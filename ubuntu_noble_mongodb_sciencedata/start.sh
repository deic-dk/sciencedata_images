#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> $MY_HOME/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

# The shutdown hook is installed FIRST: kubernetes sends SIGTERM to this script
# (PID 1), and a signal that arrives while start.sh is still in its start-up loops
# (restore, certificate fetch, install) must stop the pod too - PID 1 ignores a
# signal it has no handler for, and the pod would then run on until the grace
# period kills it. Variables the hook uses are empty until set below; harmless.
shutting_down=""
function gracefulShutdown {
  [[ -n "$shutting_down" ]] && return
  shutting_down=1
  echo "Shutting down!"
  mongosh -u admin -p secret --eval "db.shutdownServer()"
  echo "Down"
  # Ends the script here, also when the signal arrives while start.sh is still
  # running (otherwise start.sh would go on to the end before the pod could stop)
  exit 0
}
# Kubernetes sends SIGTERM to this script (PID 1) and kills the container
# terminationGracePeriodSeconds later (default 30 s - set it in the pod YAML).
# Trapping TERM and waiting on dropbear in the background runs the hook at once;
# the guard in gracefulShutdown keeps the call after wait from running it twice.
trap gracefulShutdown TERM INT


service cron start

# Fixup /etc/mongod.conf to bind to my IP
myip=`ip -4 address show dev eth0 | grep " inet " | sed -E 's| +inet ([0-9\.]+)+/[0-9]+ .*|\1|'`
sed -i "s|bindIp: 127.0.0.1|bindIp: $myip,127.0.0.1|" /etc/mongod.conf
cd /tmp

cd
# Create my own self-signed certificate
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout selfsigned_key.pem -out selfsigned_cert.pem -subj "/O=ScienceData/CN=`hostname`"
cat selfsigned_cert.pem selfsigned_key.pem > /etc/ssl/mongodb_certkey.pem
# Get sciencedata.dk ca certificate
curl https://sciencedata.dk/my_ca_cert.pem -o sciencedata_ca.pem
cat selfsigned_cert.pem sciencedata_ca.pem > /etc/ssl/ca_certs.pem
chown mongodb /etc/ssl/mongodb_certkey.pem /etc/mongod.conf /etc/ssl/ca_certs.pem
# Get personal certficate/key from sciencedata
# The home server maps this pod to its owner only once it knows the pod (the
# lookup is cached, negative answers too): a single request right after start can
# get a 4xx. Retry until a certificate arrives, up to 5 minutes.
for i in `seq 1 30`; do
	curl --insecure --location-trusted --silent --fail ${HOME_SERVER_PROTOCOL:-https}://$HOME_SERVER/remote.php/getcert | jq -r .data.certificate > $MY_HOME/mycert.pem 2>/dev/null
	grep -q 'BEGIN CERTIFICATE' $MY_HOME/mycert.pem 2>/dev/null && break
	sleep 10
done
grep -q 'BEGIN CERTIFICATE' $MY_HOME/mycert.pem 2>/dev/null || echo "WARNING: could not fetch the owner's certificate from ${HOME_SERVER_PROTOCOL:-https}://$HOME_SERVER/remote.php/getcert"
curl --insecure --location-trusted --silent --fail ${HOME_SERVER_PROTOCOL:-https}://$HOME_SERVER/remote.php/getkey | jq -r .data.private_key > $MY_HOME/mykey.pem
cat $MY_HOME/mycert.pem $MY_HOME/mykey.pem > $MY_HOME/mycertkey.pem
chown $MY_USER:$MY_USER $MY_HOME/*.pem

# Names in the owner's home folder matching $1 (PROPFIND; the old servers answer
# no HEAD on a collection, PROPFIND they do).
list_dumps() {
	curl -X PROPFIND -H 'Depth: 1' --silent --insecure --max-time 30 ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/ | grep -o -E '<d:href>[^<]*</d:href>' | sed -E 's|<d:href>.*/([^/]*)</d:href>|\1|' | grep -E "^$1$"
}
# Fetch the newest dump from the owner's home folder into $1. Retries while the
# home server does not know this pod yet (owner lookup cache); a 404 counts only
# when the folder itself answers 2xx. Returns 0 with the file, 1 with nothing.
fetch_dump() {
	local url="$1" out="$2" status folder
	for i in `seq 1 30`; do
		status=`curl -I --silent --insecure --max-time 30 $url | grep ^HTTP | awk '{print $2}'`
		[[ -z "$status" ]] && { sleep 10; continue; }
		if [[ "$status" -ge 400 ]]; then
			folder=`curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/`
			[[ "$status" == 404 && "$folder" == 2* ]] && { echo "no dump at $url - fresh database"; return 1; }
			sleep 10; continue
		fi
		curl -L --silent --insecure --fail -o "$out" $url && return 0
		sleep 10
	done
	echo "WARNING: could not fetch $url - starting with a fresh database"
	return 1
}

