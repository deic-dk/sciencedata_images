#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /var/lib/caddy/.ssh/authorized_keys
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
phpfpm=`service --status-all 2>&1 | grep php | awk '{print $NF}'`
service $phpfpm start
ln -s `basename $(ls /run/php/php*-fpm.sock)` /run/php/php-fpm.sock

###
# Nextcloud stuff
###

export HTTPS_PORT

sudo -u www bash<<END
echo secret | php /var/www/nextcloud/nextcloud/occ maintenance:install --database sqlite
END

sed -i -E "s|(0 => 'localhost',)|\1 1 => 'kube.sciencedata.dk:HTTPS_PORT',|g" /var/www/nextcloud/nextcloud/config/config.php
sed -i "s|HTTPS_PORT|$HTTPS_PORT|g" /var/www/nextcloud/nextcloud/config/config.php

sed -i "s|/var/www/nextcloud/nextcloud/data|/var/www/nextcloud/data|g" /var/www/nextcloud/nextcloud/config/config.php
mv /var/www/nextcloud/nextcloud/data/* /var/www/nextcloud/data/
rm -rf /var/www/nextcloud/nextcloud/data
ls /var/www/nextcloud/data/.ncdata 2>/dev/null || cat<< EOF > /var/www/nextcloud/data/.ncdata
# Nextcloud data directory
# Do not change this file
EOF

sudo -u www bash<<END
php /var/www/nextcloud/nextcloud/occ app:disable dashboard
php /var/www/nextcloud/nextcloud/occ files:scan admin
END

###

export HOSTNAME
/usr/bin/caddy --config /etc/caddy/Caddyfile start
/usr/sbin/dropbear -p 22 -W 65536 -F -E
