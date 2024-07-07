#!/bin/bash

set -e
set -m

ldconfig

export HOME_SERVER

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

