#!/bin/bash

set -e
set -m

sudo ldconfig

export HOME_SERVER

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
  fi
fi

# Make a random $CUDA_VISIBLE_DEVICES_NUM (or 4 if unset) out of the available GPUs visible
if [ -z "$CUDA_VISIBLE_DEVICES" ]; then
  if [ -z "$CUDA_VISIBLE_DEVICES_NUM" ]; then
    CUDA_VISIBLE_DEVICES_NUM=4
  fi
  gpus=$(echo `nvidia-smi --list-gpus | shuf -n $CUDA_VISIBLE_DEVICES_NUM | awk '{print $2}' | sed "s|:|, |"` | sed 's|,$||')
  export CUDA_VISIBLE_DEVICES=$gpus
fi

cd

export PATH
export LD_LIBRARY_PATH

sudo mkdir /usr/etc 
sudo chown $NB_USER /usr/etc/

sudo -E bash -c '/home/sciencedata/.local/bin/jupyter labextension disable "@jupyterlab/apputils-extension:announcements"'

cd

(jupyter lab --no-browser --notebook-dir="$root_dir" --allow-root --preferred-dir="$preferred_dir" --debug >& /tmp/jupyter.log)&

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

