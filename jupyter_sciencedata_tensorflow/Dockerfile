# Build command: docker build -t sciencedata/jupyter_sciencedata_tensorflow .
# Push command: docker push sciencedata/jupyter_sciencedata_tensorflow
# Run command: docker run -p 8443:443 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/jupyter_sciencedata_tensorflow
# Run command: docker run -p 8443:443 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/jupyter_sciencedata_tensorflow


# Copyright 2019 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ============================================================================

# Build command: docker build -t sciencedata/jupyter_sciencedata_tensorflow .
# Push command: docker push sciencedata/jupyter_sciencedata_tensorflow
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata_tensorflow


FROM nvidia/cuda:12.3.0-base-ubuntu22.04 as base
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8

LABEL maintainer="ScienceData Project <support@sciencedata.dk>"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"

ARG PYTHON_VERSION=python3.10
#ARG PYTHON_VERSION=default

# Configure environment
ENV SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    PYTHON_VERSION=$PYTHON_VERSION

RUN apt update

RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
RUN echo "LANG=en_US.UTF-8" > /etc/locale.conf
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
RUN apt install -y locales && \
    locale-gen

RUN apt install -y gnupg ca-certificates wget curl
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
RUN dpkg -i cuda-keyring_1.1-1_all.deb
RUN apt update
# All required CUDA packages
#RUN apt install -y \
#cuda-command-line-tools-12-3 \
#cuda-cudart-dev-12-3 \
#cuda-nvcc-12-3 \
#cuda-cupti-12-3 \
#cuda-nvprune-12-3 \
#cuda-libraries-12-3 \
#cuda-nvrtc-12-3 \
#libcufft-12-3 \
#libcurand-12-3 \
#libcusolver-12-3 \
#libcusparse-12-3 \
#libcublas-12-3
# CuDNN: https://docs.nvidia.com/deeplearning/sdk/cudnn-install/index.html#ubuntu-network-installation
#RUN apt install -y \
#libcudnn8=8.9.6.50-1+cuda12.2 \
#libnvinfer-plugin8=8.6.1.6-1+cuda12.0 \
#libnvinfer8=8.6.1.6-1+cuda12.0
#RUN apt install -y nvidia-cuda-toolkit nvidia-utils-555
# Other packages
RUN apt install -y \
build-essential \
pkg-config \
software-properties-common \
unzip \
bash \
git \
sudo \
vim \
net-tools

RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

RUN apt update

RUN apt install -y $PYTHON_VERSION $PYTHON_VERSION-venv $PYTHON_VERSION-distutils $PYTHON_VERSION-dev
RUN ln -sf /usr/bin/$PYTHON_VERSION /usr/bin/python3
RUN ln -sf /usr/bin/$PYTHON_VERSION /usr/bin/python

RUN bash -c "if [[ ! -f /usr/local/include/$PYTHON_VERSION ]]; then ln -sf /usr/include/$PYTHON_VERSION /usr/local/include/$PYTHON_VERSION; fi"

RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
RUN python3 get-pip.py
RUN python3 -m pip install --no-cache-dir --upgrade pip

RUN bash -c "find /usr/local/cuda-*/lib*/ -type f -name 'lib*_static.a' -not -name 'libcudart_static.a' -delete"
RUN bash -c "rm -f /usr/lib/x86_64-linux-gnu/libcudnn_static_v*.a"

# Link the libcuda stub to the location where tensorflow is searching for it and
# reconfigure dynamic linker run-time bindings
#RUN bash -c "ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1"
#RUN bash -c "echo /usr/local/cuda/lib64/stubs > /etc/ld.so.conf.d/z-cuda-stubs.conf"
#RUN ldconfig

#RUN pip install --no-cache-dir tf-nightly
#RUN pip install --no-cache-dir tensorrt tensorflow[and-cuda]
RUN pip install --no-cache-dir tensorrt tensorflow[and-cuda]
#RUN pip install --no-cache-dir --upgrade tensorflow[and-cuda]==2.15.0.post1
RUN pip install --no-cache-dir tensorrt tensorflow[and-cuda]==2.15.0.post1
#RUN apt install tensorrt nvidia-tensorrt-dev python3-libnvinfer-dev

FROM base as jupyter

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
RUN mkdir /usr/local/share/jupyter && chown -R $NB_UID:$NB_GID /usr/local/share/jupyter
RUN mkdir /home/$NB_USER/.local && chown $NB_UID /home/$NB_USER/.local
RUN mkdir /etc/jupyter/ && chown $NB_UID /etc/jupyter/

USER $NB_UID

ENV PATH=$PATH:/home/$NB_USER/.local/bin
RUN echo "PATH=$PATH:/home/$NB_USER/.local/bin" >> /home/$NB_USER/.bashrc

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
RUN cp jupyter_sciencedata/custom/* /usr/lib/$PYTHON_VERSION/site-packages/notebook/static/custom/ || echo "No notebook/static"
RUN cp jupyter_sciencedata/custom/* /usr/lib/$PYTHON_VERSION/site-packages/nbclassic/static/custom/ || echo "No nbclassic/static"

# Keep notebooks in sciencedata homedir ('/files')
RUN echo "from jupyter_sciencedata import JupyterScienceData" >> /etc/jupyter/jupyter_server_config.py &&\
echo "c.NotebookApp.contents_manager_class = 'jupyter_sciencedata.JupyterScienceData'" >> /etc/jupyter/jupyter_server_config.py &&\
echo "c.NotebookApp.allow_origin = '*'" >> /etc/jupyter/jupyter_server_config.py &&\
echo "c.NotebookApp.ip = '0.0.0.0'" >> /etc/jupyter/jupyter_server_config.py

EXPOSE 8888

ENV PATH=$PATH:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/python3.10/dist-packages/nvidia/cudnn:/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda-12.3/targets/x86_64-linux
ENV CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES
ENV CUDA_VISIBLE_DEVICES_NUM=$CUDA_VISIBLE_DEVICES_NUM

COPY start-notebook.sh /usr/local/sbin/start-notebook.sh
CMD /usr/local/sbin/start-notebook.sh

