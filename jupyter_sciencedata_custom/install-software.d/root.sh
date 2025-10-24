#!/bin/bash

##############
# ROOT kernel
##############

set -e

sudo apt update
sudo apt install libglu1-mesa libopengl0
pip install metakernel
pip install zmq
mamba install -y root -c conda-forge
