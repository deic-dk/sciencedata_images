#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> $SD_HOME/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

service cron start

# Fixup /etc/mongod.conf to bind to my IP
myip=`ip -4 address show dev eth0 | grep " inet " | sed -E 's| +inet ([0-9\.]+)+/[0-9]+ .*|\1|'`
sed -i "s|bindIp: 127.0.0.1|bindIp: $myip,127.0.0.1|" /etc/mongod.conf
cd /tmp

# Backup MongoDB each night
echo "5 3 * * * root /usr/local/sbin/backup_mongodb.sh" > /etc/cron.d/mongodb

cat <<"EOF">> /usr/local/sbin/backup_mongodb.sh
#!/bin/bash
cd /tmp
mongosh -u admin -p secret --eval 'db.shutdownServer()'
killall mongod
tar -cvzf /mnt/mongodb.tar.gz /mnt/mongodb
curl --insecure --upload /mnt/mongodb.tar.gz https://sciencedata/files/mongodb.tar.gz
rm /mnt/mongodb.tar.gz
sudo -u mongodb mongod -f /etc/mongod.conf &
EOF

chmod +x /usr/local/sbin/backup_mongodb.sh

cd
# Create my own self-signed certificate
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout selfsigned_key.pem -out selfsigned_cert.pem -subj "/O=ScienceData/CN=`hostname`"
cat selfsigned_cert.pem selfsigned_key.pem > /etc/ssl/mongodb_certkey.pem
# Get sciencedata.dk ca certificate
curl https://sciencedata.dk/my_ca_cert.pem -o sciencedata_ca.pem
cat selfsigned_cert.pem sciencedata_ca.pem > /etc/ssl/ca_certs.pem
chown mongodb /etc/ssl/mongodb_certkey.pem /etc/mongod.conf /etc/ssl/ca_certs.pem
# Get personal certficate/key from sciencedata
sleep 10
curl --insecure --location-trusted https://$HOME_SERVER/remote.php/getcert |  jq -r .data.certificate > $SD_HOME/mycert.pem
curl --insecure --location-trusted https://$HOME_SERVER/remote.php/getkey | jq -r .data.private_key > $SD_HOME/mykey.pem
cat $SD_HOME/mycert.pem $SD_HOME/mykey.pem > $SD_HOME/mycertkey.pem
chown $SD_USER:$SD_USER $SD_HOME/*.pem

if [ -z "`ls /mnt/mongodb/WiredTiger 2>/dev/null`" ]; then
	mkdir /mnt/mongodb
	chown -R mongodb /mnt/mongodb
	# Start mongod to allow adding users
	sudo -u mongodb mongod -f /etc/mongod.conf &
	sleep 10
	# Add admin user
	mongosh admin --eval "db.createUser({user: 'admin', pwd: 'secret', roles: ['readWrite', 'userAdminAnyDatabase', { role: 'root', db: 'admin' }]})"
	# Add myself - i.e. my X.509 subject
	ssl_subject=`openssl x509 -nameopt rfc2253 -in $SD_HOME/mycert.pem -noout -subject | sed -E 's|^subject=||' | sed -E 's| +||g'`
	mongosh -u admin -p secret admin --eval "db.getSiblingDB(\"\$external\").runCommand({createUser: '$ssl_subject', roles: [{role: 'userAdminAnyDatabase', db: 'admin'}]})"
	# Show users
	mongosh -u admin -p secret --eval "db.system.users.find()"
	# Shut down
	mongosh -u admin -p secret --eval 'db.shutdownServer()'
	sudo -u mongodb killall mongod
fi

function gracefulShutdown {
  echo "Shutting down!"
  mongosh -u admin -p secret --eval "db.shutdownServer()"
  echo "Down"
}

trap gracefulShutdown EXIT
exec sudo -u mongodb  GLIBC_TUNABLES=glibc.pthread.rseq=0 numactl --interleave=all mongod -f /etc/mongod.conf &


export HOSTNAME
/usr/sbin/dropbear -p 22 -W 65536 -F -E
