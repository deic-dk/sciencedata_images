FROM dockerregistry.clement.tel/ubuntu_jammy_sciencedata

RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh && \
    bash Mambaforge-Linux-x86_64.sh -b -p /opt/conda && \
    rm Mambaforge-Linux-x86_64.sh && \
    /opt/conda/bin/conda init bash

# Below doesn't work. Try having mamba install a default environment from an environment file instead
#SHELL ["bash", "pip install numpy"]
ADD ["default.yml", "/tmp/default.yml"]
SHELL ["bash", "-c"]
RUN /opt/conda/bin/mamba env create -f /tmp/default.yml

ADD start-scripts /usr/local/sbin/start-scripts
ADD main-script.sh /usr/local/sbin/main-script.sh

#ADD start.sh /usr/local/sbin/start.sh
#RUN chmod +x /usr/local/sbin/start.sh
#
#CMD []
#ENTRYPOINT ["bash", "/usr/local/sbin/start.sh"]
