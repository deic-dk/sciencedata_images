#!/bin/bash

############################
# ScienceData customization
############################

set -e

#sudo pip install -r requirements.txt

eval "$(conda shell.bash hook)"
conda activate python3.8

# Keep notebooks in user's sciencedata homedir ('/files')
pip install pycurl webdavclient3 lxml_html_clean
jupyter_server_version=`jupyter --version | grep jupyter_server | awk '{print $NF}'`
if [[ -z "$jupyter_server_version" || "$jupyter_server_version" > "2.10.9" ]]; then
  # For jupyter_server>=2.11, grab latest jupyter_sciencedata version
  git clone https://github.com/deic-dk/jupyter_sciencedata.git
else
  # For jupyter_server<2.11, grab version 1.0 of jupyter_sciencedata
  git clone --branch 1.0 https://github.com/deic-dk/jupyter_sciencedata.git
fi

pip install jupyter_server jupyter_sciencedata/

# Original requirements from https://github.com/genepattern/genepattern-notebook/tree/notebook
# Had to remove version from pandas and patch (commented below) scanpy-1.3.4 to be able to build the image.
# But it doesn't work: The versions of matplotlib and numpy are apparently not compatible...
# ImportError: numpy.core.multiarray failed to import
#curl -o scanpy-1.3.4.tar.gz "https://files.pythonhosted.org/packages/47/a2/3edd61806453cccad8828fc74b0d9377cf419abc14b737ed57187e446460/scanpy-1.3.4.tar.gz#sha256=fd1be48c00919ce72e67635a8d31e039d618865bc1456d72abf42570bcd760d6"
#tar -xzf scanpy-1.3.4.tar.gz
#sed -i "s|'\*\.txt'|['requirements.txt']|" scanpy-1.3.4/setup.py
# This one generates the first figure w/o graphs on the two last plots.
# It also generates the second figure
#pip install -r requirements.txt.orig

pip install -r requirements.txt

# Well, apparently this version of Jupyter has renamed jupyter_server to notebook...
sudo sed -i 's|from jupyter_server\.services\.contents\.|from notebook.services.contents.|' /opt/conda/lib/python*/site-packages/jupyter_sciencedata/jupyter_sciencedata.py || echo "No jupyter_sciencedata.py"
sudo sed -i 's|from jupyter_server\.services\.contents\.|from notebook.services.contents.|' /opt/conda/envs/python*/lib/python*/site-packages/jupyter_sciencedata/jupyter_sciencedata.py || echo "No jupyter_sciencedata.py"

sudo sed -i 's|jupyter_server\.contents.services\.managers\.ContentsManager|jupyter_server.services.contents.manager.ContentsManager|' /opt/conda/envs/python*/lib/python*/site-packages/notebook/notebookapp.py

sudo chown -R $NB_USER /etc/jupyter

python_dir=`ls -d /opt/conda/envs/python*/lib/python* | tail -1`

echo >> /etc/jupyter/jupyter_notebook_config.py
echo "from jupyter_sciencedata import JupyterScienceData" >> /etc/jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.contents_manager_class = 'jupyter_sciencedata.JupyterScienceData'" >> /etc/jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.allow_origin = '*'" >> /etc/jupyter/jupyter_server_config.py
echo "c.NotebookApp.ip = '0.0.0.0'" >> /etc/jupyter/jupyter_server_config.py

# Spinning wheel on ajax calls
sudo cp jupyter_sciencedata/custom/* $python_dir/site-packages/notebook/static/custom/ || echo "No notebook/static"
sudo cp jupyter_sciencedata/custom/* $python_dir/site-packages/nbclassic/static/custom/ || echo "No nbclassic/static"
ls -d $python_dir/site-packages/jupyterlab/themes/\@jupyterlab/theme-* | while read theme; do
  sudo cat jupyter_sciencedata/custom/custom.css >> $theme/index.css
  sudo cat jupyter_sciencedata/custom/custom.js >> $theme/index.js
done
ls -d /opt/conda/share/jupyter/lab/themes/\@jupyterlab/theme-* | while read theme; do
  sudo cat jupyter_sciencedata/custom/custom.css >> $theme/index.css
  sudo cat jupyter_sciencedata/custom/custom.js >> $theme/index.js
done

# Patch python's urllib to not match hostname with certificate
sudo sed -i -r 's|(and assert_hostname is not False)|\1 and server_hostname != "sciencedata"|' $python_dir/site-packages/urllib3/connection.py
sudo sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' $python_dir/site-packages/urllib3/connection.pynection.py || echo "No pynection"
sudo sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' $python_dir/site-packages/urllib3/connection.py
sudo sed -i -r 's|(or not ssl_\.HAS_NEVER_CHECK_COMMON_NAME)|\1 or server_hostname == "sciencedata"|' /opt/conda/envs/python*/lib/python*/site-packages/urllib3/connection.py || echo "No env"

sudo sed -i -r 's|raise$|#raise|' $python_dir/site-packages/urllib3/connection.py
sudo sed -i -r 's|raise$|#raise|' /opt/conda/envs/python*/lib/python*/site-packages/urllib3/connection.py || echo "No env"

###################################
# Jupyter fixes and customizations
###################################

# Turn off autosaving
find / -name main.js 2>/dev/null | grep autosavetime/main.js | while read name; do sed -i 's|autosavetime_starting_interval : 2,|autosavetime_starting_interval : 0,|' "$name"; done
find / -name autosavetime.yaml 2>/dev/null | while read name; do sed -i 's|default: 2|default: 0|' "$name"; done

echo "if(IPython.notebook){IPython.notebook.set_autosave_interval(0);}" >> $python_dir/site-packages/notebook/static/custom/custom.js || echo "No notebook/custom"
echo "if(IPython.notebook){IPython.notebook.set_autosave_interval(0);}" >> $python_dir/site-packages/nbclassic/static/custom/ || echo "No nbclassic/custom"


curl -L -o jquery-ui.js https://sciencedata.dk/public/kubefiles_shared/jupyter/jquery-ui-1.10.0.custom.js
curl -L -o bootstrap.js https://sciencedata.dk/public/kubefiles_shared/jupyter/bootstrap-3.3.0.js
cp jquery-ui.js bootstrap.js $python_dir/site-packages/notebook/static/custom/ || echo "No notebook/custom"
cp jquery-ui.js bootstrap.js $python_dir/site-packages/nbclassic/static/custom/ || echo "No nbclassic/custom"
#echo "requirejs(['/custom/jquery-ui.js', '/custom/bootstrap.js'])" >> $python_dir/site-packages/notebook/static/custom/custom.js || echo "No notebook/custom"
#echo "requirejs(['/custom/jquery-ui.js', '/custom/bootstrap.js'])" >> $python_dir/site-packages/nbclassic/static/custom/custom.js || echo "No nbclassic/custom"

sed -i -E "s| (\('#element'\)\.tooltip\('enable'\))| //\1|" $python_dir/site-packages/notebook/templates/tree.html || echo "No notebook/templates"

