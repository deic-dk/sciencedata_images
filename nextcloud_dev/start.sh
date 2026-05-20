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

# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi

export DST_NAME=owncloud.db-dev-$mount_dir.gz

export NC_VERSION=34.0.0rc1

function gracefulShutdown {
  echo "Shutting down!"
  killall caddy
  cd /tmp
  gzip owncloud.db
  curl --insecure --upload owncloud.db.gz https://sciencedata/files/$DST_NAME
}

###
# Nextcloud stuff
###


# If Nextcloud isn't present in NFS storage, install it
if [ ! -e /var/www/nextcloud ]; then
	sudo -u www NC_VERSION=$NC_VERSION bash<<"END"
	#tar -xzf /tmp/nextcloud.tar.gz --no-same-owner
	git clone https://github.com/nextcloud/server.git --branch v$NC_VERSION --depth 1 /tmp/nextcloud || exit 1
	cd /tmp/nextcloud
	git submodule update --init
	cd apps
	git clone --depth 1 https://github.com/nextcloud/viewer.git
	echo "Copying over from /tmp..."
	cp -a /tmp/nextcloud/ /var/www/nextcloud/
	curl -L -o /tmp/config.php https://silo2.sciencedata.dk/public/kubefiles_public/nextcloud/nextcloud-config.php
	cp /tmp/config.php /var/www/nextcloud/config/config.php
	#cd && rm -rf  /tmp/nextcloud /tmp/config.php
	sed -i "s|'datadirectory' => .*,|'datadirectory' => '/var/www/data',|g" /var/www/nextcloud/config/config.php
	touch /var/www/nextcloud/config/CAN_INSTALL
	ls -d /var/www/data 2>/dev/null || ( mkdir /var/www/data && ln -s /tmp/owncloud.db /var/www/data/ )
	ls /var/www/data/.ncdata 2>/dev/null || ( echo "# Nextcloud data directory" > /var/www/data/.ncdata && echo "# Do not change this file" >> /var/www/data/.ncdata )
	echo secret | php /var/www/nextcloud/occ maintenance:install --data-dir=/var/www/data --database sqlite
	oc_version=`grep 'OC_Version ' /var/www/nextcloud/version.php | sed -E 's|.* array\((.*)\);|\1|' | sed -E 's|.* \[(.*)\];|\1|' | sed 's|, *|.|g'`
	sed -i "s|OC_VERSION|\$oc_version|" /var/www/nextcloud/config/config.php
END
fi

touch /var/log/nextcloud.log && chown www:www /var/log/nextcloud.log

sudo -u www HTTPS_PORT=$HTTPS_PORT DST_NAME=$DST_NAME bash<<END
export HTTPS_PORT
sed -i -E "s|(0 => 'localhost',)|\1 1 => 'kube.sciencedata.dk:HTTPS_PORT',|g" /var/www/nextcloud/config/config.php
sed -i -E "s|'overwrite.cli.url' => 'https://kube.sciencedata.dk:[0-9]+'|'overwrite.cli.url' => 'https://kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php
sed -i -E "s|'overwritehost' => 'kube.sciencedata.dk:[0-9]+'|'overwritehost' => 'kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php
sed -i "s|HTTPS_PORT|$HTTPS_PORT|g" /var/www/nextcloud/config/config.php

for i in 1 2 3 4 5 6; do
	sleep 10
	status=`curl --connect-timeout 120 -I --insecure https://sciencedata/files/$DST_NAME | grep ^HTTP | awk '{print $2}'`
	echo "Getting DB https://sciencedata/files/$DST_NAME \$i --> \$status"
	curl -L -o /tmp/owncloud.db.gz --insecure https://sciencedata/files/$DST_NAME && gunzip /tmp/owncloud.db.gz && cp -a /tmp/owncloud.db /tmp/owncloud.db.bk && [[ -s /tmp/owncloud.db ]] && sed -i -E "s|( *)('loglevel' => 1,)|\1'installed' => true,\n\1\2|" /var/www/nextcloud/config/config.php && break
done

php /var/www/nextcloud/occ app:disable dashboard
php /var/www/nextcloud/occ files:scan admin
END

###

service cron start

phpfpm=`service --status-all 2>&1 | grep php | awk '{print $NF}'`
service $phpfpm start
ln -s `basename $(ls /run/php/php*-fpm.sock)` /run/php/php-fpm.sock

export HOSTNAME
trap gracefulShutdown EXIT
/usr/bin/caddy --config /etc/caddy/Caddyfile start
/usr/sbin/dropbear -p 22 -W 65536 -F -E
