#!/bin/bash

###############
# Bash kernel
###############

set -e

mamba install --yes bash_kernel
python -m bash_kernel.install
