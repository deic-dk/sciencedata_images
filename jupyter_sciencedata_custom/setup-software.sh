#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.

sudo bash<<END
export PATH=/opt/conda/bin:$PATH
if [[ ! -e /var/run/sciencedata_software ]]; then
	# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
	[[ -n "$HOME_SERVER" ]] && ( grep sciencedata /etc/hosts >& /dev/null || echo "$HOME_SERVER	sciencedata" >> /etc/hosts )
	[[ -n "$HOME_SERVER" ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
fi
END

# Fix what appears to be a Jupyter bug
if [[ -e /opt/conda/lib/python*/site-packages/nbclassic/nbserver.py && -n "$JUPYTER_ENABLE_LAB" ]]; then
	sed -i -r "s|^(manager\.link_extension\(name)(, serverapp\))|\1)\n                #\1\2|" /opt/conda/lib/python*/site-packages/nbclassic/nbserver.py
fi

if [[ -n "$SETUP_MATHEMATICA" && -d /usr/local/software/Wolfram ]]; then
	# Symlink wolframscript
	sudo ln -s /usr/local/software/Wolfram/Mathematica/*/Executables/wolframscript /usr/bin/wolframscript
	sudo chown -R sciencedata /usr/local/software/Wolfram/WolframLanguageForJupyter
	if [[ -n "$MMA_LICENSE_SERVER" ]]; then
		cd
		mkdir -p ~/.Mathematica/Licensing
		echo '!'"${MMA_LICENSE_SERVER}" > ~/.Mathematica/Licensing/mathpass
		wolframscript -configure WOLFRAMSCRIPT_KERNELPATH=`ls /usr/local/software/Wolfram/Mathematica/*/Executables/WolframKernel`
		# This takes a long time (it's apparently running some license unprotect stuff with Wolfram HQ)
		/usr/local/software/Wolfram/WolframLanguageForJupyter/configure-jupyter.wls add
	elif [[ -n "$MMA_MATHPASS" ]]; then
		cd
		mkdir -p ~/.Mathematica/Licensing
		echo "${MMA_MATHPASS}" > ~/.Mathematica/Licensing/mathpass
		wolframscript -configure WOLFRAMSCRIPT_KERNELPATH=/usr/local/software/Wolfram/Mathematica/*/Executables/WolframKernel
		/usr/local/software/Wolfram/WolframLanguageForJupyter/configure-jupyter.wls add
	fi
fi

if [[ -n "$SETUP_MATLAB" && -d /usr/local/software/matlab && -n "$MATLAB_LICENSE_SERVER" && -n "$MATLAB_LICENSE_PORT" ]]; then
	export LM_LICENSE_FILE="$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER"
	grep LM_LICENSE_FILE ~/.bashrc >& /dev/null || echo "export LM_LICENSE_FILE=$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER" >> ~/.bashrc
	sudo ln -s /usr/local/software/matlab/bin/matlab /usr/local/bin/matlab
	pip install matlab_kernel
	sed -i -r "s|(import __version__)|\1\nos.environ['LM_LICENSE_FILE'] = \"$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER\"\n|" /opt/conda/lib/python3.8/site-packages/matlab_kernel/kernel.py
	#sudo /opt/conda/bin/python -m matlab_kernel install
	cd /usr/local/software/matlab/extern/engines/python
	sudo /opt/conda/bin/python setup.py install
	# Two kernels are installed: matlab and matlab_connect. Don't see why we need more than one way to do the same...
	jupyter kernelspec remove -y matlab_connect
fi

# From https://github.com/wesketchum/Sample_Notebooks#starting-the-root-notebook-the-jupyter-way
if [[ -n "$SETUP_ROOT" && -n "$ROOTSYS" ]]; then

	# Set up a working root. - Dropped root from cvmfs, as this only exists with incomaptible versions of gcc and python
	# Instead use the one installed via conda - compiled against python3.8

	# /cvmfs/sft.cern.ch/lcg/releases/ROOT/6.28.04-6d2cc/x86_64-ubuntu2004-gcc9-opt/bin/thisroot.sh
	#. "$ROOTSYS/bin/thisroot.sh"
	#export PATH=/opt/conda/bin:$PATH
	#sudo ln -s /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/bin/python3.9 /usr/local/bin/python3.9
	
	#. /cvmfs/sft.cern.ch/lcg/releases/ROOT/6.28.04-6d2cc/x86_64-ubuntu2004-gcc9-opt/bin/thisroot.sh
	#export ROOT_INCLUDE_PATH=/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/include/Geant4:/cvmfs/sft.cern.ch/lcg/releases/jsonmcpp/3.10.5-f26c3/x86_64-ubuntu2004-gcc9-opt/include:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/src/cpp:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/include:/cvmfs/sft.cern.ch/lcg/releases/Python/3.9.12-1a716/x86_64-ubuntu2004-gcc9-opt/include/python3.9
	#export CPPYY_BACKEND_LIBRARY=/cvmfs/sft.cern.ch/lcg/releases/ROOT/6.28.04-6d2cc/x86_64-ubuntu2004-gcc9-opt/lib/libcppyy_backend3_9
	#export ROOTSYS=/cvmfs/sft.cern.ch/lcg/releases/ROOT/6.28.04-6d2cc/x86_64-ubuntu2004-gcc9-opt
	#export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/MCGenerators/thepeg/2.2.3-a9c9d/x86_64-ubuntu2004-gcc9-opt/lib/ThePEG:/cvmfs/sft.cern.ch/lcg/releases/MCGenerators/herwig++/7.2.3-0dab3/x86_64-ubuntu2004-gcc9-opt/lib/Herwig:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib/python3.9/site-packages/jaxlib/mlir/_mlir_libs:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib/python3.9/site-packages/torch/lib:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib/python3.9/site-packages/tensorflow:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib/python3.9/site-packages/tensorflow/contrib/tensor_forest:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib/python3.9/site-packages/tensorflow/python/framework:/cvmfs/sft.cern.ch/lcg/releases/java/8u362-88cd4/x86_64-ubuntu2004-gcc9-opt/jre/lib/amd64:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib64:/cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/lib
	#export PYTHONPATH=/opt/conda/lib/python3.8:$PYTHONPATH:/cvmfs/sft.cern.ch/lcg/releases/ROOT/6.28.04-6d2cc/x86_64-ubuntu2004-gcc9-opt/lib/JupyROOT
	#unset JUPYTER_PATH
	#unset JUPYTER_CONFIG_DIR
	
	cp -r `ls -d $ROOTSYS/etc/notebook/* | grep -v jupyter_notebook_config.py` /etc/jupyter/
	cat $ROOTSYS/etc/notebook/jupyter_notebook_config.py >> /etc/jupyter/jupyter_notebook_config.py
	cp -r "$ROOTSYS/etc/notebook/kernels/root" ~/.local/share/jupyter/kernels/
	sudo echo "c.NotebookApp.extra_static_paths = ['$ROOTSYS/js']" >> /etc/jupyter/jupyter_notebook_config.py
fi

# For LCG software, SETUP_SCRIPT could be /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/setup.sh
if [[ -n "$SETUP_SCRIPT" && -f "$SETUP_SCRIPT" ]]; then
	. "$SETUP_SCRIPT"
fi
