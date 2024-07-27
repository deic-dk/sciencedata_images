# Copyright ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata_custom:1.2 .
# Push command: docker push sciencedata/jupyter_sciencedata_custom:1.2
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata_custom

FROM sciencedata/jupyter_sciencedata:2.0

LABEL maintainer="ScienceData Project <support@sciencedata.dk>"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

############# ScienceData extensions ###############

WORKDIR $HOME

USER root

COPY install-software.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

USER $NB_UID

RUN /usr/local/bin/install-software.sh

USER root

RUN mkdir /usr/local/bin/start-notebook.d
COPY setup-software.sh /usr/local/bin/start-notebook.d/
RUN chmod +x /usr/local/bin/start-notebook.d/*
RUN rm -rf /home/$NB_USER/*

