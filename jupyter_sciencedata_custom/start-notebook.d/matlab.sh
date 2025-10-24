#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.

export PYTHON=/opt/conda/bin/python
export SD_UID

export SETUP_MATLAB
export MATLAB_SOFTWARE_DIR=/usr/local/software/matlab
export MATLAB_SOFTWARE_DIR
export MATLAB_LICENSE_SERVER
export MATLAB_LICENSE_PORT

if [[ -n "$SETUP_MATLAB" && -d "$MATLAB_SOFTWARE_DIR" && -n "$MATLAB_LICENSE_SERVER" && -n "$MATLAB_LICENSE_PORT" ]]; then
  # First check if we're a DTU user
  user_domain=`echo $SD_UID | sed -E 's|^([^@]+)@([^@]+)$|\2|'`
  user_name=`echo $SD_UID | sed -E 's|^([^@]+)@([^@]+)$|\1|'`
  if [[ "$user_domain" != "dtu.dk" || "$user_name" == "$SD_UI" || "$user_name" == "" ]]; then
    echo "Only DTU users are allowed to use MATLAB"
    exit 0
  fi
  export LM_LICENSE_FILE="$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER"
  grep LM_LICENSE_FILE ~/.bashrc >& /dev/null || echo "export LM_LICENSE_FILE=$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER" >> ~/.bashrc
  sudo ln -s "$MATLAB_SOFTWARE_DIR/bin/matlab" /usr/local/bin/matlab
  pip install matlab_kernel
  sed -i -r "s|(import __version__)|\1\nos.environ['LM_LICENSE_FILE'] = \"$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER\"\n|" /opt/conda/lib/python*/site-packages/matlab_kernel/kernel.py
  #sudo /opt/conda/bin/python -m matlab_kernel install
  cd "$MATLAB_SOFTWARE_DIR/extern/engines/python"
  sudo "$PYTHON" setup.py install
  # Two kernels are installed: matlab and matlab_connect. Don't see why we need more than one way to do the same...
  jupyter kernelspec remove -y matlab_connect
fi

# For LCG software, SETUP_SCRIPT could be /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/setup.sh
if [[ -n "$SETUP_SCRIPT" && -f "$SETUP_SCRIPT" ]]; then
	. "$SETUP_SCRIPT"
fi

echo "MATLAB setup all done"
