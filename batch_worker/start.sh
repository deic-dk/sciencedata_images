#!/bin/bash

###

runSSH(){
# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve unqualified sciencedata to the home server of the user running this pod
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER  sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts

# Route traffic to ScienceData over the internal network.
# Resolve all fully qualified silo names to local addresses - this in order to allow proper SSL handshake and client certificate auth
grep 10.2.0.13 /etc/hosts || echo "10.2.0.13 sciencedata.dk" >> /etc/hosts
grep 10.2.0.14 /etc/hosts || echo "10.2.0.14 silo1.sciencedata.dk" >> /etc/hosts
grep 10.2.0.15 /etc/hosts || echo "10.2.0.15 silo2.sciencedata.dk" >> /etc/hosts
grep 10.2.0.16 /etc/hosts || echo "10.2.0.16 silo3.sciencedata.dk" >> /etc/hosts
grep 10.2.0.17 /etc/hosts || echo "10.2.0.17 silo4.sciencedata.dk" >> /etc/hosts
grep 10.2.0.18 /etc/hosts || echo "10.2.0.18 silo5.sciencedata.dk" >> /etc/hosts
grep 10.2.0.19 /etc/hosts || echo "10.2.0.19 silo6.sciencedata.dk" >> /etc/hosts
grep 10.2.0.20 /etc/hosts || echo "10.2.0.20 silo7.sciencedata.dk" >> /etc/hosts
grep 10.2.0.21 /etc/hosts || echo "10.2.0.21 silo8.sciencedata.dk" >> /etc/hosts
grep 10.2.0.22 /etc/hosts || echo "10.2.0.22 silo9.sciencedata.dk" >> /etc/hosts

BATCH_IP=`host -4 batch | awk '{print $NF}'`
host -4 batch && [[ -n $BATCH_IP ]] && ( grep $BATCH_IP /etc/hosts || echo "$BATCH_IP batch.sciencedata.dk" >> /etc/hosts )

[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

service cron start

/usr/sbin/dropbear -p 22 -W 65536 -F -E
}

cd

env | grep SD_UID >> .bashrc
env | grep HOME_SERVER >> .bashrc
export SD_UID
export HOME_SERVER

# Parse $PEERS - which will be of the form hostname1:ip1,hostname2:ip2,...

GRIDFACTORY_SERVERS=""
GRIDFACTORY_SERVER_IPS=""
if [ -n $PEERS ]; then
  GRIDFACTORY_SERVERS=`echo $PEERS | sed -E 's| *, *| |g' | sed -E 's| *: *([0-9.]+)|:\1|g' | sed -E 's|:[^ ]*||g'`
  GRIDFACTORY_SERVER_IPS=`echo $PEERS | sed -E 's| *, *| |g' | sed -E 's| *: *([0-9.]+)|:\1|g' | sed -E 's|: |:- |g' | sed -E 's|[^ ]+:||g'`
fi

export GRIDFACTORY_SERVERS
export GRIDFACTORY_SERVER_IPS

env | grep GRIDFACTORY >> .bashrc

HOME_SERVER=$HOME_SERVER GRIDFACTORY_USER=root KEY_PASSWORD=grid GRIDFACTORY_SERVERS=$GRIDFACTORY_SERVERS  \
GRIDFACTORY_SERVER_IPS=$GRIDFACTORY_SERVER_IPS /usr/share/gridfactory/gridworker/configure_worker_node.sh -y

runSSH
