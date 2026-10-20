#!/bin/bash
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

set -e
set -m

export HOME_SERVER

# Guest pod (SCIENCEDATA_GUEST=1 from run_pod, anonymous "Run this notebook"): no home
# server, the files live in a local work directory and nothing is kept. FILE is then a
# URL (the notebook's public link), fetched into that directory at start.
if [[ -n "$SCIENCEDATA_GUEST" ]]; then
  unset HOME_SERVER
  guest_dir="$HOME/work"
  mkdir -p "$guest_dir"
  if [[ "$FILE" =~ ^https?:// ]]; then
    # the file name: a files= query parameter (Nextcloud download links), else the last path element
    if [[ "$FILE" == *files=* ]]; then
      guest_name="${FILE##*files=}"; guest_name="${guest_name%%&*}"
    else
      guest_name=$(basename "${FILE%%\?*}")
    fi
    guest_name=$(printf '%b' "${guest_name//%/\\x}")
    if curl -L --silent --fail --max-time 300 -o "$guest_dir/$guest_name" "$FILE"; then
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

root_dir='/'
preferred_dir='/'

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
  fi
fi

if [[ ! -z "${JUPYTERHUB_API_TOKEN}" ]]; then
  # launched by JupyterHub, use single-user entrypoint
  exec /usr/local/bin/start-singleuser.sh "$@"
elif [[ ! -z "${JUPYTER_ENABLE_LAB}" ]]; then
    (. /usr/local/bin/start.sh $wrapper jupyter lab --NotebookApp.show_banner=False --no-browser --notebook-dir="$root_dir" --preferred-dir="$preferred_dir" --debug "$@" >& /tmp/jupyter.log)&
    for i in {1..20}; do
      sleep 5
      uri=`jupyter lab list | grep -E ' *http://[^/]*/(.*token=.*) *' | sed -E 's| *http://[^/]*/(.*token=.*) *|\1|' | tail -1 | awk '{print $1}'`
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
else
  #echo "WARN: Jupyter Notebook deprecation notice https://github.com/jupyter/docker-stacks#jupyter-notebook-deprecation-notice."
  # jupyter notebook will now launch jupyter 7, which is a 'sunset' release of the original notebook interface
  # jupyter nbclassic will launch jupyter 7 with the nbclassic extension enabled - allowing compatibility with older extensions
  (. /usr/local/bin/start.sh $wrapper jupyter nbclassic --NotebookApp.show_banner=False --ServerApp.allow_remote_access='True' --no-browser --notebook-dir="$root_dir" --preferred-dir="$preferred_dir" --debug "$@" >& /tmp/jupyter.log)&
  for i in {1..20}; do
    sleep 5
    echo $i
    jupyter notebook list
    jupyter nbclassic list
    uri=`( jupyter notebook list; jupyter nbclassic list ) | grep -E ' *http://[^/]*/(.*token=.*) *' | \
      sed -E 's| *http://[^/]*/(.*token=.*) *|\1|' | tail -1 | awk '{print $1}'`
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
fi
