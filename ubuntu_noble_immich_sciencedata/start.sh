#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /var/lib/immich/home/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && sudo bash -c 'echo "'$HOME_SERVER'	sciencedata" >> /etc/hosts'
[[ -n $HOME_SERVER ]] && sudo bash -c 'echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"'$HOME_SERVER'	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts'
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
  cd /var/lib/immich/home
  pg_dump -c immich | gzip > immich_data.sql.gz
  curl --insecure --upload immich_data.sql.gz https://sciencedata/files/$DST_NAME
  # Ends the script here, also when the signal arrives while start.sh is still
  # running (otherwise start.sh would go on to the end before the pod could stop)
  exit 0
}
# Kubernetes sends SIGTERM to this script (PID 1) and kills the container
# terminationGracePeriodSeconds later (default 30 s - set it in the pod YAML).
# Trapping TERM and waiting on dropbear in the background runs the hook at once;
# the guard in gracefulShutdown keeps the call after wait from running it twice.
trap gracefulShutdown TERM INT


sudo service cron start

export HOSTNAME
# For run_pod to set NFS_VOLUME_PATH requires setting the environment variable NFS_VOLUME_PATH (to "") in the YAML.
# This may have been forgotten by the YAML author, so we fall back to using df.
if [ -z "$NFS_VOLUME_PATH" ]; then
	mount_path=`df | grep :/ | awk '{print $1}'`
	mount_dir=`basename $mount_path`
else
	mount_dir=`basename "$NFS_VOLUME_PATH"`
fi

export DST_NAME=immich_data-$mount_dir.sql.gz

##################
# Reddis
##################

sudo /etc/init.d/redis-server start

##################
# Postgresql
##################

sudo /etc/init.d/postgresql start

##################
### Immich
##################


# Re-establish DB
# Restore: keep trying while the server is unreachable; 404 = first pod, nothing to
# restore. Nothing is uploaded at shutdown unless this succeeded ($restored).
cd /var/lib/immich/home
restored=""
for i in `seq 1 30`; do
  status=`curl -I --silent --insecure --max-time 30 https://sciencedata/files/$DST_NAME | grep ^HTTP | awk '{print $2}'`
  [[ -z "$status" ]] && { sleep 10; continue; }
  if [[ "$status" -ge 400 ]]; then
    # 404 means nothing to restore - but only if the server knows this pod: a pod
    # that is not yet mapped to its owner (lookup cache on the home server) gets an
    # error too. HEAD on the folder itself tells the two apart.
    folder=`curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' https://sciencedata/files/`
    [[ "$status" == 404 && "$folder" == 2* ]] && { restored="nothing to restore"; break; }
    sleep 10; continue
  fi
  curl -L -o immich_data.sql.gz --insecure --fail https://sciencedata/files/$DST_NAME && { restored="restored"; break; }
  sleep 10
done
echo "persistence: ${restored:-could not reach https://sciencedata/files/$DST_NAME - shutdown backup disabled}"
if [ -e immich_data.sql.gz ]; then
	gunzip immich_data.sql.gz
	if [ -s immich_data.sql ]; then
		psql immich < immich_data.sql
	fi
fi

IMMICH_PATH=/var/lib/immich

READ_ONLY=`df -hT | grep nfs4 | grep '/tank/data' | awk '{print $NF}'`
if [ "$READ_ONLY" ]; then
	# Disable upload if NFS volume  is mounted r/w
	sed -i "s|</head>|<style>#dashboard-navbar button:nth-child(2) {display: none;}</style>\n<script>\ndocument.body.addEventListener('dragenter',function(event){event.stopPropagation();}, true);window.addEventListener('load',function(){var buttons=document.getElementsByTagName('button');for(var i=0;i<buttons.length;i++){if(buttons[i].textContent.trim()=='Upload'){buttons[i].style.display='none';break;}}});\n</script>\n</head>|" /var/lib/immich/app/www/index.html
	export UPLOAD_LOCATION=upload
else
	if [ ! -e "/var/lib/immich/home/media/upload" ]; then
		# Create upload folder in NFS volume if it is mounted r/w
		mkdir "/var/lib/immich/home/media/upload"
	fi
	export UPLOAD_LOCATION=$IMMICH_PATH/home/media/upload
fi

chown -R immich:immich $IMMICH_PATH

# Run Immich
export PATH=/usr/lib/jellyfin-ffmpeg:$PATH
set -a
: "${IMMICH_HOST=`ip a show dev eth0 | grep -oP '(?:\b\.?(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){4}' | head -1`}"
: "${DB_PASSWORD=secret}"
: "${NODE_ENV=production}"
: "${DB_USERNAME=immich}"
: "${DB_DATABASE_NAME=immich}"
: "${IMMICH_VERSION=release}"
: "${DB_HOSTNAME=127.0.0.1}"
: "${IMMICH_MACHINE_LEARNING_URL=http://127.0.0.1:3003}"
: "${REDIS_HOSTNAME=127.0.0.1}"

cd /var/lib/immich/app
IMMICH_PORT=2283 node dist/main >& /tmp/immich.log &

# Run machine-learning
cd /var/lib/immich/app/machine-learning
. venv/bin/activate
: "${MACHINE_LEARNING_WORKERS:=1}"
: "${MACHINE_LEARNING_HTTP_KEEPALIVE_TIMEOUT_S:=2}"
: "${MACHINE_LEARNING_WORKER_TIMEOUT:=300}"
: "${MACHINE_LEARNING_CACHE_FOLDER:=/var/lib/immich/cache}"
: "${TRANSFORMERS_CACHE:=/var/lib/immich/cache}"
gunicorn immich_ml.main:app \
  -k immich_ml.config.CustomUvicornWorker \
  -c immich_ml/gunicorn_conf.py \
  -b 127.0.0.1:3003 \
  -w "$MACHINE_LEARNING_WORKERS" \
  -t "$MACHINE_LEARNING_WORKER_TIMEOUT" \
  --keep-alive "$MACHINE_LEARNING_HTTP_KEEPALIVE_TIMEOUT_S" \
  --graceful-timeout 10 \
  --daemon &

################
# Dropbear
################

sudo /usr/sbin/dropbear -p 22 -W 65536 -F -E >& /tmp/dropbear.log &
wait $!
# dropbear ended by itself: run the hook before the container exits
gracefulShutdown

