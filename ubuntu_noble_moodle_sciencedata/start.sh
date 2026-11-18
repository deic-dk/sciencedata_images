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
# (restore, install) must stop the pod too - PID 1 ignores a signal it has no
# handler for, and the pod would then run on until the grace period kills it.
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
  /usr/local/sbin/moodle_backup.sh \
    && [[ -n "$from_old_location" ]] && curl --insecure --silent --max-time 30 -o /dev/null -X DELETE $OLD_BACKUP_URL
  # Ends the script here, also when the signal arrives while start.sh is still
  # running (otherwise start.sh would go on to the end before the pod could stop)
  exit 0
}
trap gracefulShutdown TERM INT

service cron start
phpfpm=`service --status-all 2>&1 | grep php | awk '{print $NF}'`
cat <<"EOF">/etc/php/8.3/fpm/conf.d/99-sciencedata-uploads.ini
max_execution_time = 3600
max_input_time = 3600
EOF
service $phpfpm start
ln -s `basename $(ls /run/php/php*-fpm.sock)` /run/php/php-fpm.sock

export HOSTNAME

# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi

export DST_NAME=moodle_db-$mount_dir.sql.gz

# The backup lives in the folder Containers in the owner's home folder (as for the
# other images). The top-level place is only looked at for symmetry with them.
BACKUP_URL=${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/$DST_NAME
OLD_BACKUP_URL=${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME
from_old_location=""
cat <<EOF > /etc/moodle_backup.env
BACKUP_URL='$BACKUP_URL'
HOME_SERVER_PROTOCOL='${HOME_SERVER_PROTOCOL:-https}'
EOF

# The public address, from the port kube's reverse proxy got for this pod
if [[ -n "$HTTPS_PORT" ]]; then
  wwwroot="https://kube.sciencedata.dk:$HTTPS_PORT"
else
  wwwroot="http://localhost"
fi
sed -i -E "s|^\\\$CFG->wwwroot *= *'[^']*';|\$CFG->wwwroot   = '$wwwroot';|" /var/www/moodle/config.php

##################
# PostgreSQL - in the pod, with Moodle preinstalled (see the Dockerfile)
##################

service postgresql start
until sudo -u postgres pg_isready -q; do sleep 1; done

# Restore: keep trying while the server is unreachable; 404 = first pod, nothing to
# restore. Nothing is uploaded at shutdown unless this succeeded ($restored).
cd /var/cache/moodle
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
    # error too. PROPFIND on the folder itself tells the two apart.
    folder=`curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/`
    [[ "$status" == 404 && "$folder" == 2* ]] && { restored="nothing to restore"; break; }
    sleep 10; continue
  fi
  curl -L -o moodle_db.sql.gz --insecure --fail $src && { restored="restored"; [[ "$src" == "$OLD_BACKUP_URL" ]] && from_old_location=1; break; }
  sleep 10
done
echo "persistence: ${restored:-could not reach $BACKUP_URL - shutdown backup disabled}"

if [[ "$restored" == "restored" ]]; then
  gunzip -c moodle_db.sql.gz | sudo -u www psql -q moodle >/dev/null
  rm -f moodle_db.sql.gz
fi

##################
# Moodle's files
##################

# Course files etc. go to the mounted ScienceData folder. It must be writable
# (a folder under /storage/); with a read-only mount (/files/) the files stay in
# the pod (the seed folder) - fine for a quick look, lost when the pod is deleted.
if sudo -u www touch /var/moodledata/.moodle_write_test 2>/dev/null; then
  rm -f /var/moodledata/.moodle_write_test
  # A new site: the files the preinstalled database refers to. Never over an
  # existing site's files (copied as www: root's writes to NFS are squashed).
  if [[ "$restored" != "restored" && ! -d /var/moodledata/filedir ]]; then
    sudo -u www cp -r /var/moodledata-seed/. /var/moodledata/
  fi
else
  echo "WARNING: /var/moodledata is not writable - Moodle's files stay in the pod and are lost with it"
  sed -i "s|'/var/moodledata'|'/var/moodledata-seed'|" /var/www/moodle/config.php
fi
datadir=$(sed -n -E "s|^\\\$CFG->dataroot *= *'([^']*)';.*|\1|p" /var/www/moodle/config.php)

# A newer image may carry newer Moodle code: bring the database up to it (a no-op otherwise)
sudo -u www php /var/www/moodle/admin/cli/upgrade.php --non-interactive

if [[ "$restored" != "restored" ]]; then
  # A new site from the preinstalled database: its own password and identifier
  adminpass="$ADMIN_PASSWORD"
  if [[ -z "$adminpass" ]]; then
    adminpass=`head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 16`A1!
  fi
  adminemail="$SD_UID"
  [[ "$adminemail" == *@* ]] || adminemail="admin@localhost.localdomain"
  sudo -u www php /var/www/moodle/admin/cli/reset_password.php --username=admin --password="$adminpass" --ignore-password-policy
  sudo -u www psql -q moodle -c "UPDATE mdl_user SET email='$adminemail' WHERE username='admin'"
  sudo -u www php /var/www/moodle/admin/cli/cfg.php --name=supportemail --set="$adminemail"
  sudo -u www php /var/www/moodle/admin/cli/cfg.php --name=siteidentifier --set="`head -c 24 /dev/urandom | md5sum | cut -c1-32`kube.sciencedata.dk"
  # The password is shown once in the pod log and kept in the data root (the
  # owner's ScienceData folder), never in the database backup
  echo "$adminpass" > $datadir/admin_password.txt && chown www:www $datadir/admin_password.txt && chmod 600 $datadir/admin_password.txt
  echo "New Moodle site. Log in at $wwwroot/ as admin; the password is in admin_password.txt in the mounted folder."
fi

# An hourly backup too, so a pod that stops without a clean shutdown loses at most an hour
[[ -n "$restored" ]] && echo "17 * * * * root /usr/local/sbin/moodle_backup.sh >> /var/log/moodle_backup.log 2>&1" > /etc/cron.d/moodle_backup

sudo -u www php /var/www/moodle/admin/cli/purge_caches.php

/usr/bin/caddy --config /etc/caddy/Caddyfile start

/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
