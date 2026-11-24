#!/bin/bash

# This image has no URI to add to the pod's web address: tell run_pod so at once,
# instead of letting it ask for /tmp/URI for half an hour (and log each miss).
touch /tmp/URI.none

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/sciencedata/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

# Update yt-dlp
/home/sciencedata/bin/yt-dlp -U

# Write cronjobs running mounted cron scripts
cat << "EOF" >> /etc/cron.hourly/user_scripts
#!/bin/bash
ls /home/sciencedata/mnt/cron.hourly/*.sh | while read name; do
  echo running "$name"
  chmod +x "$name"
  su - sciencedata "$name"
done
EOF
cat << "EOF" >> /etc/cron.daily/user_scripts
#!/bin/bash
ls /home/sciencedata/mnt/cron.daily/*.sh | while read name; do
  echo running "$name"
  chmod +x "$name"
  su - sciencedata "$name"
done
EOF
cat << "EOF" >> /etc/cron.weekly/user_scripts
ls /home/sciencedata/mnt/cron.weekly/*.sh | while read name; do
  echo running "$name"
  su - sciencedata "$name"
done
EOF
cat << "EOF" >> /etc/cron.monthly/user_scripts
#!/bin/bash
ls /home/sciencedata/mnt/cron.monthly/*.sh | while read name; do
  echo running "$name"
  chmod +x "$name"
  su - sciencedata "$name"
done
EOF

chmod +x /etc/cron.*/user_scripts

service cron start

# SSH with keys only; passwords only if a root password was set explicitly
# (ROOT_PASSWORD, for standalone docker run). The pods' SSH ports get root
# password guessing from the internet.
DROPBEAR_AUTH="-s"; [ -n "$ROOT_PASSWORD" ] && DROPBEAR_AUTH=""
/usr/sbin/dropbear $DROPBEAR_AUTH -p 22 -W 65536 -F -E
