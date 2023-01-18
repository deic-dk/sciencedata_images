FROM dockerregistry.clement.tel/ubuntu_jammy_sciencedata

RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh && \
    bash Mambaforge-Linux-x86_64.sh -b -p /opt/conda && \
    rm Mambaforge-Linux-x86_64.sh && \
    /opt/conda/bin/conda init bash

# Below doesn't work. Try having mamba install a default environment from an environment file instead
#SHELL ["bash", "pip install numpy"]
