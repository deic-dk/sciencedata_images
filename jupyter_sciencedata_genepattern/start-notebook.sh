#!/bin/bash

set -e
set -m

sudo ldconfig

export HOME_SERVER

# Guest pod (SCIENCEDATA_GUEST=1 from run_pod, anonymous "Run this notebook"): no home
# server, the files live in a local work directory and nothing is kept. FILE is then a
# URL (the notebook's public link), fetched into that directory at start.
if [[ -n "$SCIENCEDATA_GUEST" ]]; then
  unset HOME_SERVER
  guest_dir="$HOME/work"
  mkdir -p "$guest_dir"
  # this part of the script may run as root; the notebook user must own the directory
  chown -R "${NB_USER:-sciencedata}" "$guest_dir" 2>/dev/null || true
  if [[ "$FILE" =~ ^https?:// ]]; then
    # saved under the name the server sends (Content-Disposition, curl -J), else the
    # last path element; curl reports which (-w filename_effective)
    guest_name=$(cd "$guest_dir" && curl -L -J -O --silent --fail --max-time 300 -w '%{filename_effective}' "$FILE")
    if [[ -n "$guest_name" && -s "$guest_dir/$guest_name" ]]; then
      chown "${NB_USER:-sciencedata}" "$guest_dir/$guest_name" 2>/dev/null || true
      FILE="$guest_name"
    else
      echo "guest: could not fetch $FILE" >&2
      FILE=""
    fi
  fi
  ROOT_DIR="$guest_dir"
  PREFERRED_DIR="$guest_dir"
fi

wrapper=""
if [[ "${RESTARTABLE}" == "yes" ]]; then
  wrapper="run-one-constantly"
fi

root_dir='/home/sciencedata'
preferred_dir='/home/sciencedata'

sudo bash<<END
# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n "$HOME_SERVER" ]] && ( grep sciencedata /etc/hosts >& /dev/null || echo "$HOME_SERVER sciencedata" >> /etc/hosts )
[[ -n "$HOME_SERVER" ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER  sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
# the heredoc must end with status 0: with no home server (guest pods) the lines above are false, and the
# calling start script runs under set -e - a non-zero sudo bash here aborted it before Jupyter was launched
true
END

# A $FILE ending with a slash we use as notebook-dir.
if [[ -n "$FILE" && $FILE =~ .*/$ ]]; then
  root_dir="$FILE"
  preferred_dir="$FILE"
  export JUPYTER_SERVER_ROOT="$FILE"
  unset FILE
else
# We also allow setting ROOT_DIR and PREFERRED_DIR directly in the yaml.
  if [[ -n "$ROOT_DIR" ]]; then
    root_dir="$ROOT_DIR"
  fi
  if [[ -n "$PREFERRED_DIR" ]]; then
    preferred_dir="$PREFERRED_DIR"
  elif [[ -n "$ROOT_DIR" ]]; then
    # jupyter_server >= 2 refuses a preferred_dir outside root_dir ("/ is outside root contents directory")
    preferred_dir="$ROOT_DIR"
  fi
fi

cd

export PATH LD_LIBRARY_PATH

cd

eval "$(conda shell.bash hook)"
conda activate python3.8

(jupyter notebook --no-browser --notebook-dir="$root_dir" --debug >& /tmp/jupyter.log)&

for i in {1..20}; do
  sleep 5
  uri=`jupyter notebook list | grep -E ' *http://[^/]*/(.*token=.*) *' | sed -E 's| *http://[^/]*/(.*token=.*) *|\1|' | tail -1 | awk '{print $1}'`
if [[ -n "$uri" ]]; then
  if [[ -n "$FILE" ]]; then
    FILE=`echo $FILE | sed -E 's|^/+||'`
    uri=`echo $uri | sed "s|?token=|notebooks/$FILE?token=|"`
  fi
  echo "URI: $uri"
  echo "$uri" > /tmp/URI
  break
fi
done
fg

