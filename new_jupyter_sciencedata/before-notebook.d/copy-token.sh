#!/bin/bash

for i in {1..60}; do
  sleep 1
  echo $i
  jupyter server list
  uri=$(sudo -u sciencedata jupyter server list | grep -E ' *http://[^/]*/(.*token=.*) *' | \
    sed -E 's| *http://[^/]*/(.*token=[^ ]*).*|\1|' | tail -1 | awk '{print $1}')
  if [[ -n "$uri" ]]; then
    if [[ -n "$FILE" ]]; then
      FILE=`echo $FILE | sed -E 's|^/+||'`
      uri=`echo $uri | sed "s|?token=|notebooks/$FILE?token=|"`
    fi
    echo "URI: $uri"
    echo "$uri" > /tmp/appendURL
    break
  fi;
done &
