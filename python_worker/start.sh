#!/bin/bash

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
echo "$HOME_SERVER_IP    sciencedata" >> /etc/hosts
echo "$HOME_SERVER_IP    $HOME_SERVER_HOSTNAME" >> /etc/hosts

# SSH access to root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
  ###### Begin generate new ssh_host keys
  rm /etc/ssh/ssh_host*
  ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
  ssh-keygen -t rsa -N '' -f /etc/ssh/ssh_host_rsa_key
  #get fingerprints
  ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub | sed -E 's|.*(SHA256:.*) root.*|\1|' > /tmp/ed25519HostKeyHash
  ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub | sed -E 's|.*(SHA256:.*) root.*|\1|' > /tmp/rsaHostKeyHash
  ###### End generate new ssh_host keys
fi

# Before running the main script, run all the start-scripts that may be present in docker images based on this one.
for f in /usr/local/sbin/start-scripts/*; do
	bash "${f}"
done

# If there is a main script, run that
if [[ -f /usr/local/sbin/main-script.sh ]]; then
	bash /usr/local/sbin/main-script.sh
# Otherwise, start the sshd server and let it run indefinitely
else
  cd /root
  /usr/sbin/sshd -D
fi
