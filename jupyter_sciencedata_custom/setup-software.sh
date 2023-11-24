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

# Make sure that in the container we're in the homedir (ROOT writes tmp files to cwd)
sed -i -E "s|(import sys)|\1\nimport os|" /opt/conda/lib/python3.8/site-packages/JupyROOT/__init__.py
echo 'os.chdir(os.path.expanduser("~"))' >> /opt/conda/lib/python3.8/site-packages/JupyROOT/__init__.py

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

# For LCG software, SETUP_SCRIPT could be /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/setup.sh
if [[ -n "$SETUP_SCRIPT" && -f "$SETUP_SCRIPT" ]]; then
	. "$SETUP_SCRIPT"
fi
