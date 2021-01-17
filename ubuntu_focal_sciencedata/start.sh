#!/bin/bash

if [ -n "$SSH_PUBLIC_KEY" ]; then
	echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
else
	echo "root:$ROOT_PASSWORD" | chpasswd;
fi
test -e "/root/www/$HOSTNAME" || \
mkdir -p "/root/www/$HOSTNAME" && mv /root/index.php "/root/www/$HOSTNAME"
service php7.4-fpm start
cd /root
export HOSTNAME
# Didn't find a way to get this set...
#export SSH_PORT
/usr/bin/caddy start
/usr/sbin/dropbear -p 22 -W 65536 -F -E