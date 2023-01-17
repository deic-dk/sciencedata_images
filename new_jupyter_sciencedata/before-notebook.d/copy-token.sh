#!/bin/bash

for i in {1..60}; do
  sleep 1
  echo "Waiting for server to be running to copy token $i"
  uri=$(sudo -u sciencedata jupyter server list | grep -E ' *http://[^/]*/(.*token=.*) *' | \
    sed -E 's| *http://[^/]*/(.*token=[^ ]*).*|\1|' | tail -1 | awk '{print $1}')
  if [[ -n "$uri" ]]; then
    echo "URI: $uri"
    echo "$uri" > /tmp/appendURL

		# Now that the server is running, the pod should be in Ready state, and it can cURL from the silo
		# If the user specified an environment file, get it and create the environment
		echo "Now trying to curl the env file"
		if [[ $ENVIRONMENT_FILE ]]; then
			sudo -u sciencedata curl https://$HOME_SERVER_HOSTNAME/files/$ENVIRONMENT_FILE -o /tmp/user_environment_file.yml
			sudo -u sciencedata conda env create -f /tmp/user_environment_file.yml 2>&1 > /tmp/user_environment_log.txt
		fi

    break
  fi;
done &
