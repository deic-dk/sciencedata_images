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

sed -i -E "s|, 1 => 'kube.sciencedata.dk:[0-9]+'|, 1 => 'kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php || sed -i -E "s|(0 => 'localhost',)|\1 1 => 'kube.sciencedata.dk:HTTPS_PORT',|g" /var/www/nextcloud/config/config.php
sed -i -E "s|'overwrite.cli.url' => 'https://kube.sciencedata.dk:[0-9]+'|'overwrite.cli.url' => 'https://kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php
sed -i -E "s|'overwritehost' => 'kube.sciencedata.dk:[0-9]+'|'overwritehost' => 'kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php
sed -i "s|HTTPS_PORT|$HTTPS_PORT|g" /var/www/nextcloud/config/config.php

sudo -u www touch /var/www/nextcloud/config/CAN_INSTALL

ls /var/www/nextcloud/data/.ncdata >& /dev/null || cat<< EOF > /var/www/nextcloud/data/.ncdata
# Nextcloud data directory
# Do not change this file
EOF

chown -R www:www /var/www/nextcloud/data

###

export HOSTNAME

function gracefulShutdown {
  echo "Shutting down!"
  killall caddy
  cd /var/db
  gzip owncloud.db
  curl --insecure --upload owncloud.db.gz https://sciencedata/files/owncloud.db.gz
}

# If we've mounted r/w, we use the mounted directory for data, otherwise use /var/www/nextcloud/data and add symlink 'sciencedata', pointing to the mounted directory in the user kube's homedir
df | grep :/tank/data/owncloud/ >&/dev/null
if [[ "$?" == "0" ]]; then
  # With r/o data directory we use a volatile pod dir for data, add a user kube and symlink in nfs volume
  sed -i "s|'datadirectory' => '/var/www/data'|'datadirectory' => '/var/www/nextcloud/data'|" /var/www/nextcloud/config/config.php
  sed -i -E "s|( *)('loglevel' => 1,)|\1'localstorage.allowsymlinks' => true,\n\1\2|" /var/www/nextcloud/config/config.php
  sudo -u www bash<<END
echo secret | php /var/www/nextcloud/occ maintenance:install --database sqlite
END
  sed -i -E "s|(public function validate.*)|\1\n               return;|" /var/www/nextcloud/apps/password_policy/lib/PasswordValidator.php
  sudo -u www bash -c "OC_PASS=`date | md5sum | awk '{print $1}'` php /var/www/nextcloud/occ user:add --password-from-env --display-name='kube' kube"
  sudo -u www bash -c "ls -d /var/www/nextcloud/data/kube/files || mkdir -p /var/www/nextcloud/data/kube/files"
  sudo -u www bash -c "ln -s /var/www/data /var/www/nextcloud/data/kube/files/sciencedata"
  sudo -u www bash<<END
php /var/www/nextcloud/occ app:disable dashboard
END
else
    ## With r/w data directory we reuse the DB if possible
    for i in 1 2 3 4; do
    status=`curl -I --silent --insecure https://sciencedata/files/owncloud.db.gz | grep ^HTTP | awk '{print $2}'`
    [[ $status < 400 ]] && curl -L -o /var/db/owncloud.db.gz --insecure https://sciencedata/files/owncloud.db.gz && gunzip /var/db/owncloud.db.gz && chown www:www /var/db/owncloud.db && sed -i -E "s|( *)('loglevel' => 1,)|\1'installed' => true,\n\1\2|" /var/www/nextcloud/config/config.php && break
    sleep 10
  done
fi

sudo -u www bash<<END
php /var/www/nextcloud/occ files:scan --all
END

trap gracefulShutdown EXIT
/usr/bin/caddy --config /etc/caddy/Caddyfile start

/usr/sbin/dropbear -p 22 -W 65536 -F -E
