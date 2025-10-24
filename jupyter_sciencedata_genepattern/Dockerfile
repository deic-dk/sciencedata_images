# Copyright ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata_genepattern .
# Push command: docker push sciencedata/jupyter_sciencedata_genepattern
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata_genepattern

FROM genepattern/genepattern-notebook

LABEL maintainer="ScienceData Project <support@sciencedata.dk>"
ENV NB_USER="sciencedata"
ENV NB_UID="1000"
ENV NB_GID="100"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"

ENV TERM="vt100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

############# ScienceData extensions ###############

WORKDIR $HOME

USER root

RUN apt update && apt install -y libigraph0-dev cython3 less file gcc

COPY custom.sh /opt/bin/custom.sh
RUN chmod +x /opt/bin/custom.sh

# change  jovyan to $NB_USER
RUN usermod -d /home/$NB_USER -l $NB_USER jovyan 
# Takes very long...
#RUN mkdir /home/$NB_USER
#RUN ls -a  /home/jovyan | grep '^\.' | grep -v '^\.$' | grep -v '^\.\.' | while read name; do echo moving $name; mv "/home/jovyan/$name" /home/$NB_USER/; done
# Link instead
RUN ln -s /home/jovyan /home/$NB_USER
RUN userdel $NB_USER && useradd --home /home/$NB_USER -u $NB_UID -g $NB_GID -G 100 -l $NB_USER
RUN groupadd -f -g $NB_GID -o ${NB_GROUP:-${NB_USER}} && chown -R $NB_UID:$NB_GID /home/$NB_USER
RUN echo "$NB_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/notebook
# Add $CONDA_DIR/bin to sudo secure_path
RUN sed -r "s#Defaults\s+secure_path\s*=\s*\"?([^\"]+)\"?#Defaults secure_path=\"\1:/opt/conda/bin\"#" /etc/sudoers | grep secure_path > /etc/sudoers.d/path

USER $NB_UID

COPY requirements.txt requirements.txt
COPY requirements.txt.orig requirements.txt.orig

RUN conda init bash

RUN /opt/bin/custom.sh

USER root

COPY start-notebook.sh /usr/local/sbin/start-notebook.sh

RUN rm -rf /home/$NB_USER/*

USER $NB_UID

CMD /usr/local/sbin/start-notebook.sh
#CMD sleep 36000
