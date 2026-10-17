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
  service postgresql stop
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

cd /tmp

# Take out IPv6 entry from /etc/hosts
sed -E "s|^([^\.]+\s+$hostname)|#\1|" /etc/hosts > /tmp/hosts
cat /tmp/hosts > /etc/hosts

# Create new snakeoil cert with current hostname as CN
make-ssl-cert generate-default-snakeoil --force-overwrite

cd
# Get sciencedata.dk ca certificate
curl https://sciencedata.dk/my_ca_cert.pem -o sciencedata_ca.pem
cat /etc/ssl/certs/ssl-cert-snakeoil.pem sciencedata_ca.pem > /etc/ssl/ca_certs.pem
chown postgres:postgres /etc/ssl/ca_certs.pem

# Get personal certficate/key from sciencedata
# The home server maps this pod to its owner only once it knows the pod (the
# lookup is cached, negative answers too): a single request right after start can
# get a 4xx. Retry until a certificate arrives, up to 5 minutes.
for i in `seq 1 30`; do
	curl --insecure --location-trusted --silent --fail https://$HOME_SERVER/remote.php/getcert | jq -r .data.certificate > $MY_HOME/mycert.pem 2>/dev/null
	grep -q 'BEGIN CERTIFICATE' $MY_HOME/mycert.pem 2>/dev/null && break
	sleep 10
done
grep -q 'BEGIN CERTIFICATE' $MY_HOME/mycert.pem 2>/dev/null || echo "WARNING: could not fetch the owner's certificate from https://$HOME_SERVER/remote.php/getcert"
curl --insecure --location-trusted --silent --fail https://$HOME_SERVER/remote.php/getkey | jq -r .data.private_key > $MY_HOME/mykey.pem
chown $MY_USER:$MY_USER $MY_HOME/*.pem
chmod go-rw $MY_USER:$MY_USER $MY_HOME/*.pem

# Fetch the newest dump from the owner's home folder into $1. Retries while the
# home server does not know this pod yet (owner lookup cache); a 404 counts only
# when the folder itself answers 2xx. Returns 0 with the file, 1 with nothing.
fetch_dump() {
	local url="$1" out="$2" status folder
	for i in `seq 1 30`; do
		status=`curl -I --silent --insecure --max-time 30 $url | grep ^HTTP | awk '{print $2}'`
		[[ -z "$status" ]] && { sleep 10; continue; }
		if [[ "$status" -ge 400 ]]; then
			folder=`curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' https://sciencedata/files/`
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
# type the database is ephemeral): a nightly pg_dumpall (consistent while running,
# roles included) uploaded to the owner's home folder as postgresql-dump.sql.gz -
# Nextcloud's file versioning keeps the history - and, on a first start with an
# empty disk, the newest dump is restored into the fresh cluster.
if mountpoint -q /mnt; then
	cat <<'EOF' > /usr/local/sbin/dump_postgresql.sh
#!/bin/bash
tmp=/tmp/postgresql-dump.$$.sql.gz
if sudo -u postgres pg_dumpall | gzip > "$tmp" && [ -s "$tmp" ]; then
	if curl --insecure --silent --fail --upload-file "$tmp" https://sciencedata/files/postgresql-dump.sql.gz; then
		echo "`date '+%F %T'` dump_postgresql: uploaded `stat -c %s "$tmp"` bytes"
	else
		echo "`date '+%F %T'` dump_postgresql: upload failed"
	fi
else
	echo "`date '+%F %T'` dump_postgresql: pg_dumpall failed"
fi
rm -f "$tmp"
EOF
	chmod 755 /usr/local/sbin/dump_postgresql.sh
	echo "5 4 * * * root /usr/local/sbin/dump_postgresql.sh >> /var/log/postgresql_dump.log 2>&1" > /etc/cron.d/postgresql_dump
fi

service postgresql stop
fresh=""
if [ -z "`ls /mnt/postgresql/16 2>/dev/null`" ]; then
	mkdir /mnt/postgresql
	chown postgres:postgres /mnt/postgresql
	cp -a /var/lib/postgresql/16 /mnt/postgresql/
	fresh=yes
fi
service postgresql start
if [ -n "$fresh" ] && mountpoint -q /mnt && fetch_dump https://sciencedata/files/postgresql-dump.sql.gz /tmp/restore.sql.gz; then
	sleep 5
	gunzip -c /tmp/restore.sql.gz | sudo -u postgres psql -q postgres > /dev/null && echo "restored postgresql-dump.sql.gz"
	rm -f /tmp/restore.sql.gz
fi

# Create user
export cn=`openssl x509 -in $MY_HOME/mycert.pem -noout -subject -nameopt compat | sed -E 's|.+/CN=(.+)/.+|\1|'`
sudo su - postgres -c "createuser --superuser $cn"


/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
