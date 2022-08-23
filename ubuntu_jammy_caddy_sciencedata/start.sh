#!/bin/bash

# SSH access to root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
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

###### Begin generate new ssh_host keys
rm /etc/ssh/ssh_host*
ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
ssh-keygen -t rsa -N '' -f /etc/ssh/ssh_host_rsa_key
#get fingerprints
printf "ed25519\t%s\nrsa\t%s" $(ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub | sed -E 's|.*SHA256:(.*) root.*|\1|') \
$(ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub | sed -E 's|.*SHA256:(.*) root.*|\1|') >/tmp/hostkeys
###### End generate new ssh_host keys

# Try to get service name installed by `apt-get install php-fpm`, and default to "php8.1-fpm"
installed_php_fpm=$(service --status-all 2> /dev/null | grep "php[0-9][.][0-9]-fpm" | sed -E 's/.*(php[0-9][.][0-9]-fpm).*/\1/')
if [[ -z $installed_php_fpm ]]; then
    installed_php_fpm="php8.1-fpm"
fi
service "$installed_php_fpm" start
sed -i "s/INSTALLED_PHP_FPM/$installed_php_fpm/" /root/Caddyfile
sed -i "s/INSTALLED_PHP_FPM/$installed_php_fpm/" /root/index.php

# if an index file isn't present in the presistent storage, then use the default index.php
[[ -e /root/www/index.* ]] || chmod go+rw "/root/index.php" &&  mv "/root/index.php" "/root/www/"

service cron start
cd /root
export HOSTNAME
/usr/bin/caddy start
/usr/sbin/sshd -D
