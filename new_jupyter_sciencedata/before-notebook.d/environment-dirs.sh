#!/bin/bash

# Make it so the user cannot write to /opt/conda/envs so that new environments will be installed in ~/.conda/
mkdir -p /opt/conda/envs
chown root:root /opt/conda/envs

# If the NFS_ENVIRONMENTS option is set, then symlink the user storage to ~/.conda where environments will be installed
if [[ $NFS_ENVIRONMENTS ]]; then
	[[ -d /mnt/sciencedata/jupyter/.conda ]] || mkdir -p /mnt/sciencedata/jupyter/.conda
	rm -rf /home/sciencedata/.conda
	ln -s /mnt/sciencedata/jupyter/.conda /home/sciencedata/.conda
else
	chown -R sciencedata /home/sciencedata/.conda
fi
