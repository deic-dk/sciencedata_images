# Copyright (c) Jupyter Development Team.
# Modified/extended by the ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata .
# Push command: docker push sciencedata/jupyter_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata

FROM ubuntu:22.04

LABEL maintainer="ScienceData Project <support@sciencedata.dk>"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"
#ARG conda_version="4.9.2"
#ARG conda_version="24.3.0"
ARG conda_version=25.3.1-0

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt update \
 && apt install -yq --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    gnupg \
    sudo \
    locales \
    fonts-liberation \
    run-one \
 && apt clean && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER \
    CONDA_VERSION="${conda_version}"

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc 

# Create $NB_USER with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    . fix-permissions $HOME && \
    . fix-permissions $CONDA_DIR

# Comment out for production image
RUN echo "$NB_USER:secret" | chpasswd
RUN echo "$NB_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$NB_USER && chmod 0440 /etc/sudoers.d/$NB_USER

USER $NB_USER
ARG PYTHON_VERSION=default

# Install conda as $NB_USER and check the sha256 sum provided on the download site
WORKDIR /tmp

# Prerequisites installation: conda, pip, tini

RUN curl -LO https://github.com/conda-forge/miniforge/releases/download/${CONDA_VERSION}/Miniforge3-${CONDA_VERSION}-Linux-x86_64.sh && chmod +x *.sh

RUN ./*forge* -f -b -p $CONDA_DIR && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [ ! $PYTHON_VERSION = 'default' ]; then mamba install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    mamba install --quiet --yes \
    "conda=${CONDA_VERSION}" \
    'pip' \
    'tini' && \
    conda update --all --quiet --yes && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn

RUN echo "export PATH=$PATH:$CONDA_DIR/bin" >> /home/$NB_USER/.bashrc

# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
RUN mamba install --yes \
    'notebook' \
    'jupyter_server' \
    'nbclassic' \
    'jupyterlab' \
    'widgetsnbextension'\
    'jupyter_contrib_nbextensions' && \
    conda clean --all -f -y && \
    ( ( which npm && npm cache clean --force ) || echo "no pm" ) && \
    jupyter notebook --generate-config && \
    jupyter lab clean && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    . fix-permissions $CONDA_DIR && \
    . fix-permissions /home/$NB_USER

EXPOSE 80

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Fix permissions on /etc/jupyter as root
USER root
RUN mkdir /etc/jupyter/
COPY jupyter_notebook_config.py /etc/jupyter/

# Prepare upgrade to JupyterLab V3.0 #1205
RUN sed -re "s/c.NotebookApp/c.ServerApp/g" \
    /etc/jupyter/jupyter_notebook_config.py > /etc/jupyter/jupyter_server_config.py

RUN . fix-permissions /etc/jupyter/

# Install all OS dependencies for fully functional notebook server
RUN apt update && apt install -yq --no-install-recommends \
    build-essential \
    vim-tiny \
    vim \
    less \
    psmisc \
    telnet \
    git \
    openssh-client \
    file \
    zip \
    inkscape \
    libsm6 \
    libxext-dev \
    libxrender1 \
    libxt6 \
    iproute2 \
    lmodern \
    netcat \
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    tzdata \
    unzip \
    nano-tiny \
    nodejs \
    ffmpeg \
    dvipng \
    cm-super \
    fonts-dejavu \
    gfortran \
    gcc \
    imagemagick \
    && apt clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/apt/keyrings && \
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > \
/etc/apt/sources.list.d/nodesource.list

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab

# Switch back to $NB_USER to avoid accidental container runs as root
USER $NB_USER
WORKDIR $HOME

#########################
# Science/bio Python packages
#########################

# Install Python 3 packages
RUN mamba install --yes \
    'beautifulsoup4' \
    'conda-forge::blas=*=openblas' \
    'bokeh' \
    'bottleneck' \
    'cloudpickle*' \
    'cython' \
    'dask' \
    'dill' \
    'h5py' \
    'ipywidgets' \
    'ipympl'\
    'matplotlib-base' \
    'numba' \
    'numexpr' \
    'pandas' \
    'patsy' \
    'protobuf' \
    'pytables' \
    'scikit-image' \
    'scikit-learn' \
    'scipy' \
    'seaborn' \
    'sqlalchemy' \
    'statsmodels' \
    'sympy' \
    'vincent' \
    'xlrd' && \
    mamba clean --all -f -y

# Import matplotlib the first time to build the font cache.
ENV XDG_CACHE_HOME="/home/${NB_USER}/.cache/"
RUN python -c "import matplotlib.pyplot"

