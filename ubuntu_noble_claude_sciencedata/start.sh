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
BACKUP_URL="https://sciencedata/files/$DST_NAME"

# Persistence: /home/claude/.claude* is saved to the owner's home folder every hour
# and at shutdown, and restored when the pod starts. A backup cut short cannot do
# harm: the archive is on the pod's own disk and goes with it, and Nextcloud
# discards an upload that ends before its declared length. Two things do matter:
#  - one backup runs at a time (the hourly cron and the shutdown hook can coincide);
#  - nothing is uploaded until the restore at start has succeeded, or the server
#    has said there is nothing to restore - otherwise a pod started while the
#    server was unreachable would overwrite the real backup with an empty one.
# tar exits 1 when a file changed while being read (claude appends to its
# transcript continuously); that archive is fine, only exit codes above 1 are errors.
cat << EOF > /usr/local/sbin/claude_backup
#!/bin/bash
BACKUP_URL="$BACKUP_URL"
[ -f /run/claude_restored ] || { echo "claude_backup: no restore yet - not uploading"; exit 1; }
exec 9>/run/claude_backup.lock
flock -w 900 9 || { echo "claude_backup: another backup is still running"; exit 1; }
cd /home/claude || exit 1
tmp=/tmp/claude_backup.\$\$.tar.gz
tar --warning=no-file-changed -czf "\$tmp" .claude*
rc=\$?
if [ \$rc -gt 1 ]; then echo "claude_backup: tar failed (\$rc)"; rm -f "\$tmp"; exit 1; fi
if curl --insecure --silent --fail --upload-file "\$tmp" "\$BACKUP_URL"; then
	echo "claude_backup: \`date '+%F %T'\` saved \`stat -c %s "\$tmp"\` bytes to \$BACKUP_URL"
	rm -f "\$tmp"
else
	echo "claude_backup: \`date '+%F %T'\` upload failed"; rm -f "\$tmp"; exit 1
fi
EOF
chmod +x /usr/local/sbin/claude_backup

cat << EOF > /etc/cron.hourly/claude_backup
#!/bin/bash
/usr/local/sbin/claude_backup >> /var/log/claude_backup.log 2>&1
EOF
chmod +x /etc/cron.hourly/claude_backup

service cron start

# Restore. Keep trying while the server is unreachable (a pod may start during a
# hiccup); a 404 means a first pod with nothing to restore. If this gives up, the
# pod runs without persistence and claude_backup says so in its log.
cd /home/claude
restored=""
for i in `seq 1 30`; do
  status=`curl -I --silent --insecure $BACKUP_URL | grep ^HTTP | awk '{print $2}'`
  if [[ -z "$status" ]]; then
    sleep 10; continue
  fi
  if [[ "$status" -ge 400 ]]; then
    # 404 means nothing to restore - but only if the server knows this pod: a pod
    # that is not yet mapped to its owner (lookup cache on the home server) gets an
    # error too. HEAD on the folder itself tells the two apart.
    folder=`curl -I --silent --insecure https://sciencedata/files/ | grep ^HTTP | awk '{print $2}'`
    [[ "$status" == 404 && "$folder" == 2* ]] && { restored="nothing to restore"; break; }
    sleep 10; continue
  fi
  if curl -L --silent --insecure --fail -o claude.tar.gz $BACKUP_URL && tar -xzf claude.tar.gz; then
    restored="restored"; break
  fi
  sleep 10
done
if [[ -n "$restored" ]]; then
  echo "claude persistence: $restored"
  touch /run/claude_restored
else
  echo "claude persistence: could not reach $BACKUP_URL - backups disabled for this pod"
fi
rm -f claude.tar.gz
chown -R claude:claude .claude* 2>/dev/null

# Shutdown: kubernetes sends SIGTERM to this script (PID 1); the trap runs a last
# backup, then stops the ssh daemon so the script ends. The pod's YAML must give
# it time (terminationGracePeriodSeconds) - the default 30 s is not enough for
# tar + upload of a large .claude. Running dropbear in the background and
# waiting on it makes the trap fire at once instead of after dropbear exits.
shutting_down=""
function gracefulShutdown {
  [[ -n "$shutting_down" ]] && return
  shutting_down=1
  echo "Shutting down!"
  /usr/local/sbin/claude_backup
  kill $DROPBEAR_PID 2>/dev/null
  exit 0
}
trap gracefulShutdown TERM INT

# Web terminal: ttyd served under a secret base-path = a
# capability URL, fronted by the master's per-pod TLS Caddy. tmux keeps the
# shell (and `claude`) alive across websocket drops — ttyd's client auto-
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

chown -R claude:claude .tmux.conf

HASH=$(tr -dc 'a-f0-9' </dev/urandom | head -c 48)
ttyd -W -p 7681 -b "/$HASH" -t disableLeaveAlert=true \
  su - claude -c 'tmux new -A -s claude' &
echo "$HASH/" > /tmp/URI

/usr/sbin/dropbear -p 22 -W 65536 -F -E &
DROPBEAR_PID=$!
wait $DROPBEAR_PID
# dropbear ended by itself: save before the container exits
gracefulShutdown
