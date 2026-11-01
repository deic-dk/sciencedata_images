#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/jellyfin/.ssh/authorized_keys
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
  killall jellyfin; sleep 3
  cd /var/lib/jellyfin
  tar -cvzf /tmp/jellyfin_data.tar.gz data
  curl --insecure --silent --max-time 30 -o /dev/null -X MKCOL ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/
  curl --insecure --fail --upload /tmp/jellyfin_data.tar.gz $BACKUP_URL \
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

export HOSTNAME

##################
### Transmission
##################

# Add stop script for tranmission-cli
mkdir /home/jellyfin/bin
cat <<"EOF"> /home/jellyfin/bin/transmission-stop.sh
#!/bin/bash

killall transmission-cli
find /home/jellyfin/Downloads/ | grep -E '\.mkv$|\.mp4$|\.avi|\.divx|\.srt' | while read name; do
  encoded_name=`basename "$name" | tr -d '\n' | jq -sRr @uri`
  curl --insecure --globoff --upload "$name" ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Movies/$encoded_name
done
EOF

cat <<"EOF"> /home/jellyfin/bin/gettorrent.sh
#!/bin/bash

transmission-cli -f /home/jellyfin/bin/transmission-stop.sh "$@"
EOF
chown -R jellyfin:jellyfin /home/jellyfin/bin
chmod +x /home/jellyfin/bin/*.sh

##################
### Jellyfin
##################

# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi

export DST_NAME=jellyfin_data-$mount_dir.tar.gz

# The backup lives in the folder Containers in the owner's home folder - one folder
# that is easy to recognize and to leave out of sync. Earlier images kept it at the
# top level: if Containers has none, it is restored from there, and that top-level
# copy is deleted after the first backup to Containers.
BACKUP_URL=${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/$DST_NAME
OLD_BACKUP_URL=${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$DST_NAME
from_old_location=""


# Restore: keep trying while the server is unreachable; 404 = first pod, nothing to
# restore. Nothing is uploaded at shutdown unless this succeeded ($restored).
cd /var/lib/jellyfin
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
  curl -o jellyfin_data.tar.gz -L --insecure --fail $src && tar -xvzf jellyfin_data.tar.gz && { restored="restored"; [[ "$src" == "$OLD_BACKUP_URL" ]] && from_old_location=1; break; }
  sleep 10
done
echo "persistence: ${restored:-could not reach $BACKUP_URL - shutdown backup disabled}"

export PATH=$PATH:/usr/lib/jellyfin-ffmpeg
exec jellyfin --datadir /var/lib/jellyfin/data --logdir /home/jellyfin --service &

################
# Dropbear
################

/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
