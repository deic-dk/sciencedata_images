#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.

sudo bash<<END
export PATH=/opt/conda/bin:$PATH
if [[ ! -e /var/run/sciencedata_software ]]; then
  # Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
  [[ -n "$HOME_SERVER" ]] && ( grep sciencedata /etc/hosts >& /dev/null || echo "$HOME_SERVER sciencedata" >> /etc/hosts )
  [[ -n "$HOME_SERVER" ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER  sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
fi
END

# Make sure that in the container we're in the homedir (ROOT writes tmp files to cwd)
root_init=`ls -d /opt/conda/lib/python*/site-packages/JupyROOT/__init__.py | tail -1`
if [ -n "$root_init" ]; then
  sed -i -E "s|(import sys)|\1\nimport os|" "$root_init"
  echo 'os.chdir(os.path.expanduser("~"))' >> "$root_init"
fi

# E.g. for LCG software, SETUP_SCRIPT could be /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/setup.sh
if [[ -n "$SETUP_SCRIPT" && -f "$SETUP_SCRIPT" ]]; then
  . "$SETUP_SCRIPT"
fi