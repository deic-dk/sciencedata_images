#!/bin/bash

echo "Starting the main script"
# If the user specified an environment file, fetch it and create the environment, then activate it
if [[ $ENVIRONMENT_FILE ]]; then
	echo "getting the env file"
	curl https://$HOME_SERVER_HOSTNAME/files/$ENVIRONMENT_FILE -o /tmp/user_environment_file.yml
	echo "got it, creating env"
	/opt/conda/bin/mamba env create -f /tmp/user_environment_file.yml -n user-env 2>&1 > /tmp/user_environment_log.txt
	ENV_NAME="user-env"
else
	ENV_NAME="default"
fi

echo "get python script"
curl https://$HOME_SERVER_HOSTNAME/files/$PYTHON_SCRIPT -o /tmp/python_script.py

if [[ $STAY_ALIVE_AFTER ]]; then
	# Run the python script in the background
	echo "starting python script in background in environment $ENV_NAME"
	/opt/conda/bin/conda run -n "$ENV_NAME" python /tmp/python_script.py &
	# Listen for the interrupt signal from kubernetes, and then sleep until it comes
	trap - TERM INT
	sleep infinity
else
	# Otherwise, run the python script in the foreground, and finish when it exits
	echo "starting python script in foreground in environment $ENV_NAME"
  /opt/conda/bin/conda run -n "$ENV_NAME" python /tmp/python_script.py
fi
