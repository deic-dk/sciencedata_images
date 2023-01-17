#!/bin/bash

# Set the server hostname in /etc/hosts so that requests to the homeserver by hostname will go over the vlan
echo "$HOME_SERVER_IP    sciencedata" >> /etc/hosts
echo "$HOME_SERVER_IP    $HOME_SERVER_HOSTNAME" >> /etc/hosts
