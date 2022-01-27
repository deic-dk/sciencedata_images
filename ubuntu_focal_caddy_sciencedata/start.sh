#!/bin/bash

# SSH access to root
if [ -n "$SSH_PUBLIC_KEY" ]; then
	echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
else
	echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts

# Make everything world read/writeable.
# This is to allow user www on the home silo to modify/delete files/directories in the
# directory exported and mounted as www.
# - we anyway only have one user on this system - root.
umask 000
echo "umask 000" >> ~/.bashrc

test -e /root/www/index.* || chmod go+rw "/root/index.php" &&  mv "/root/index.php" "/root/www/"
service php7.4-fpm start
service cron start
cd /root
export HOSTNAME
/usr/bin/caddy start
/usr/sbin/dropbear -p 22 -W 65536 -F -E