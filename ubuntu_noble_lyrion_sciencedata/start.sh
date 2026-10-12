#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/lyrion/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

export HOSTNAME

# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi
export DST_NAME=lyrion_config-$mount_dir.tar.gz

shutting_down=""
function gracefulShutdown {
  [[ -n "$shutting_down" ]] && return
  shutting_down=1
  echo "Shutting down!"
  if [[ -z "$restored" ]]; then
    echo "no restore at start - not uploading (it would replace the backup with an empty state)"
    return
  fi
  /etc/init.d/lyrionmusicserver stop
  cd /var/lib/squeezeboxserver
  tar -cvzf /tmp/lyrion_config.tar.gz cache prefs
  curl --insecure --upload /tmp/lyrion_config.tar.gz https://sciencedata/files/$DST_NAME
}

# Restore: keep trying while the server is unreachable; 404 = first pod, nothing to
# restore. Nothing is uploaded at shutdown unless this succeeded ($restored).
cd /var/lib/squeezeboxserver
restored=""
for i in `seq 1 30`; do
  status=`curl -I --silent --insecure https://sciencedata/files/$DST_NAME | grep ^HTTP | awk '{print $2}'`
  [[ -z "$status" ]] && { sleep 10; continue; }
  if [[ "$status" -ge 400 ]]; then
    # 404 means nothing to restore - but only if the server knows this pod: a pod
    # that is not yet mapped to its owner (lookup cache on the home server) gets an
    # error too. HEAD on the folder itself tells the two apart.
    folder=`curl -I --silent --insecure https://sciencedata/files/ | grep ^HTTP | awk '{print $2}'`
    [[ "$status" == 404 && "$folder" == 2* ]] && { restored="nothing to restore"; break; }
    sleep 10; continue
  fi
  curl -L -o lyrion_config.tar.gz --insecure --fail https://sciencedata/files/$DST_NAME && tar -xvzf lyrion_config.tar.gz && { restored="restored"; break; }
  sleep 10
done
echo "persistence: ${restored:-could not reach https://sciencedata/files/$DST_NAME - shutdown backup disabled}"

# Kubernetes sends SIGTERM to this script (PID 1) and kills the container
# terminationGracePeriodSeconds later (default 30 s - set it in the pod YAML).
# Trapping TERM and waiting on dropbear in the background runs the hook at once;
# the guard in gracefulShutdown keeps the call after wait from running it twice.
trap gracefulShutdown TERM INT
/etc/init.d/lyrionmusicserver start

/usr/sbin/dropbear -p 22 -W 65536 -F -E &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown
