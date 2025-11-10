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

sudo service cron start

export HOSTNAME

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

function gracefulShutdown {
  echo "Shutting down!"
  cd /var/lib/immich/home
  pg_dump -c immich | gzip > immich_data.sql.gz
  
  curl --insecure --upload immich_data.sql.gz https://sciencedata/files/immich_data.sql.gz
}

# Re-establish DB
cd /var/lib/immich/home
for i in 1 2 3 4; do
  status=`curl -I --silent --insecure https://sciencedata/files/immich_data.sql.gz | grep ^HTTP | awk '{print $2}'`
  [[ $status < 400 ]] && curl -LO --insecure https://sciencedata/files/immich_data.sql.gz && break
  sleep 3
done
if [ -e immich_data.sql.gz ]; then
	gunzip immich_data.sql.gz
	if [ -s immich_data.sql ]; then
		psql immich < immich_data.sql
	fi
fi


READ_ONLY=`df -hT | grep nfs4 | grep '/tank/data' | awk '{print $NF}'`
if [ "$READ_ONLY" ]; then
	# Disable upload if NFS volume  is mounted r/w
	sed -i "s|</head>|<style>#dashboard-navbar button:nth-child(2) {display: none;}</style>\n<script>\ndocument.body.addEventListener('dragenter',function(event){event.stopPropagation();}, true);window.addEventListener('load',function(){var buttons=document.getElementsByTagName('button');for(var i=0;i<buttons.length;i++){if(buttons[i].textContent.trim()=='Upload'){buttons[i].style.display='none';break;}}});\n</script>\n</head>|" /var/lib/immich/app/www/index.html
	UPLOAD_LOCATION=upload
else
	if [ ! -e "/var/lib/immich/home/media/upload" ]; then
		# Create upload folder in NFS volume if it is mounted r/w
		mkdir "/var/lib/immich/home/media/upload"
	fi
	export UPLOAD_LOCATION=/var/lib/immich/home/media/upload
fi

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

trap gracefulShutdown EXIT
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

sudo /usr/sbin/dropbear -p 22 -W 65536 -F -E >& /tmp/dropbear.log

