#!/bin/bash
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

set -e
set -m

export HOME_SERVER

wrapper=""
if [[ "${RESTARTABLE}" == "yes" ]]; then
  wrapper="run-one-constantly"
fi

if [[ ! -z "${JUPYTERHUB_API_TOKEN}" ]]; then
  # launched by JupyterHub, use single-user entrypoint
  exec /usr/local/bin/start-singleuser.sh "$@"
elif [[ ! -z "${JUPYTER_ENABLE_LAB}" ]]; then
    (. /usr/local/bin/start.sh $wrapper jupyter lab "$@")&
    sleep 5
    jupyter lab list | grep -E ' *http://[^/]*/(.*token=.*) *' | sed -E 's| *http://[^/]*/(.*token=.*) *|\1|' | tail -1 | awk '{print $1}' > /tmp/URI
    fg
else
  #echo "WARN: Jupyter Notebook deprecation notice https://github.com/jupyter/docker-stacks#jupyter-notebook-deprecation-notice."
  (. /usr/local/bin/start.sh $wrapper jupyter notebook "$@")&
  for i in {1..20}; do
    sleep 5
    echo $i
    jupyter notebook list
    uri=`jupyter notebook list | grep -E ' *http://[^/]*/(.*token=.*) *' | \
      sed -E 's| *http://[^/]*/(.*token=.*) *|\1|' | tail -1 | awk '{print $1}'`
    if [[ -n "$uri" ]]; then
      echo "URI: $uri"
      echo "$uri" > /tmp/URI
      break
    fi;
  done
  fg
fi
