# Copyright (c) Jupyter Development Team.
# Modified/extended by the ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata

FROM jupyter/scipy-notebook:3d10155c955f@sha256:5bce431c1b63525dc8749747b09133b2a66a01df10b533ad70a106add7a65bb5

USER root
RUN apt-get update
# "unminimize" script provided by ubuntu:22.04 container restores expected shell features like installing
# man pages. The script itself is interactive, so this a modified version that runs without interaction
RUN sed -i 's/^read.*//g' /usr/local/sbin/unminimize && \
    sed -i 's/exit 1/echo "skip"/g' /usr/local/sbin/unminimize && \
    sed -i 's/apt-get upgrade/apt-get upgrade -y/g' /usr/local/sbin/unminimize && \
    /usr/local/sbin/unminimize


RUN apt-get install -y \
    curl

ADD --chown=root:root ["before-notebook.d", "/usr/local/bin/before-notebook.d"]

# Install the custom content API to access the virtual filesystem via webdav on the data vlan
USER ${NB_UID}
RUN pip install webdavclient3 && \
    wget https://api.github.com/repos/joshuadclement/jupyter_sciencedata/git/refs/heads/main -o version.json && \
    git clone https://github.com/joshuadclement/jupyter_sciencedata.git && \
    pip install jupyter_sciencedata/

# Use bash shell in order for ANSI-C quoting in following RUN statement to work
SHELL ["/bin/bash", "-c"]
# Configure the jupyter notebook to use the custom content API
RUN echo $'\n\
from jupyter_sciencedata import JupyterScienceData\n\
c.NotebookApp.contents_manager_class = \'jupyter_sciencedata.JupyterScienceData\'\n\
' >> /etc/jupyter/jupyter_notebook_config.py


USER root

ENV NB_USER="sciencedata" \
    GRANT_SUDO="yes"
