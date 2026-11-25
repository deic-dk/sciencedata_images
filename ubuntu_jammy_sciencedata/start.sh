#!/bin/bash

# SSH access to root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

# Add non-root user if USERNAME is set in yaml
if [[ -n "$USERNAME" && "$USERNAME" != "root" ]]; then
	adduser --uid 80 --home /home/$USERNAME --disabled-password --gecos '' $USERNAME
	cp -a /root/.ssh /home/$USERNAME/
	chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
	echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME && chmod 0440 /etc/sudoers.d/$USERNAME
	[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && echo ". \"$SETUP_SCRIPT\"" >> /home/$USERNAME/.bashrc
	env | grep SD_UID >> /home/$USERNAME/.bashrc
	env | grep HOME_SERVER >> /home/$USERNAME/.bashrc
else
	[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && echo ". \"$SETUP_SCRIPT\"" >> /root/.bashrc
	env | grep SD_UID >> /root/.bashrc
	env | grep HOME_SERVER >> /root/.bashrc
fi

#/etc/init.d/php* start
service cron start
cd /root
export HOSTNAME
# SSH with keys only; passwords only if a root password was set explicitly
# (ROOT_PASSWORD, for standalone docker run). The pods' SSH ports get root
# password guessing from the internet.
DROPBEAR_AUTH="-s"; [ -n "$ROOT_PASSWORD" ] && DROPBEAR_AUTH=""
/usr/sbin/dropbear $DROPBEAR_AUTH -p 22 -W 65536 -F -E
