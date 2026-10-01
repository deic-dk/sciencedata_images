#!/bin/bash

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

service cron start

# Web terminal: ttyd served under a secret base-path = a
# capability URL, fronted by the master's per-pod TLS Caddy. tmux keeps the
# shell alive across websocket drops — ttyd's client auto-
# reconnects and re-attaches, so brief network glitches no longer kill the session.
cat << "EOF">> .tmux.conf
set -ga terminal-overrides ',xterm*:smcup@:rmcup@'
set -g history-limit 100000
set -g set-clipboard on
bind -n PageUp copy-mode -eu
# mouse OFF on purpose: with mouse tracking on, tmux grabs drag-selection and                                                                                         
# the browser can't keep a stable highlight, so native select + right-click-Copy                                                                                      
# fails. Off → browser does native selection (stays highlighted, right-click Copy                                                                                     
# works). History scrolling is still available via the PageUp binding below.                                                                                          
set -g mouse off
EOF

chown -R sciencedata:sciencedata .tmux.conf

HASH=$(tr -dc 'a-f0-9' </dev/urandom | head -c 48)
ttyd -W -p 7681 -b "/$HASH" -t disableLeaveAlert=true \
  su - sciencedata -c 'tmux new -A -s sciencedata' &
echo "$HASH/" > /tmp/URI

/usr/sbin/dropbear -p 22 -W 65536 -F -E
