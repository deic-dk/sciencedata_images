#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.


sudo bash<<END

# Keep notebooks in sciencedata homedir
export PATH=/opt/conda/bin:$PATH
git clone https://github.com/deic-dk/jupyter_sciencedata.git
pip install jupyter_sciencedata/

# Monkey patch python's urllib to not match hostname with certificate
sed -i 's|and self.assert_hostname is not False|and self.assert_hostname is not False and False|' /opt/conda/lib/python3.8/site-packages/urllib3/connection.py

if [ ! -e /var/run/sciencedata_software ]; then
	# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
	[[ -n "$HOME_SERVER" ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
	[[ -n "$HOME_SERVER" ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
	# Symlink wolframscript
	ln -s /usr/local/software/Wolfram/WolframEngine/12.2/Executables/wolframscript /usr/bin/wolframscript
	touch /var/run/sciencedata_software
fi

if [[ -n "$SETUP_MATLAB" && -d /usr/local/software/MATLAB ]]; then

	ln -s /usr/local/software/MATLAB/R2020b/bin/matlab /usr/local/bin/matlab
	pip install matlab_kernel
	python -m matlab_kernel install
	cd /usr/local/software/MATLAB/R2020b/extern/engines/python
	python setup.py install
fi

END

if [[ -n "$SETUP_MATHEMATICA" && -d /usr/local/software/Wolfram && -n "$MMA_LICENSE_SERVER" ]]; then
	if [[ -n "$MMA_LICENSE_SERVER" ]]; then
		cd
		mkdir -p ~/.Mathematica/Licensing
		echo '!'"${MMA_LICENSE_SERVER}" > ~/.Mathematica/Licensing/mathpass
		wolframscript -configure WOLFRAMSCRIPT_KERNELPATH=/usr/local/software/Wolfram/Mathematica/12.1/Executables/WolframKernel
		# This takes a long time (it's apparently running some license unprotect stuff with Wolfram HQ)
		~/WolframLanguageForJupyter/configure-jupyter.wls add
	elif [[ -n "$MMA_MATHPASS" ]]; then
		cd
		mkdir -p ~/.Mathematica/Licensing
		echo "${MMA_MATHPASS}" > ~/.Mathematica/Licensing/mathpass
		wolframscript -configure WOLFRAMSCRIPT_KERNELPATH=/usr/local/software/Wolfram/Mathematica/12.1/Executables/WolframKernel
		~/WolframLanguageForJupyter/configure-jupyter.wls add
		mv ~/WolframLanguageForJupyter /tmp/
	fi
fi
