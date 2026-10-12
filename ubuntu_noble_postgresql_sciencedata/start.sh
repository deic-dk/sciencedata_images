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

service postgresql stop
if [ -z "`ls /mnt/postgresql/16 2>/dev/null`" ]; then
	mkdir /mnt/postgresql
	chown postgres:postgres /mnt/postgresql
	cp -a /var/lib/postgresql/16 /mnt/postgresql/
fi
service postgresql start

# Create user
export cn=`openssl x509 -in $MY_HOME/mycert.pem -noout -subject -nameopt compat | sed -E 's|.+/CN=(.+)/.+|\1|'`
sudo su - postgres -c "createuser --superuser $cn"

shutting_down=""
function gracefulShutdown {
  [[ -n "$shutting_down" ]] && return
  shutting_down=1
  echo "Shutting down!"
  service postgresql stop
  echo "Down"
}

# Kubernetes sends SIGTERM to this script (PID 1) and kills the container
# terminationGracePeriodSeconds later (default 30 s - set it in the pod YAML).
# Trapping TERM and waiting on dropbear in the background runs the hook at once;
# the guard in gracefulShutdown keeps the call after wait from running it twice.
trap gracefulShutdown TERM INT
/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
