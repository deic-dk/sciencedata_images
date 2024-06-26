#!/bin/bash

###

runSSH(){
# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata sciencedata.dk" >> /etc/hosts
# Route traffic to ScienceData over the internal network.
# Resolve all fully qualified silo names to local addresses - this in order to allow proper SSL handshake and client certificate auth
echo "10.2.0.13 sciencedata.dk" >> /etc/hosts
echo "10.2.0.14 silo1.sciencedata.dk" >> /etc/hosts
echo "10.2.0.15 silo2.sciencedata.dk" >> /etc/hosts
echo "10.2.0.16 silo3.sciencedata.dk" >> /etc/hosts
echo "10.2.0.17 silo4.sciencedata.dk" >> /etc/hosts
echo "10.2.0.18 silo5.sciencedata.dk" >> /etc/hosts
echo "10.2.0.19 silo6.sciencedata.dk" >> /etc/hosts
echo "10.2.0.20 silo7.sciencedata.dk" >> /etc/hosts
echo "10.2.0.21 silo8.sciencedata.dk" >> /etc/hosts
echo "10.2.0.22 silo9.sciencedata.dk" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

service cron start

/usr/sbin/dropbear -p 22 -W 65536 -F -E
}

cd

env | grep SD_UID >> .bashrc
env | grep HOME_SERVER >> .bashrc
env | grep ONLY_FROM >> .bashrc
env | grep SSL_DN_HEADER >> .bashrc
env | grep TRUSTED_VOS >> .bashrc
env | grep RTE_URLS >> .bashrc

# Get personal certficate/key from sciencedata
cat << EOF >> .bashrc
if [ ! -e $HOME/.gridfactory/userkey.pem ]; then
mkdir $HOME/.gridfactory
curl --insecure --location-trusted https://$HOME_SERVER/remote.php/getcert | jq -r .data.certificate > $HOME/.gridfactory/usercert.pem
curl --insecure --location-trusted https://$HOME_SERVER/remote.php/getkey | jq -r .data.private_key > $HOME/.gridfactory/userkey_unenc.pem
# Encrypt the key
openssl rsa -des3 -in .gridfactory/userkey_unenc.pem -passin "pass:" -passout "pass:grid" > $HOME/.gridfactory/userkey.pem
fi
EOF

if [[ -n "$RTE_URLS" ]]; then
  sed -E -i "s|RTE_URLS *= *$|RTE_URLS = $RTE_URLS|" /etc/gridfactory.conf
fi

if [[ -n "$TRUSTED_VOS" ]]; then
  sed -E -i "s|MY_VOS *= *(.*)$|MY_VOS = \1 $TRUSTED_VOS|" /etc/gridfactory.conf
fi

# Set the mysql password
echo "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'grid';" | \
mysql -uroot

TRUSTED_VOS="$TRUSTED_VOS" GRID_USER=www-data MY_HOSTNAME=`hostname` LOCAL_USER_DN="/CN=$SD_UID/O=sciencedata.dk" \
KEY_PASSWORD=grid LOCAL_USER_KEY_PASSWORD=grid MY_DB_USERNAME=root MY_DB_PASSWORD=grid NO_DB_PASSWORD=no \
/usr/share/gridfactory/configure_services.sh -y

if [[ -n "$ONLY_FROM" && -n "$SSL_DN_HEADER" ]]; then
  sed -E -i "s|#DNHeader.*|DNHeader $SSL_DN_HEADER|" /etc/apache2/sites-available/grid.conf
  sed -E -i "s|#OnlyFrom.*|OnlyFrom $ONLY_FROM|" /etc/apache2/sites-available/grid.conf
fi

service apache2 restart

runSSH
