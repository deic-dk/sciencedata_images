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
  if [[ ! -f /tmp/nc_restored ]]; then
    echo "no restore at start - not uploading (it would replace the backup with an empty state)"
    return
  fi
  killall caddy
  /usr/local/sbin/backup_nextcloud_db.sh
  # Ends the script here, also when the signal arrives while start.sh is still
  # running (otherwise start.sh would go on to the end before the pod could stop)
  exit 0
}
# Kubernetes sends SIGTERM to this script (PID 1) and kills the container
# terminationGracePeriodSeconds later (default 30 s - set it in the pod YAML).
# Trapping TERM and waiting on dropbear in the background runs the hook at once;
# the guard in gracefulShutdown keeps the call after wait from running it twice.
trap gracefulShutdown TERM INT


# Nextcloud cronjob
echo "*/5 * * * * www /usr/bin/php -f /var/www/nextcloud/cron.php >/dev/null 2>&1" > /etc/cron.d/nextcloud

# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi

export DST_NAME=owncloud.db-dev-$mount_dir.gz

export NC_VERSION=34.0.2


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
# 'sciencedata' is the Host header the users' pods send (their /etc/hosts aliases HOME_SERVER = this pod's address to it)
grep -q "'sciencedata'," /var/www/nextcloud/config/config.php || sed -i -E "s|(0 => 'localhost',)|\1 9 => 'sciencedata',|" /var/www/nextcloud/config/config.php
sed -i -E "s|'overwrite.cli.url' => 'https://kube.sciencedata.dk:[0-9]+'|'overwrite.cli.url' => 'https://kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php
sed -i -E "s|'overwritehost' => 'kube.sciencedata.dk:[0-9]+'|'overwritehost' => 'kube.sciencedata.dk:HTTPS_PORT'|g" /var/www/nextcloud/config/config.php
sed -i "s|HTTPS_PORT|$HTTPS_PORT|g" /var/www/nextcloud/config/config.php

# Restore: keep trying while the server is unreachable; 404 = first pod, nothing to
# restore. Nothing is uploaded at shutdown unless /tmp/nc_restored exists.
for i in \`seq 1 30\`; do
	sleep 10
	status=\`curl --connect-timeout 120 --max-time 150 -I --silent --insecure ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME | grep ^HTTP | awk '{print \$2}'\`
	echo "Getting DB ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME \$i --> \$status"
	[[ -z "\$status" ]] && continue
	if [[ "\$status" -ge 400 ]]; then
		# 404 = nothing to restore, but only if the server knows this pod (owner lookup cache): HEAD on the folder tells the two apart
		folder=\`curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/\`
		[[ "\$status" == 404 && "\$folder" == 2* ]] && { touch /tmp/nc_restored; break; }
		continue
	fi
	curl -L -o /tmp/owncloud.db.gz --insecure --fail ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME && gunzip /tmp/owncloud.db.gz && cp -a /tmp/owncloud.db /tmp/owncloud.db.bk && [[ -s /tmp/owncloud.db ]] && sed -i -E "s|( *)('loglevel' => 1,)|\1'installed' => true,\n\1\2|" /var/www/nextcloud/config/config.php && { touch /tmp/nc_restored; break; }
done

php /var/www/nextcloud/occ app:disable dashboard
php /var/www/nextcloud/occ files:scan admin
END

cat <<"EOF"> /etc/caddy/Caddyfile
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

	# canonical public links: /shared/<token> -> NC share page (same as the Apache image rewrite)
	@shared path_regexp shared ^/shared/([^/]+)/?$
	redir @shared /index.php/s/{re.shared.1} 302

	# pods: /files and /grid are the legacy WebDAV of the logged-in user, served by
	# files_sharding's legacydav.php - the same rewrite Apache does on the boxes.
	# Caddy keeps the original URI in REQUEST_URI, which legacydav.php relies on.
	@legacydav path /files /files/* /grid /grid/*
	rewrite @legacydav /apps/files_sharding/appinfo/legacydav.php

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

# Outbound mail (invoices, notifications, resets). Needs MAIL_SMTPHOST, MAIL_SMTPNAME, MAIL_SMTPPASSWORD
# set in the SETUP_SCRIPT pointed to in the web UI. SETUP_SCRIPT needs to be specified by it's full path
# as seen from inside the pod, e.g. /var/www/setup.sh
if [[ -n "$MAIL_SMTPHOST" ]]; then
  sudo -u www \
    MAIL_SMTPHOST="$MAIL_SMTPHOST" MAIL_SMTPPORT="${MAIL_SMTPPORT:-587}" \
    MAIL_SMTPNAME="$MAIL_SMTPNAME" MAIL_SMTPPASSWORD="$MAIL_SMTPPASSWORD" \
    MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS:-no-reply}" MAIL_DOMAIN="${MAIL_DOMAIN:-sciencedata.dk}" \
    bash <<'END'                                                            
  O="php /var/www/nextcloud/occ"                                            
  $O config:system:set mail_smtpmode     --value smtp                       
  $O config:system:set mail_smtphost     --value "$MAIL_SMTPHOST"
  $O config:system:set mail_smtpport     --value "$MAIL_SMTPPORT" --type integer
  $O config:system:set mail_smtpsecure   --value tls
  $O config:system:set mail_smtpauth     --value true --type boolean        
  $O config:system:set mail_smtpname     --value "$MAIL_SMTPNAME"
  $O config:system:set mail_smtppassword --value "$MAIL_SMTPPASSWORD"       
  $O config:system:set mail_from_address --value "$MAIL_FROM_ADDRESS"
  $O config:system:set mail_domain       --value "$MAIL_DOMAIN"             
END
fi

# The database lives in /tmp (SQLite must not sit on NFS); it is uploaded to the owner's
# home server at a graceful shutdown AND every night, so a pod that is killed or a node
# that is lost costs at most a day (a silo2 dev pod ran five months without a single
# backup before this). An online copy via sqlite3 .backup, so the file is consistent.
cat <<"EOF" > /usr/local/sbin/backup_nextcloud_db.sh
#!/bin/bash
# Upload a consistent copy of /tmp/owncloud.db as $DST_NAME to the owner's home server.
[[ -f /tmp/nc_restored ]] || { echo "no restore at start - not uploading (it would replace the backup with an empty state)"; exit 0; }
[[ -s /tmp/owncloud.db ]] || { echo "no database"; exit 0; }
cd /tmp && rm -f owncloud.db.copy && sqlite3 owncloud.db ".backup owncloud.db.copy" && gzip -f owncloud.db.copy \
  && curl --insecure --silent --fail --upload-file owncloud.db.copy.gz ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME \
  && echo "$(date -Is) uploaded $DST_NAME" || echo "$(date -Is) upload of $DST_NAME FAILED"
EOF
chmod +x /usr/local/sbin/backup_nextcloud_db.sh
echo "35 3 * * * root HOME_SERVER_PROTOCOL=${HOME_SERVER_PROTOCOL:-https} DST_NAME=$DST_NAME /usr/local/sbin/backup_nextcloud_db.sh >> /var/log/nextcloud_db_backup.log 2>&1" > /etc/cron.d/nextcloud_db_backup
chmod 644 /etc/cron.d/nextcloud_db_backup
service cron start

phpfpm=`service --status-all 2>&1 | grep php | awk '{print $NF}'`
service $phpfpm start
ln -s `basename $(ls /run/php/php*-fpm.sock)` /run/php/php-fpm.sock

export HOSTNAME
/usr/bin/caddy --config /etc/caddy/Caddyfile start
/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
