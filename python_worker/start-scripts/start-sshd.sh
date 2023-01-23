#!/bin/bash

# If the user provided their ssh public key, then start the sshd service in the background so they can check on things
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	echo "cd"
	cd /root
	echo "starting sshd as a daemon"
	/usr/sbin/sshd
fi
