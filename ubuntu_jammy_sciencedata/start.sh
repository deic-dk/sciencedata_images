#!/bin/bash

# SSH access to root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
echo "$HOME_SERVER_IP    sciencedata" >> /etc/hosts
echo "$HOME_SERVER_IP    $HOME_SERVER_HOSTNAME" >> /etc/hosts

###### Begin generate new ssh_host keys
rm /etc/ssh/ssh_host*
ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
ssh-keygen -t rsa -N '' -f /etc/ssh/ssh_host_rsa_key
#get fingerprints
ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub | sed -E 's|.*(SHA256:.*) root.*|\1|' > /tmp/ed25519HostKeyHash
ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub | sed -E 's|.*(SHA256:.*) root.*|\1|' > /tmp/rsaHostKeyHash
###### End generate new ssh_host keys

cd /root
/usr/sbin/sshd -D
