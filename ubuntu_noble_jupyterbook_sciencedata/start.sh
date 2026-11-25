#!/bin/bash

# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	echo "$SSH_PUBLIC_KEY" >> /var/lib/caddy/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	echo "root:$ROOT_PASSWORD" | chpasswd
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

# What the build script needs to know (it runs as www, without this environment)
cat > /etc/sciencedata_book.env <<ENV
HOME_SERVER='$HOME_SERVER'
HOME_SERVER_PROTOCOL='${HOME_SERVER_PROTOCOL:-https}'
NFS_VOLUME_PATH='$NFS_VOLUME_PATH'
ENV

/usr/bin/caddy --config /etc/caddy/Caddyfile start

# The book: built at start and again whenever its sources change
sudo -u www nohup /usr/local/sbin/sciencedata_book.sh >/var/lib/book/meta/watch.log 2>&1 &

# SSH with keys only; passwords only if a root password was set explicitly
# (ROOT_PASSWORD, for standalone docker run). The pods' SSH ports get root
# password guessing from the internet.
DROPBEAR_AUTH="-s"; [ -n "$ROOT_PASSWORD" ] && DROPBEAR_AUTH=""
/usr/sbin/dropbear $DROPBEAR_AUTH -p 22 -W 65536 -F -E
