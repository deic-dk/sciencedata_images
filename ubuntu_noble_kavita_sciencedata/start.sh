#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/kavita/.ssh/authorized_keys
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

function gracefulShutdown {
  echo "Shutting down!"
  cd /home/kavita/Kavita
  tar -cvzf /tmp/kavita_config.tar.gz config
  curl --insecure --upload /tmp/kavita_config.tar.gz https://sciencedata/files/kavita_config.tar.gz
}

cd /home/kavita/Kavita
for i in 1 2 3 4; do
  status=`curl -I --silent --insecure https://sciencedata/files/kavita_config.tar.gz | grep ^HTTP | awk '{print $2}'`
  [[ $status < 400 ]] && curl -LO --insecure https://sciencedata/files/kavita_config.tar.gz && tar -xvzf kavita_config.tar.gz && break
  sleep 10
done

trap gracefulShutdown EXIT
exec ./Kavita &

/usr/sbin/dropbear -p 22 -W 65536 -F -E
