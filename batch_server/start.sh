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
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
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

GRID_USER=www-data MY_HOSTNAME=`hostname` LOCAL_USER_DN="/CN=$SD_UID/O=sciencedata.dk" \
KEY_PASSWORD=grid LOCAL_USER_KEY_PASSWORD=grid MY_DB_USERNAME=root NO_DB_PASSWORD=yes \
/usr/share/gridfactory/configure_services.sh -y

if [[ -n "$ONLY_FROM" && -n "$SSL_DN_HEADER" ]]; then
  sed -E -i "s|#DNHeader.*|DNHeader $SSL_DN_HEADER|" /etc/apache2/sites-available/grid.conf
  sed -E -i "s|#OnlyFrom.*|OnlyFrom $ONLY_FROM|" /etc/apache2/sites-available/grid.conf
fi

runSSH
