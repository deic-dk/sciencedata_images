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

RUN apt update
RUN apt install -y gnupg ca-certificates wget curl
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
RUN dpkg -i cuda-keyring_1.1-1_all.deb
RUN apt update
# All required CUDA packages
RUN apt install -y \
cuda-command-line-tools-12-3 \
cuda-cudart-dev-12-3 \
cuda-nvcc-12-3 \
cuda-cupti-12-3 \
cuda-nvprune-12-3 \
cuda-libraries-12-3 \
cuda-nvrtc-12-3 \
libcufft-12-3 \
libcurand-12-3 \
libcusolver-12-3 \
libcusparse-12-3 \
libcublas-12-3
# CuDNN: https://docs.nvidia.com/deeplearning/sdk/cudnn-install/index.html#ubuntu-network-installation
RUN apt install -y \
libcudnn8=8.9.6.50-1+cuda12.2 \
libnvinfer-plugin8=8.6.1.6-1+cuda12.0 \
libnvinfer8=8.6.1.6-1+cuda12.0
# Other packages
RUN apt install -y \
build-essential \
pkg-config \
software-properties-common \
unzip \
bash \
git

RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

ARG PYTHON_VERSION=python3.11

RUN apt install -y $PYTHON_VERSION $PYTHON_VERSION-venc $PYTHON_VERSION-distutils $PYTHON_VERSION-dev
RUN ln -sf /usr/bin/$PYTHON_VERSION /usr/bin/python3
RUN ln -sf /usr/bin/$VERSION /usr/bin/python

RUN bash -c "if [[ ! -f /usr/local/include/$PYTHON_VERSION ]]; then ln -sf /usr/include/$PYTHON_VERSION /usr/local/include/$PYTHON_VERSION; fi"

RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
RUN python3 get-pip.py
RUN python3 -m pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir tf-nightly

RUN bash -c "find /usr/local/cuda-*/lib*/ -type f -name 'lib*_static.a' -not -name 'libcudart_static.a' -delete"
RUN bash -c "rm -f /usr/lib/x86_64-linux-gnu/libcudnn_static_v*.a"

# Link the libcuda stub to the location where tensorflow is searching for it and
# reconfigure dynamic linker run-time bindings
RUN bash -c "ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1"
RUN bash -c "echo /usr/local/cuda/lib64/stubs > /etc/ld.so.conf.d/z-cuda-stubs.conf"
RUN ldconfig

FROM base as jupyter

RUN python3 -m pip install --no-cache-dir jupyter matplotlib jupyter_http_over_ws -U
RUN jupyter serverextension enable --py jupyter_http_over_ws
RUN mkdir /.local
RUN chmod a+rwx /.local
RUN python3 -m ipykernel.kernelspec

# Keep notebooks in sciencedata homedir
WORKDIR $HOME
RUN pip install pycurl webdavclient3
ADD https://api.github.com/repos/deic-dk/jupyter_sciencedata/git/refs/heads/main version.json
RUN git clone -b main https://github.com/deic-dk/jupyter_sciencedata.git
RUN pip install jupyter_sciencedata/

# Spinning wheel on ajax calls
RUN cp jupyter_sciencedata/custom/* /opt/conda/lib/python3.8/site-packages/notebook/static/custom/ || echo "No notebook/static"
RUN cp jupyter_sciencedata/custom/* /opt/conda/lib/python3.8/site-packages/nbclassic/static/custom/ || echo "No nbclassic/static"

# Keep notebooks in sciencedata homedir ('/files')
RUN echo "from jupyter_sciencedata import JupyterScienceData" >> /etc/jupyter/jupyter_notebook_config.py &&\
echo "c.NotebookApp.contents_manager_class = 'jupyter_sciencedata.JupyterScienceData'" >> /etc/jupyter/jupyter_notebook_config.py

EXPOSE 80

ENV PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64

COPY start-notebook.sh /usr/local/sbin/start-notebook.sh
CMD /usr/local/sbin/start-notebook.sh