# Persistence (only with a disk type, i.e. when /mnt is a mounted volume; without a
# type the database is ephemeral, as the image description says):
#  - a nightly logical dump (mongodump --archive --gzip, consistent while running)
#    as a dedicated backup user, uploaded to the owner's home folder as
#    mongodb-dump.archive.gz - Nextcloud's file versioning keeps the history;
#  - on a first start with an empty disk, the newest dump is restored (all
#    databases except the users/roles of the admin db: the admin password is then
#    the image default again and the backup user is recreated).
if mountpoint -q /mnt; then
	cat <<'EOF' > /usr/local/sbin/dump_mongodb.sh
#!/bin/bash
# Nightly logical dump of the owner's databases to the owner's home folder, one
# archive per database (Nextcloud keeps the versions). Authenticates with the
# owner's own X.509 identity (the certificate user the image creates), so it dumps
# exactly the databases that identity may read; no extra MongoDB user.
# UPLOAD=no dumps into /tmp and reports without uploading (test).
MY_HOME=${MY_HOME:-/home/sciencedata}
pem=$MY_HOME/mycertkey.pem
[ -f "$pem" ] || { echo "`date '+%F %T'` dump_mongodb: no $pem"; exit 1; }
dbs=`mongosh --quiet --tls --tlsCertificateKeyFile "$pem" --tlsAllowInvalidCertificates --authenticationMechanism MONGODB-X509 --authenticationDatabase '$external' --eval 'db.adminCommand({listDatabases:1, authorizedDatabases:true}).databases.map(d=>d.name).join("\n")' 2>/dev/null`
[ -n "$dbs" ] || { echo "`date '+%F %T'` dump_mongodb: cannot list databases with $pem"; exit 1; }
rc=0
for d in $dbs; do
	case "$d" in admin|config|local) continue;; esac
	tmp=/tmp/mongodb-dump-$d.$$.archive.gz
	if ! mongodump --quiet --ssl --sslPEMKeyFile "$pem" --tlsInsecure --authenticationMechanism MONGODB-X509 --authenticationDatabase '$external' --db "$d" --archive="$tmp" --gzip; then
		echo "`date '+%F %T'` dump_mongodb: mongodump of $d failed"; rm -f "$tmp"; rc=1; continue
	fi
	if [ "$UPLOAD" = "no" ]; then
		echo "`date '+%F %T'` dump_mongodb: $d -> `stat -c %s "$tmp"` bytes (not uploaded, test)"
	elif curl --insecure --silent --fail --upload-file "$tmp" "${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/mongodb-dump-$d.archive.gz"; then
		echo "`date '+%F %T'` dump_mongodb: $d -> uploaded `stat -c %s "$tmp"` bytes as mongodb-dump-$d.archive.gz"
	else
		echo "`date '+%F %T'` dump_mongodb: upload of $d failed"; rc=1
	fi
	rm -f "$tmp"
done
exit $rc
EOF
	chmod 755 /usr/local/sbin/dump_mongodb.sh
	echo "5 3 * * * root /usr/local/sbin/dump_mongodb.sh >> /var/log/mongodb_dump.log 2>&1" > /etc/cron.d/mongodb_dump
fi

if [ -z "`ls /mnt/mongodb/WiredTiger 2>/dev/null`" ]; then
	mkdir /mnt/mongodb
	chown -R mongodb /mnt/mongodb
	# Start mongod to allow adding users
	sudo -u mongodb mongod -f /etc/mongod.conf &
	sleep 10
	# Add admin user
	mongosh admin --eval "db.createUser({user: 'admin', pwd: 'secret', roles: ['readWrite', 'userAdminAnyDatabase', { role: 'root', db: 'admin' }]})"
	# Restore the newest dumps (one archive per database, mongodb-dump-<db>.archive.gz
	# in the owner's home folder), if the disk is a mounted volume and dumps exist.
	if mountpoint -q /mnt; then
		for name in `list_dumps 'mongodb-dump-.*\.archive\.gz'`; do
			if fetch_dump "${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$name" /tmp/restore.archive.gz; then
				mongorestore --quiet -u admin -p secret --authenticationDatabase admin --archive=/tmp/restore.archive.gz --gzip --drop && echo "restored $name"
				rm -f /tmp/restore.archive.gz
			fi
		done
	fi
	# Add myself - i.e. my X.509 subject
	ssl_subject=`openssl x509 -nameopt rfc2253 -in $MY_HOME/mycert.pem -noout -subject | sed -E 's|^subject=||' | sed -E 's| +||g'`
	mongosh -u admin -p secret admin --eval "db.getSiblingDB(\"\$external\").runCommand({createUser: '$ssl_subject', roles: [{role: 'userAdminAnyDatabase', db: 'admin'}, {role: 'readWriteAnyDatabase', db: 'admin'}, {role: 'dbAdminAnyDatabase', db: 'admin'}, {role: 'backup', db: 'admin'}]})"
	# Show users
	mongosh -u admin -p secret --eval "db.system.users.find()"
	# Shut down
	mongosh -u admin -p secret --eval 'db.shutdownServer()'
	sudo -u mongodb killall mongod
fi


exec sudo -u mongodb  GLIBC_TUNABLES=glibc.pthread.rseq=0 numactl --interleave=all mongod -f /etc/mongod.conf &


export HOSTNAME
/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
