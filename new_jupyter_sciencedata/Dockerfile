# Copyright (c) Jupyter Development Team.
# Modified/extended by the ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata

FROM jupyter/datascience-notebook@sha256:48bd19591972e68bbc8a08149d8f5222b5830d7d3818a2169880aeb0bea52660

USER root
RUN apt-get update
# "unminimize" script provided by ubuntu:22.04 container restores expected shell features like installing
# man pages. The script itself is interactive, so this a modified version that runs without interaction
RUN sed -i 's/^read.*//g' /usr/local/sbin/unminimize && \
    sed -i 's/exit 1/echo "skip"/g' /usr/local/sbin/unminimize && \
    sed -i 's/apt-get upgrade/apt-get upgrade -y/g' /usr/local/sbin/unminimize && \
    /usr/local/sbin/unminimize


RUN apt-get install -y \
    curl \
    vim \
    man

# Install the custom content API to access the virtual filesystem via webdav on the data vlan
USER ${NB_UID}
RUN pip install webdavclient3 && \
    git clone https://github.com/joshuadclement/jupyter_sciencedata.git && \
    pip install jupyter_sciencedata/ && \
    rm -rf jupyter_sciencedata work

RUN conda install -y nb_conda_kernels

ADD --chown=root:root ["before-notebook.d", "/usr/local/bin/before-notebook.d"]

# Use bash shell in order for ANSI-C quoting in following RUN statement to work
SHELL ["/bin/bash", "-c"]
# Configure the jupyter notebook to use the custom content API,
# and to ignore conda envs in /opt/conda when automatically adding conda envs to the kernel (necessary to avoid duplicate entries)
RUN echo $'\n\
from jupyter_sciencedata import JupyterScienceData\n\
c.NotebookApp.contents_manager_class = \'jupyter_sciencedata.JupyterScienceData\'\n\
c.NotebookApp.notebook_dir = "/"\n\
c.CondaKernelSpecManager.env_filter = "/opt/conda.*"\n\
c.CondaKernelSpecManager.name_format = "{language} [{environment}]"\n\
' >> /etc/jupyter/jupyter_notebook_config.py
RUN echo $'\n\
c.ServerApp.root_dir = "/"\n\
' >> /etc/jupyter/jupyter_server_config.py

USER root

# Configure conda to install new envs to the user directory first. This way they won't be put in /opt/conda and be ignored
RUN echo $'\n\
envs_dirs:\n\
  - /home/sciencedata/.conda/envs\n\
  - /opt/conda/envs\n\
' >> /opt/conda/.condarc

ENV NB_USER="sciencedata" \
    GRANT_SUDO="yes"
