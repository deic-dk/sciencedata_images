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
  curl --insecure --globoff --upload "$name" https://sciencedata/files/Movies/$encoded_name
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

function gracefulShutdown {
  echo "Shutting down!"
  cd /var/lib/jellyfin
  tar -cvzf /tmp/jellyfin_data.tar.gz data
  curl --insecure --upload /tmp/jellyfin_data.tar.gz https://sciencedata/files/jellyfin_data.tar.gz
}

cd /var/lib/jellyfin
for i in 1 2 3 4; do
  status=`curl -I --silent --insecure https://sciencedata/files/jellyfin_data.tar.gz | grep ^HTTP | awk '{print $2}'`
  [[ $status < 400 ]] && curl -LO --insecure https://sciencedata/files/jellyfin_data.tar.gz && tar -xvzf jellyfin_data.tar.gz && break
  sleep 10
done

trap gracefulShutdown EXIT
export PATH=$PATH:/usr/lib/jellyfin-ffmpeg
exec jellyfin --datadir /var/lib/jellyfin/data --logdir /home/jellyfin --service &

################
# Dropbear
################

/usr/sbin/dropbear -p 22 -W 65536 -F -E
