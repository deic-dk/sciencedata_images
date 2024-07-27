# Keep notebooks in sciencedata homedir
pip install pycurl webdavclient3
jupyter_server_version=`jupyter --version | grep jupyter_server | awk '{print $NF}'`
jv=`printf "$jupyter_server_version\n2.11\n" | sort -V | head -1`
if [[ "$jv" == "2.11" ]]; then
  # For jupyter_server>=2.11, grab latest jupyter_sciencedata
  git clone --depth 1 https://github.com/deic-dk/jupyter_sciencedata.git
else
  # For jupyter_server<2.11, grab version 1.0 of jupyter_sciencedata
  git clone --depth 1 --branch 1.0 https://github.com/deic-dk/jupyter_sciencedata.git
fi
pip install jupyter_sciencedata/

# TOC extension
echo "export PATH=$PATH:~/.local/bin" >> ~/.bashrc
pip install webcolors uri-template jsonpointer isoduration fqdn
mamba install --quiet --yes jupyter_contrib_nbextensions

jupyter contrib nbextension install --user
jupyter nbextension enable toc2/main
jupyter nbextension enable autosavetime/main
jupyter nbextension enable equation-numbering/main

# Patch to default to 0/off - and yeah - what a bonty of duplicated code... It seems the last one is the one actually loaded.
sed -i 's|default: 2|default: 0|' '/opt/conda/share/jupyter/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/opt/conda/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"
sed -i 's|2 (\(default\))|2|' '/opt/conda/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"

sed -i 's|default: 2|default: 0|' $python_dir/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/autosavetime.yaml || echo "not found"
sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' $python_dir/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js || echo "not found"
sed -i 's|2 (\(default\))|2|' $python_dir/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js || echo "not found"

sed -i 's|default: 2|default: 0|' '/opt/conda/pkgs/jupyter_contrib_nbextensions-0.5.1-pyhd8ed1ab_2/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/opt/conda/pkgs/ || echo "not found"jupyter_contrib_nbextensions-0.5.1-pyhd8ed1ab_2/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js' || echo "not found"
sed -i 's|2 (\(default\))|2|' '/opt/conda/pkgs/jupyter_contrib_nbextensions-0.5.1-pyhd8ed1ab_2/site-packages/jupyter_contrib_nbextensions/nbextensions/autosavetime/main.js' || echo "not found"

sed -i 's|default: 2|default: 0|' '/home/sciencedata/.local/share/jupyter/nbextensions/autosavetime/autosavetime.yaml' || echo "not found"
sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' '/home/sciencedata/.local/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"
sed -i 's|2 (\(default\))|2|' '/home/sciencedata/.local/share/jupyter/nbextensions/autosavetime/main.js' || echo "not found"

# Bash kernel
mamba install --quiet --yes bash_kernel
python -m bash_kernel.install

# ROOT kernel
sudo apt update
sudo apt install libglu1-mesa libopengl0
pip install metakernel
pip install zmq
mamba install root -c conda-forge

# For the ensteinpy examples
pip install einsteinpy

# For the astropy examples
pip install astropy astroquery notebook git+https://github.com/radio-astro-tools/spectral-cube radio-beam reproject dust_extinction gala dust_extinction synphot

# For riemann_book
mamba install clawpack

python_dir=`ls -d /opt/conda/lib/python* | tail -1`

# Spinning wheel on ajax calls
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
sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' $python_dir/site-packages/urllib3/connection.py

# Fix https://github.com/ipython-contrib/jupyter_contrib_nbextensions/issues/1529
grep -r template_path $python_dir/site-packages/jupyter_contrib_nbextensions | grep '.py:' | while read line; do name=`echo $line | awk -F: '{print $1}'`; grep template_paths "$name" || sed -i 's|template_path|template_paths|g' "$name"; done
grep -r template_path $python_dir/site-packages/latex_envs | grep '.py:' | while read line; do name=`echo $line | awk -F: '{print $1}'`; grep template_paths "$name" || sed -i 's|template_path|template_paths|g' "$name"; done

# Fix what appears to be a Jupyter bug - preventing JupyterLab from starting
sed -i -r 's|(self\.contents_manager\.preferred_dir)|#\1|' $python_dir/site-packages/jupyter_server/serverapp.py

# Enable nbextensions tab in nbclassic
#cp -r $python_dir/site-packages/jupyter_nbextensions_configurator/static/nbextensions_configurator \
#~/.local/share/jupyter/nbextensions/
rm -rf ~/.local/share/jupyter/nbextensions/*
cd $python_dir/site-packages/jupyter_nbextensions_configurator;  cp -r static/nbextensions_configurator \
/opt/conda/share/jupyter/nbextensions/ && cp -r application.py templates \
/opt/conda/share/jupyter/nbextensions/nbextensions_configurator/

sed -i -r "s|(\{\{super\(\)\}\})|\1\n<script src=\"/static/notebook/js/main.min.js\" type=\"text/javascript\" charset=\"utf-8\"></script>|" \
$python_dir/site-packages/jupyter_nbextensions_configurator/templates/nbextensions_configurator.html

# Keep notebooks in sciencedata homedir ('/files')
echo "from jupyter_sciencedata import JupyterScienceData" >> /etc/jupyter/jupyter_notebook_config.py &&\
echo "c.NotebookApp.contents_manager_class = 'jupyter_sciencedata.JupyterScienceData'" >> /etc/jupyter/jupyter_notebook_config.py &&\
echo "c.NotebookApp.allow_origin = '*'" >> /etc/jupyter/jupyter_server_config.py

cp /opt/conda/etc/jupyter/jupyter_notebook_config.d/jupyter_nbextensions_configurator.json \
/opt/conda/etc/jupyter/jupyter_server_config.d/jupyter_nbextensions_configurator.json &&\
sed -i 's|NotebookApp|ServerApp|' /opt/conda/etc/jupyter/jupyter_server_config.d/jupyter_nbextensions_configurator.json
jupyter nbextensions_configurator enable
jupyter labextension disable "@jupyterlab/apputils-extension:announcements"


