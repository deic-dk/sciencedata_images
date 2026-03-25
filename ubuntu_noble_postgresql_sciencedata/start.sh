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

service cron start

cd /tmp

# Backup Postgresql each night
echo "5 4 * * * root /usr/local/sbin/backup_postgresql.sh" > /etc/cron.d/mongodb

cat <<"EOF">> /usr/local/sbin/backup_postgresql.sh
#!/bin/bash
cd /tmp
service postgresql stop
tar -cvzf /mnt/postgresql.tar.gz /mnt/postgresql
curl --insecure --upload /mnt/postgresql.tar.gz https://sciencedata/files/postgresql.tar.gz
rm /mnt/postgresql.tar.gz
service postgresql start
EOF

chmod +x /usr/local/sbin/backup_postgresql.sh

# Take out IPv6 entry from /etc/hosts
sed -E "s|^([^\.]+\s+$hostname)|#\1|" /etc/hosts > /tmp/hosts
cat /tmp/hosts > /etc/hosts

cd
# Get sciencedata.dk ca certificate
curl https://sciencedata.dk/my_ca_cert.pem -o sciencedata_ca.pem
cat /etc/ssl/certs/ssl-cert-snakeoil.pem sciencedata_ca.pem > /etc/ssl/ca_certs.pem
chown postgres:postgres /etc/ssl/ca_certs.pem

# Get personal certficate/key from sciencedata
sleep 10
curl --insecure --location-trusted https://$HOME_SERVER/remote.php/getcert |  jq -r .data.certificate > $MY_HOME/mycert.pem
curl --insecure --location-trusted https://$HOME_SERVER/remote.php/getkey | jq -r .data.private_key > $MY_HOME/mykey.pem
chown $MY_USER:$MY_USER $MY_HOME/*.pem

service postgresql stop
if [ -z "`ls /mnt/postgresql/16 2>/dev/null`" ]; then
	mkdir /mnt/postgresql
	chown postgres:postgres /mnt/postgresql
	cp -a /var/lib/postgres/16 /mnt/postgresql/
fi
service postgresql start

# Create user
cn=`openssl x509 -in mycert.pem -noout -subject -nameopt compat | sed -E 's|.+/CN=(.+)/.+|\1|'`
sudo su - postgres -c "createuser --superuser $cn"

function gracefulShutdown {
  echo "Shutting down!"
  service postgresql stop
  echo "Down"
}

trap gracefulShutdown EXIT
/usr/sbin/dropbear -p 22 -W 65536 -F -E
