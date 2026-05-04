#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/s3/.ssh/authorized_keys
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

chown -R s3:s3 /mnt/vgw

ls /mnt/vgw/data 2>/dev/null || mkdir -p /mnt/vgw/data
ls /mnt/vgw/accounts 2>/dev/null || mkdir -p /mnt/vgw/accounts
ls /mnt/vgw/versions 2>/dev/null || mkdir -p /mnt/vgw/versions
mkdir /home/s3/sidecar
if [ ! -s /mnt/vgw/versitygw.conf ]; then
	secret_key="`openssl rand -base64 16 | md5sum | awk '{print $1}'`"
	cat <<EOF>>/mnt/vgw/versitygw.conf
	VGW_BACKEND=posix
	VGW_BACKEND_ARG=/mnt/vgw/data
	VGW_VERSIONING_DIR=/mnt/vgw/versions
	ROOT_ACCESS_KEY_ID=admin
	ROOT_SECRET_ACCESS_KEY=$secret_key
	VGW_IAM_DIR=/mnt/vgw/accounts
EOF
fi

function gracefulShutdown {
  echo "Shutting down!"
  killall versitygw
  cd /tmp
  tar -cvzf versitygw.tar.gz versitygw
  curl --insecure --upload /tmp/versitygw.tar.gz https://sciencedata/files/versitygw.tar.gz
}

cd /tmp
for i in 1 2 3 4; do
  status=`curl -I --silent --insecure https://sciencedata/files/versitygw.tar.gz | grep ^HTTP | awk '{print $2}'`
  [[ $status > 399 ]] && break
  [[ $status < 400 ]] && curl -LO --insecure https://sciencedata/files/versitygw.tar.gz && tar -xvzf versitygw.tar.gz && break
  sleep 10
done

ls /tmp/versitygw 2>/dev/null || mkdir /tmp/versitygw

trap gracefulShutdown EXIT
set -a
source /mnt/vgw/versitygw.conf
set +a
exec versitygw $VGW_BACKEND --sidecar /tmp/versitygw $VGW_BACKEND_ARG &

/usr/sbin/dropbear -p 22 -W 65536 -F -E
