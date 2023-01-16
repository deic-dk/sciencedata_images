#!/bin/bash

if [[ $NFS_ENVIRONMENTS ]]; then
	[[ -d /mnt/sciencedata/jupyter/.conda ]] || mkdir -p /mnt/sciencedata/jupyter/.conda
	rm -rf /home/sciencedata/.conda
	ln -s /mnt/sciencedata/jupyter/.conda /home/sciencedata/.conda
fi
