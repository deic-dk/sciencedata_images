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

# The shutdown hook is installed FIRST: kubernetes sends SIGTERM to this script
# (PID 1), and a signal that arrives while start.sh is still in its start-up loops
# (restore, certificate fetch, install) must stop the pod too - PID 1 ignores a
# signal it has no handler for, and the pod would then run on until the grace
# period kills it. Variables the hook uses are empty until set below; harmless.
shutting_down=""
function gracefulShutdown {
  [[ -n "$shutting_down" ]] && return
  shutting_down=1
  echo "Shutting down!"
  if [[ -z "$restored" ]]; then
    echo "no restore at start - not uploading (it would replace the backup with an empty state)"
    return
  fi
  killall caddy
  cd /var/db
  gzip -f owncloud.db
  curl --insecure --silent --max-time 30 -o /dev/null -X MKCOL ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/
  curl --insecure --fail --upload owncloud.db.gz $BACKUP_URL \
    && [[ -n "$from_old_location" ]] && curl --insecure --silent --max-time 30 -o /dev/null -X DELETE $OLD_BACKUP_URL
  # Ends the script here, also when the signal arrives while start.sh is still
  # running (otherwise start.sh would go on to the end before the pod could stop)
  exit 0
}
# Kubernetes sends SIGTERM to this script (PID 1) and kills the container
# terminationGracePeriodSeconds later (default 30 s - set it in the pod YAML).
# Trapping TERM and waiting on dropbear in the background runs the hook at once;
# the guard in gracefulShutdown keeps the call after wait from running it twice.
trap gracefulShutdown TERM INT


service cron start
phpfpm=`service --status-all 2>&1 | grep php | awk '{print $NF}'`
cat <<"EOF">/etc/php/8.3/fpm/conf.d/99-sciencedata-uploads.ini
max_execution_time = 3600
max_input_time = 3600
EOF
chown www:www /etc/php/8.3/fpm/conf.d/99-sciencedata-uploads.ini
service $phpfpm start
ln -s `basename $(ls /run/php/php*-fpm.sock)` /run/php/php-fpm.sock

## Modify Caddyfile, so the header X-Forwarded-For is trusted and client IP is set correctly and not to 10.2.12.1
cat <<"EOF">/etc/caddy/Caddyfile
{
	servers {
		trusted_proxies static 10.2.12.1
	}
}

:80 {
	# Set this path to your site's directory.
	root * /var/www/nextcloud

	# files_picocms pretty URLs
	@picocms path /sites /sites/* /users /users/*
	rewrite @picocms /remote.php{uri}

	# Enable the static file server.
	file_server

	# Serve the PHP site through php-fpm.
	php_fastcgi unix//run/php/php-fpm.sock

	log {
		output file /var/log/caddy.log
	}
}
EOF


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

# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi

export DST_NAME=owncloud.db-$mount_dir.gz

# The backup lives in the folder Containers in the owner's home folder - one folder
# that is easy to recognize and to leave out of sync. Earlier images kept it at the
# top level: if Containers has none, it is restored from there, and that top-level
# copy is deleted after the first backup to Containers.
BACKUP_URL=${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/$DST_NAME
OLD_BACKUP_URL=${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME
from_old_location=""


# If we've mounted r/w, we use the mounted directory for data, otherwise use /var/www/nextcloud/data and add symlink 'sciencedata', pointing to the mounted directory in the user kube's homedir
df | grep :/tank/data/owncloud/ >&/dev/null
if [[ "$?" == "0" ]]; then
  # With r/o data directory we use a volatile pod dir for data, add a user kube and symlink in nfs volume
  sed -i "s|'datadirectory' => '/var/www/data'|'datadirectory' => '/var/www/nextcloud/data'|" /var/www/nextcloud/config/config.php
  sed -i -E "s|( *)('loglevel' => 1,)|\1'localstorage.allowsymlinks' => true,\n\1\2|" /var/www/nextcloud/config/config.php
  restored="fresh install"
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
  ## With r/w data directory we reuse the DB if possible. Keep trying while the
  ## server is unreachable; 404 = first pod, nothing to restore. Nothing is
  ## uploaded at shutdown unless this succeeded ($restored).
  restored=""
  for i in `seq 1 30`; do
    status=`curl -I --silent --insecure --max-time 30 $BACKUP_URL | grep ^HTTP | awk '{print $2}'`
    src=$BACKUP_URL
    if [[ "$status" == 404 ]]; then
      old_status=`curl -I --silent --insecure --max-time 30 $OLD_BACKUP_URL | grep ^HTTP | awk '{print $2}'`
      [[ "$old_status" == 200 ]] && { status=200; src=$OLD_BACKUP_URL; }
    fi
    [[ -z "$status" ]] && { sleep 10; continue; }
    if [[ "$status" -ge 400 ]]; then
    # 404 means nothing to restore - but only if the server knows this pod: a pod
    # that is not yet mapped to its owner (lookup cache on the home server) gets an
    # error too. HEAD on the folder itself tells the two apart.
    folder=`curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/`
    [[ "$status" == 404 && "$folder" == 2* ]] && { restored="nothing to restore"; break; }
    sleep 10; continue
  fi
    curl -L -o /var/db/owncloud.db.gz --insecure --fail $src && gunzip /var/db/owncloud.db.gz && chown www:www /var/db/owncloud.db && sed -i -E "s|( *)('loglevel' => 1,)|\1'installed' => true,\n\1\2|" /var/www/nextcloud/config/config.php && { restored="restored"; [[ "$src" == "$OLD_BACKUP_URL" ]] && from_old_location=1; break; }
    sleep 10
  done
  echo "persistence: ${restored:-could not reach $BACKUP_URL - shutdown backup disabled}"
fi

sudo -u www bash<<END
php /var/www/nextcloud/occ files:scan --all
END

/usr/bin/caddy --config /etc/caddy/Caddyfile start

# SSH with keys only; passwords only if a root password was set explicitly
# (ROOT_PASSWORD, for standalone docker run). The pods' SSH ports get root
# password guessing from the internet.
DROPBEAR_AUTH="-s"; [ -n "$ROOT_PASSWORD" ] && DROPBEAR_AUTH=""
/usr/sbin/dropbear $DROPBEAR_AUTH -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
