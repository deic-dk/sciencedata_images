#!/bin/bash

############################
# ScienceData customization
############################

set -e

# Keep notebooks in user's sciencedata homedir ('/files')
pip install pycurl webdavclient3
jupyter_server_version=`jupyter --version | grep jupyter_server | awk '{print $NF}'`
if [[ "$jupyter_server_version" > "2.10.9" ]]; then
  # For jupyter_server>=2.11, grab latest jupyter_sciencedata version
  git clone https://github.com/deic-dk/jupyter_sciencedata.git
else
  # For jupyter_server<2.11, grab version 1.0 of jupyter_sciencedata
  git clone --branch 1.0 https://github.com/deic-dk/jupyter_sciencedata.git
fi
pip install jupyter_sciencedata/

echo "from jupyter_sciencedata import JupyterScienceData" >> /etc/jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.contents_manager_class = 'jupyter_sciencedata.JupyterScienceData'" >> /etc/jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.allow_origin = '*'" >> /etc/jupyter/jupyter_server_config.py

# Spinning wheel on ajax calls
python_dir=`ls -d /opt/conda/lib/python* | tail -1`
cp jupyter_sciencedata/custom/* $python_dir/site-packages/notebook/static/custom/ || echo "No notebook/static"
cp jupyter_sciencedata/custom/* $python_dir/site-packages/nbclassic/static/custom/ || echo "No nbclassic/static"
ls -d $python_dir/site-packages/jupyterlab/themes/\@jupyterlab/theme-* | while read theme; do
  cat jupyter_sciencedata/custom/custom.css >> $theme/index.css
  cat jupyter_sciencedata/custom/custom.js >> $theme/index.js
done
ls -d /opt/conda/share/jupyter/lab/themes/\@jupyterlab/theme-* | while read theme; do
  cat jupyter_sciencedata/custom/custom.css >> $theme/index.css
  cat jupyter_sciencedata/custom/custom.js >> $theme/index.js
done

# Patch python's urllib to not match hostname with certificate
python_dir=`ls -d /opt/conda/lib/python* | tail -1`
cp jupyter_sciencedata/custom/* $python_dir/site-packages/notebook/static/custom/ || echo "No notebook/static"
cp jupyter_sciencedata/custom/* $python_dir/site-packages/nbclassic/static/custom/ || echo "No nbclassic/static"
ls -d $python_dir/site-packages/jupyterlab/themes/\@jupyterlab/theme-* | while read theme; do
  cat jupyter_sciencedata/custom/custom.css >> $theme/index.css
  cat jupyter_sciencedata/custom/custom.js >> $theme/index.js
done
ls -d /opt/conda/share/jupyter/lab/themes/\@jupyterlab/theme-* | while read theme; do
  cat jupyter_sciencedata/custom/custom.css >> $theme/index.css
  cat jupyter_sciencedata/custom/custom.js >> $theme/index.js
done

# sddk apparently needs kaleido
pip install kaleido sddk
# For now, manually override with updated version
curl -L -o $python_dir/site-packages/sddk/__init__.py https://raw.githubusercontent.com/deic-dk/sddk_py/master/sddk/__init__.py

# Patch python's urllib to not match hostname with certificate
sed -i -r 's|(and assert_hostname is not False)|\1 and server_hostname != "sciencedata"|' $python_dir/site-packages/urllib3/connection.py 
sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' $python_dir/site-packages/urllib3/connection.pynection.py || echo "No pynection"
sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' $python_dir/site-packages/urllib3/connection.py

###############################
# Scientific software packages
##############################

# ensteinpy
pip install einsteinpy

# astropy
pip install astropy astroquery notebook git+https://github.com/radio-astro-tools/spectral-cube radio-beam reproject dust_extinction gala dust_extinction synphot

# Python packages for riemann_book
pip install clawpack

###################################
# Jupyter fixes and customizations
###################################

# TOC extension
echo "export PATH=$PATH:~/.local/bin" >> ~/.bashrc
pip install webcolors uri-template jsonpointer isoduration fqdn
mamba install --quiet --yes jupyter_contrib_nbextensions

jupyter contrib nbextension install --sys-prefix
jupyter nbextension enable toc2/main
jupyter nbextension enable autosavetime/main
jupyter nbextension enable equation-numbering/main

# Fix warnings and errors in recent builds
#pip install --upgrade ipywidgets jupyterlab_widgets
mamba install --yes ipywidgets widgetsnbextension jupyterlab_widgets

# Turn off autosaving
sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' /opt/conda/share/jupyter/nbextensions/autosavetime/main.js
sed -i 's|autosavetime_set_starting_interval : false,|autosavetime_set_starting_interval : true,|' /opt/conda/share/jupyter/nbextensions/autosavetime/main.js

sed -i 's|default: 2|default: 0|' /opt/conda/share/jupyter/nbextensions/autosavetime/autosavetime.yaml

# Fix cors error
sed -i 's|about:blank|/static/nbclassic/components/MathJax/adobe-blank/adobe-blank.css|' /opt/conda/lib/python*/site-packages/nbclassic/static/components/MathJax/jax/output/HTML-CSS/jax.js /opt/conda/lib/python3.12/site-packages/nbclassic/static/components/MathJax/config/TeX-AMS-MML_HTMLorMML-full.js

