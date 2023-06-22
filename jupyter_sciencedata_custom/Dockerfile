# Copyright ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata_custom .
# Push command: docker push sciencedata/jupyter_sciencedata_custom
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata_custom

FROM sciencedata/jupyter_sciencedata

LABEL maintainer="ScienceData Project <cloud@deic.dk>"
ARG NB_USER="sciencedata"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

############# ScienceData extensions ###############

WORKDIR $HOME
USER root
RUN mkdir /usr/local/bin/start-notebook.d
COPY setup-software.sh /usr/local/bin/start-notebook.d/
RUN chmod +x /usr/local/bin/start-notebook.d/*

USER $NB_UID

# Keep notebooks in sciencedata homedir
RUN pip install webdavclient3
#RUN git clone https://github.com/deic-dk/jupyter_sciencedata.git
ADD https://api.github.com/repos/deic-dk/jupyter_sciencedata/git/refs/heads/main version.json
RUN sudo chown "${NB_USER}":users version.json
RUN git clone -b main https://github.com/deic-dk/jupyter_sciencedata.git
RUN pip install jupyter_sciencedata/

# TOC extension
RUN echo "export PATH=$PATH:~/.local/bin" >> ~/.bashrc
RUN conda install --quiet --yes jupyter_contrib_nbextensions

RUN jupyter contrib nbextension install --user
RUN jupyter nbextension enable toc2/main
RUN jupyter nbextension enable autosavetime/main
RUN jupyter nbextension enable equation-numbering/main

# Patch to default to 0/off - and yeah - what a bonty of duplicated code... It seems the last one is the one actually loaded.
RUN sed -i 's|default: 2|default: 0|' '/opt/conda/share/jupyter/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
RUN sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/opt/conda/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"
RUN sed -i 's|2 (\(default\))|2|' '/opt/conda/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"

RUN sed -i 's|default: 2|default: 0|' '/opt/conda/lib/python3.8/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
RUN sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/opt/conda/lib/python3.8/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js' || echo "not found"
RUN sed -i 's|2 (\(default\))|2|' '/opt/conda/lib/python3.8/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js' || echo "not found"

RUN sed -i 's|default: 2|default: 0|' '/opt/conda/pkgs/jupyter_contrib_nbextensions-0.5.1-pyhd8ed1ab_2/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
RUN sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/opt/conda/pkgs/ || echo "not found"jupyter_contrib_nbextensions-0.5.1-pyhd8ed1ab_2/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js' || echo "not found"
RUN sed -i 's|2 (\(default\))|2|' '/opt/conda/pkgs/jupyter_contrib_nbextensions-0.5.1-pyhd8ed1ab_2/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js' || echo "not found"

RUN sed -i 's|default: 2|default: 0|' '/home/sciencedata/.local/share/jupyter/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
RUN sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/home/sciencedata/.local/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"
RUN sed -i 's|2 (\(default\))|2|' '/home/sciencedata/.local/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"

# Bash kernel
RUN conda install --quiet --yes bash_kernel
RUN python -m bash_kernel.install

# For the ensteinpy examples
RUN pip install einsteinpy

# For the astropy examples
RUN pip install astropy astroquery notebook git+https://github.com/radio-astro-tools/spectral-cube radio-beam reproject dust_extinction gala dust_extinction synphot

# For riemann_book
RUN pip install clawpack

# Spinning wheel on ajax calls
RUN cp jupyter_sciencedata/custom/* /opt/conda/lib/python3.8/site-packages/notebook/static/custom/

RUN pip install sddk
# For now, manually override with updated version
RUN curl -L -o /opt/conda/lib/python3.8/site-packages/sddk/__init__.py https://raw.githubusercontent.com/deic-dk/sddk_py/master/sddk/__init__.py

# Patch python's urllib to not match hostname with certificate
RUN sed -i -r 's|(and assert_hostname is not False)|\1 and server_hostname != "sciencedata"|' /opt/conda/lib/python3.8/site-packages/urllib3/connection.py 
RUN sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' /opt/conda/lib/python3.8/site-packages/urllib3/connection.py

# Fix https://github.com/ipython-contrib/jupyter_contrib_nbextensions/issues/1529
RUN grep -r template_path /opt/conda/lib/python3.8/site-packages/jupyter_contrib_nbextensions | grep '.py:' | while read line; do name=`echo $line | awk -F: '{print $1}'`; grep template_paths "$name" || sed -i 's|template_path|template_paths|g' "$name"; done
RUN grep -r template_path /opt/conda/lib/python3.8/site-packages/latex_envs | grep '.py:' | while read line; do name=`echo $line | awk -F: '{print $1}'`; grep template_paths "$name" || sed -i 's|template_path|template_paths|g' "$name"; done

