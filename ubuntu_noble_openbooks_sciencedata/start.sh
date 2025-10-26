#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/openbooks/.ssh/authorized_keys
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

mkdir /home/openbooks/bin
# Add stop script for tranmission-cli
cat <<"EOF"> /home/openbooks/bin/transmission-stop.sh
#!/bin/bash

killall transmission-cli
find Downloads/ | grep -E '\.mkv$|\.mp4$|\.avi|\.divx|\.srt' | while read name; do
  encoded_name=`basename "$name" | tr -d '\n' | jq -sRr @uri`
  curl --insecure --globoff --upload "$name" https://sciencedata/files/Movies/$encoded_name
done
EOF

cat <<"EOF"> /home/openbooks/bin/gettorrent.sh
#!/bin/bash

transmission-cli -f /home/openbooks/bin/transmission-stop.sh "$@"
EOF

chown -R openbooks:openbooks /home/openbooks/bin
chmod +x /home/openbooks/bin/*


IRCNAME=`date | md5sum | cut -c1-8`
/home/openbooks/openbooks --log --debug server --no-browser-downloads -p 8080 -n o${IRCNAME} --basepath / --persist --dir /home/openbooks/ebooks/ --tls false irc.irchighway.net &

/usr/sbin/dropbear -p 22 -W 65536 -F -E
