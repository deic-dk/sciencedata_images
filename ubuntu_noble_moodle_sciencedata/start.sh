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
; teachers upload course material through the ScienceData folder activity
upload_max_filesize = 4G
post_max_size = 4G
max_file_uploads = 100
EOF
# PHP-FPM workers from the CPUs this pod gets: Ubuntu's default (5) made Moodle queue
# requests long before the CPU was busy (load test 2026-11-25, 200 students at once on a
# 4-core node: 5 workers 21 req/s and ~8 s per page, 16 workers 35 req/s and ~5 s).
# 4 per core, between 8 and 64; a CPU limit on the pod (cgroup cpu.max) counts first.
cores=$(nproc)
if read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null && [ "$quota" != "max" ]; then
	cores=$(( (quota + period - 1) / period ))
fi
workers=$(( cores * 4 )); [ $workers -lt 8 ] && workers=8; [ $workers -gt 64 ] && workers=64
pool=$(ls /etc/php/*/fpm/pool.d/www.conf | head -1)
sed -i -E "s/^pm.max_children = .*/pm.max_children = $workers/; \
	s/^pm.start_servers = .*/pm.start_servers = $(( workers / 4 ))/; \
	s/^pm.min_spare_servers = .*/pm.min_spare_servers = $(( workers / 8 ))/; \
	s/^pm.max_spare_servers = .*/pm.max_spare_servers = $(( workers / 2 ))/" "$pool"
echo "PHP-FPM: $workers workers for $cores CPUs"
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
# Browsers keep cookies per host name, not per port: all pods on the host share
# them. A session cookie of its own (MoodleSession<port>), or two Moodles - or
# the one before this - log each other out ("Your session has timed out").
sed -i -E "s|^\\\$CFG->sessioncookie *= *'[^']*';|\$CFG->sessioncookie = '${HTTPS_PORT:-}';|" /var/www/moodle/config.php

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
fi

# Logging in with ScienceData accounts: the Containers app gives the pod a
# login client (its address is only known now, so the pod asks; authenticated
# as its owner by the pod network's address login) - restricted to a group's
# members, or for just the owner. The owner logs in as admin, no password.
# 503: the pod is not yet in the container list - ask again; 404: the
# Containers app is too old to know about it.
login=""
if [[ -n "$HOME_SERVER" ]]; then
  for i in `seq 1 30`; do
    login=$(curl -s --insecure --max-time 20 -w '\n%{http_code}' "${HOME_SERVER_PROTOCOL:-https}://sciencedata/index.php/apps/user_pods/api/pod-login?callback=/admin/oauth2callback.php")
    code=${login##*$'\n'}; login=${login%$'\n'*}
    echo "$login" | grep -q '"oidc"' && break
    login=""
    [[ "$code" == 404 ]] && break
    sleep 10
  done
fi
oidc=""
rm -f /etc/cron.d/moodle_cohorts
if echo "$login" | grep -q '"oidc":true' && echo "$login" | sudo -u www php /usr/local/sbin/sciencedata_oidc.php "$SD_UID"; then
  oidc=1
  # each group that logs in = a cohort with its members (accounts made in
  # advance), kept up to date every 5 minutes - courses enrol a group by cohort sync
  if echo "$login" | grep -q '"groups":\[[^]]'; then
    sudo -u www php /usr/local/sbin/sciencedata_cohorts.php "$SD_UID"
    echo "*/5 * * * * www php /usr/local/sbin/sciencedata_cohorts.php '$SD_UID' >/dev/null 2>&1" > /etc/cron.d/moodle_cohorts
  fi
else
  sudo -u www php /usr/local/sbin/sciencedata_oidc.php --off
  echo "login: Moodle's own accounts only (${login:-no answer from the Containers app})"
fi

# Course material: the folder 'Course material' in the owner's ScienceData files
# - an ordinary folder (web interface, sync client; shared with the course's
# group for the students) - in Moodle's file picker (repository_sciencedata),
# read over WebDAV from inside the pod (the pod network's address login). Made
# if missing, with a subfolder per login group, shared read-only with that group
# (sciencedata_course_folders.php). And ScienceData share links in course text shown as previews,
# players and cards (filter_sciencedata), for the ScienceData servers known
# here: the login server and this pod's home server.
sdbase="${HOME_SERVER_PROTOCOL:-https}://sciencedata"
davurl="$sdbase/files"
rm -f /etc/cron.d/moodle_transcode
if [[ -n "$HOME_SERVER" ]]; then
  echo "$login" | php /usr/local/sbin/sciencedata_course_folders.php "$sdbase"
  # videos in the course folders that browsers cannot play as they are get a web
  # version (.web/<name>.mp4) - one video at a time, at low priority
  echo "*/5 * * * * www flock -n /tmp/sciencedata_transcode.lock php /usr/local/sbin/sciencedata_transcode.php '$davurl' >> /var/cache/moodle/transcode.log 2>&1" > /etc/cron.d/moodle_transcode
fi
sdhosts="sciencedata.dk"
issuer=$(echo "$login" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("issuer",""))' 2>/dev/null)
for u in "$issuer" "$PUBLIC_HOME_SERVER"; do
  h=${u#*://}; h=${h%%/*}; h=${h%%:*}
  [[ -n "$h" && " $sdhosts " != *" $h "* ]] && sdhosts="$sdhosts $h"
done
sudo -u www php /usr/local/sbin/sciencedata_setup.php "$sdhosts" "$davurl"

# Without ScienceData login, until the administrator has logged in once (also
# after a restart): the container's link on the Containers page (/tmp/URI, a
# path after the pod's address) is Moodle's own "set password" page for admin -
# a password-reset token, as in Moodle's "Forgotten your password?" mail. Moodle
# lets such a token live 30 minutes; a cron job keeps it fresh until it is used
# (Moodle then deletes it and logs admin in). Otherwise the link is the login page.
uri="login/index.php"
rm -f /etc/cron.d/moodle_admin_link
if [[ -z "$oidc" && "$(sudo -u www psql -tAq moodle -c "SELECT currentlogin FROM mdl_user WHERE username='admin'")" == 0 ]]; then
  token=`head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32`
  sudo -u www psql -q moodle -c "DELETE FROM mdl_user_password_resets WHERE userid=(SELECT id FROM mdl_user WHERE username='admin')"
  sudo -u www psql -q moodle -c "INSERT INTO mdl_user_password_resets (userid, timerequested, timererequested, token) SELECT id, extract(epoch FROM now())::bigint, 0, '$token' FROM mdl_user WHERE username='admin'"
  echo "*/5 * * * * www psql -tAq moodle -c \"UPDATE mdl_user_password_resets SET timerequested=extract(epoch FROM now())::bigint WHERE token='$token'\" >/dev/null 2>&1" > /etc/cron.d/moodle_admin_link
  uri="login/forgot_password.php?token=$token"
  echo "Moodle: the administrator (admin) sets a password through the container's link on the Containers page."
fi

# An hourly backup too, so a pod that stops without a clean shutdown loses at most an hour
[[ -n "$restored" ]] && echo "17 * * * * root /usr/local/sbin/moodle_backup.sh >> /var/log/moodle_backup.log 2>&1" > /etc/cron.d/moodle_backup

sudo -u www php /var/www/moodle/admin/cli/purge_caches.php

/usr/bin/caddy --config /etc/caddy/Caddyfile start
# the Containers page shows "Starting..." until this exists (catalog/wait-for-token)
echo "$uri" > /tmp/URI

# SSH with keys only; passwords only if a root password was set explicitly
# (ROOT_PASSWORD, for standalone docker run). The pods' SSH ports get root
# password guessing from the internet.
DROPBEAR_AUTH="-s"; [ -n "$ROOT_PASSWORD" ] && DROPBEAR_AUTH=""
/usr/sbin/dropbear $DROPBEAR_AUTH -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
