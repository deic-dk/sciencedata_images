# Copyright (c) Jupyter Development Team.
# Modified/extended by the ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata

FROM jupyter/scipy-notebook:3d10155c955f@sha256:5bce431c1b63525dc8749747b09133b2a66a01df10b533ad70a106add7a65bb5

USER root
RUN apt-get update
RUN apt-get install -y \
    curl

ADD --chown=root:root ["before-notebook.d", "/usr/local/bin/before-notebook.d"]

RUN rm -rf /home/jovyan/work && \
    COPYLINE='[[ -n "${STORAGE_PATH}" ]] && ln -s /mnt/sciencedata/${STORAGE_PATH} /home/jovyan/sciencedata || ln -s /mnt/sciencedata /home/jovyan/sciencedata' && \
    echo -e "$(head /usr/local/bin/start-notebook.sh -n 3)\n${COPYLINE}\n$(tail /usr/local/bin/start-notebook.sh -n +3)" > /usr/local/bin/start-notebook.sh

USER ${NB_UID}
