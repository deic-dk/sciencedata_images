#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /home/claude/.ssh/authorized_keys
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

export DST_NAME=claude-$mount_dir.tar.gz

function gracefulShutdown {
  echo "Shutting down!"
  cd /home/claude
  tar -cvzf /tmp/claude.tar.gz .claude*
  curl --insecure --upload /tmp/claude.tar.gz https://sciencedata/files/$DST_NAME
}

cat << EOF > /etc/cron.hourly/claude_backup
#!/bin/bash

cd /home/claude && tar -cvzf /tmp/claude.tar.gz .claude* && curl --insecure --upload /tmp/claude.tar.gz https://sciencedata/files/$DST_NAME
EOF
chmod +x /etc/cron.hourly/claude_backup

service cron start

cd /home/claude 
for i in 1 2 3 4; do
  status=`curl -I --silent --insecure https://sciencedata/files/$DST_NAME | grep ^HTTP | awk '{print $2}'`
  [[ $status < 400 ]] && curl -L -o claude.tar.gz --insecure https://sciencedata/files/$DST_NAME && tar -xvzf claude.tar.gz && break
  sleep 10
done
chown -R claude:claude .claude*

trap gracefulShutdown EXIT

# Web terminal: ttyd served under a secret base-path = a
# capability URL, fronted by the master's per-pod TLS Caddy. tmux keeps the
# shell (and `claude`) alive across websocket drops — ttyd's client auto-
# reconnects and re-attaches, so brief network glitches no longer kill the session.
cat << "EOF">> .tmux.conf
set -ga terminal-overrides ',xterm*:smcup@:rmcup@'
set -g history-limit 100000
set -g mouse on
bind -n PageUp copy-mode -eu
EOF

chown -R claude:claude .tmux.conf

HASH=$(tr -dc 'a-f0-9' </dev/urandom | head -c 48)
ttyd -W -p 7681 -b "/$HASH" -t disableLeaveAlert=true \
  su - claude -c 'tmux new -A -s claude' &
echo "$HASH/" > /tmp/URI

/usr/sbin/dropbear -p 22 -W 65536 -F -E
