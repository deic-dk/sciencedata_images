# Copyright ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: e.g docker build -t sciencedata/jupyter_sciencedata_custom:1.2 .
# Push command: e.g docker push sciencedata/jupyter_sciencedata_custom:1.2
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata_custom

FROM sciencedata/jupyter_sciencedata

LABEL maintainer="ScienceData Project <support@sciencedata.dk>"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

############# ScienceData extensions ###############

WORKDIR $HOME

USER root

COPY install-software.d/ /opt/install-software.d/
RUN chmod +x /opt/install-software.d/*.sh

USER $NB_UID

ENV JULIA_DEPOT_PATH=/opt/julia
ENV JULIA_PKGDIR=/opt/julia
ENV JULIA_VERSION="1.11.7"
ENV CONDA_DIR=/opt/conda

#RUN ls /opt/install-software.d/*.sh | while read name; do echo "Running installation script: $name"; . "$name"; done
RUN . /opt/install-software.d/julia.sh
RUN . /opt/install-software.d/bash.sh
RUN . /opt/install-software.d/root.sh
RUN . /opt/install-software.d/r.sh
RUN . /opt/install-software.d/custom.sh

USER root

COPY adobe-blank/ /opt/conda/lib/python*/site-packages/nbclassic/static/components/MathJax7/adobe-blank/

COPY start-notebook.d/ /usr/local/bin/start-notebook.d/
RUN chmod +x /usr/local/bin/start-notebook.d/*
RUN rm -rf /home/$NB_USER/*