sed -i 's|MathJax_Blank|AdobeBlankRegular|' /opt/conda/lib/python*/site-packages/nbclassic/static/components/MathJax/jax/output/HTML-CSS/jax.js /opt/conda/lib/python3.12/site-packages/nbclassic/static/components/MathJax/config/TeX-AMS-MML_HTMLorMML-full.js

# Get rid of ipyparallel
jupyter labextension disable ipyparallel-labextension
jupyter nbextension disable ipyparallel-nbextension
jupyter nbextension disable ipyparallel
rm -rf /opt/conda/lib/python3.10/site-packages/ipyparallel

# Fix https://github.com/ipython-contrib/jupyter_contrib_nbextensions/issues/1529
grep -r template_path $python_dir/site-packages/jupyter_contrib_nbextensions | grep '.py:' | while read line; do name=`echo $line | awk -F: '{print $1}'`; grep template_paths "$name" || sed -i 's|template_path|template_paths|g' "$name"; done
grep -r template_path $python_dir/site-packages/latex_envs | grep '.py:' | while read line; do name=`echo $line | awk -F: '{print $1}'`; grep template_paths "$name" || sed -i 's|template_path|template_paths|g' "$name"; done

# Fix what appears to be a Jupyter bug - preventing JupyterLab from starting
sed -i -r 's|(self\.contents_manager\.preferred_dir)|#\1|' $python_dir/site-packages/jupyter_server/serverapp.py

# Fix what appears to be a Jupyter bug
if [[ -e /opt/conda/lib/python*/site-packages/nbclassic/nbserver.py && -n "$JUPYTER_ENABLE_LAB" ]]; then
  sed -i -r "s|^(manager\.link_extension\(name)(, serverapp\))|\1)\n                #\1\2|" /opt/conda/lib/python*/site-packages/nbclassic/nbserver.py || echo no nbserver.py
fi

# fix toc2 bugs
sed -i 's|typeof _ !== undefined|typeof _ !== "undefined"|' /opt/conda/share/jupyter/nbextensions/toc2/toc2.js
sed -i 's|top: 0|/*top: 0*/|' /opt/conda/share/jupyter/nbextensions/toc2/main.css
sed -i 's|bottom: 0|/*bottom: 0*/|' /opt/conda/share/jupyter/nbextensions/toc2/main.css
echo "#Navigate_menu.dropdown-menu {min-height: 84px;}" >> /opt/conda/share/jupyter/nbextensions/toc2/main.css

# Enable nbextensions tab in nbclassic
#rm -rf ~/.local/share/jupyter/nbextensions/*
#cd $python_dir/site-packages/jupyter_nbextensions_configurator
#cp -r static/nbextensions_configurator /opt/conda/share/jupyter/nbextensions/
#cp -r application.py templates /opt/conda/share/jupyter/nbextensions/nbextensions_configurator/

#sed -i -r "s|(\{\{super\(\)\}\})|\1\n<script src=\"/static/notebook/js/main.min.js\" type=\"text/javascript\" charset=\"utf-8\"></script>|" $python_dir/site-packages/jupyter_nbextensions_configurator/templates/nbextensions_configurator.html

#cp /opt/conda/etc/jupyter/jupyter_notebook_config.d/jupyter_nbextensions_configurator.json /opt/conda/etc/jupyter/jupyter_server_config.d/jupyter_nbextensions_configurator.json
#sed -i 's|NotebookApp|ServerApp|' /opt/conda/etc/jupyter/jupyter_server_config.d/jupyter_nbextensions_configurator.json
#jupyter nbextensions_configurator enable

# Fix Jupyter bug
# https://github.com/Jupyter-contrib/jupyter_nbextensions_configurator/issues/127#issuecomment-1301506342
jupyter nbextension install --prefix /opt/conda --py jupyter_nbextensions_configurator --overwrite
jupyter nbextension enable --py jupyter_nbextensions_configurator
#jupyter serverextension enable jupyter_nbextensions_configurator

# Install facets - which does not have a pip or conda package at the moment
#jupyter nbextension enable varInspector/main
#jupyter labextension enable varInspector/main
git clone https://github.com/PAIR-code/facets.git
jupyter nbextension install --prefix /opt/conda facets/facets-dist/
rm -rf facets

# Get rid of upgrade announcements
jupyter labextension disable "@jupyterlab/apputils-extension:announcements"

