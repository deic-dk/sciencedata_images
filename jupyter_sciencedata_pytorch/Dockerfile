# Build command: docker build -t sciencedata/jupyter_sciencedata_pytorch .
# Push command: docker push sciencedata/jupyter_sciencedata_pytorch
# Run command: docker run -p 8443:443 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/jupyter_sciencedata_pytorch
# Run command: docker run -p 8443:443 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/jupyter_sciencedata_pytorch
#

#FROM continuumio/miniconda3:23.3.1-0 as base
FROM nvidia/cuda:12.3.0-base-ubuntu22.04 as base
WORKDIR /app

ENV DEBIAN_FRONTEND="noninteractive"
ENV LANG C.UTF-8

LABEL maintainer="ScienceData Project <support@sciencedata.dk>"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"

ARG PYTHON_VERSION=3.10

# Configure environment
ENV SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    PYTHON_VERSION=$PYTHON_VERSION

#RUN echo "deb http://ftp.us.debian.org/debian bullseye-proposed-updates main contrib non-free #non-free-firmware" > /etc/apt/sources.list.d/bullseye.list

RUN apt update

RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
RUN echo "LANG=en_US.UTF-8" > /etc/locale.conf
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
RUN apt install -y locales && \
    locale-gen

#RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
#RUN dpkg -i cuda-keyring_1.1-1_all.deb
RUN apt update
RUN apt install -y \
gnupg \
ca-certificates \
wget \
curl \
build-essential \
pkg-config \
software-properties-common \
unzip \
bash \
git \
sudo \
vim \
net-tools \
ca-certificates \
ccache \
cmake \
curl \
libjpeg-dev \
libpng-dev

RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

RUN apt update

# Create $NB_USER with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo $NB_UID : $NB_USER
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    chmod g+w /etc/passwd

# Comment out for production image
RUN echo "$NB_USER:secret" | chpasswd
RUN echo "$NB_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$NB_USER && chmod 0440 /etc/sudoers.d/$NB_USER

RUN chown -R $NB_UID:$NB_GID /home/$NB_USER

###########################
# Conda
###########################

USER $NB_UID
WORKDIR /home/$NB_USER

#wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
RUN curl -LO https://repo.anaconda.com/miniconda/Miniconda3-py310_23.3.1-0-Linux-x86_64.sh
RUN bash Miniconda3-py310_23.3.1-0-Linux-x86_64.sh -b
RUN bash -c "source /home/sciencedata/miniconda3/bin/activate && conda init"

###########################
# CUDA
###########################

#RUN curl -LO https://developer.download.nvidia.com/compute/cuda/12.8.1/local_installers/cuda-repo-debian12-12-8-local_12.8.1-570.124.06-1_amd64.deb && dpkg -i cuda-repo-debian12-12-8-local_12.8.1-570.124.06-1_amd64.deb
#RUN cp /var/cuda-repo-debian12-12-8-local/cuda-*-keyring.gpg /usr/share/keyrings/
#RUN sudo apt update
#RUN apt install -y \
#cuda-drivers
#RUN apt install -y \
#cuda-toolkit \
#nvidia-utils-570

###########################
# PyTorch
# - from https://github.com/tivnanmatt/docker_conda_cuda_pytorch/blob/main/Dockerfile
###########################

# Install necessary system packages
USER root
RUN apt update && apt install -y wget git libgl1-mesa-glx && \
    rm -rf /var/lib/apt/lists/*
USER $NB_UID

# Install Python and other dependencies with Conda
RUN bash -c "source /home/sciencedata/miniconda3/bin/activate && conda install python=${PYTHON_VERSION} -y && \
conda install -c nvidia/label/cuda-12.1.1 cuda-toolkit -y  && \
conda config --add channels pytorch && \
conda install -c pytorch -c nvidia pytorch torchvision torchaudio pytorch-cuda=12.1 pytorch-lightning>=1.4 -y && \
conda install matplotlib -y && \
conda install scipy -y  && \
conda install ffmpeg -y"

###########################
# Jupyter
###########################

USER root

FROM base as jupyter

RUN apt update && apt install -y pip

RUN mkdir /usr/local/share/jupyter && chown -R $NB_UID:$NB_GID /usr/local/share/jupyter
RUN mkdir /home/$NB_USER/.local && chown $NB_UID /home/$NB_USER/.local
RUN mkdir /etc/jupyter/ && chown $NB_UID /etc/jupyter/

ENV PATH=$PATH:/home/$NB_USER/.local/bin
RUN echo "PATH=$PATH:/home/$NB_USER/.local/bin" >> /root/.bashrc

USER $NB_UID

ENV PATH=$PATH:/home/$NB_USER/.local/bin
RUN echo "PATH=$PATH:/home/$NB_USER/.local/bin" >> /home/$NB_USER/.bashrc

RUN pip install --no-cache-dir seaborn tensorboard

RUN pip install --no-cache-dir jupyter matplotlib jupyter_http_over_ws -U
RUN pip install --no-cache-dir --upgrade notebook==6.4.12
RUN pip install --no-cache-dir jupyter-tensorboard
RUN jupyter labextension enable jupyter_http_over_ws
RUN python3 -m ipykernel.kernelspec

# Keep notebooks in sciencedata homedir
RUN pip install pycurl webdavclient3
ADD https://api.github.com/repos/deic-dk/jupyter_sciencedata/git/refs/heads/main version.json

WORKDIR /home/$NB_USER
RUN git clone -b main https://github.com/deic-dk/jupyter_sciencedata.git && pip install jupyter_sciencedata/

# Spinning wheel on ajax calls
USER root
RUN cp jupyter_sciencedata/custom/* /usr/lib/python${PYTHON_VERSION}/site-packages/notebook/static/custom/ || echo "No notebook/static"
RUN cp jupyter_sciencedata/custom/* /usr/lib/python${PYTHON_VERSION}/site-packages/nbclassic/static/custom/ || echo "No nbclassic/static"

# Keep notebooks in sciencedata homedir ('/files')
RUN echo "from jupyter_sciencedata import JupyterScienceData" >> /etc/jupyter/jupyter_server_config.py &&\
echo "c.NotebookApp.contents_manager_class = 'jupyter_sciencedata.JupyterScienceData'" >> /etc/jupyter/jupyter_server_config.py &&\
echo "c.NotebookApp.allow_origin = '*'" >> /etc/jupyter/jupyter_server_config.py &&\
echo "c.NotebookApp.ip = '0.0.0.0'" >> /etc/jupyter/jupyter_server_config.py

USER $NB_UID

EXPOSE 8888

ENV PATH=$PATH:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/python${PYTHON_VERSION}/dist-packages/nvidia/cudnn:/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda-12.3/targets/x86_64-linux
ENV CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES

USER root

COPY start-notebook.sh /usr/local/sbin/start-notebook.sh

USER $NB_UID

CMD /usr/local/sbin/start-notebook.sh

