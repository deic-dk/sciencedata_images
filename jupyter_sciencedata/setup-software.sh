#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.

if [ -e /var/run/sciencedata_software ]; then
	exit 0
fi

sudo bash<<END >&/dev/null

export PATH=/opt/conda/bin:$PATH

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts

if [ -d /usr/local/software/matlab ]; then
	ln -s /usr/local/software/MATLAB/R2020b/bin/matlab /usr/local/bin/matlab
	pip install matlab_kernel
	python -m matlab_kernel install
	cd /usr/local/software/MATLAB/R2020b/extern/engines/python
	python setup.py install
fi

ln -s /usr/local/software/Wolfram/WolframEngine/12.2/Executables/wolframscript /usr/bin/wolframscript

touch /var/run/sciencedata_software

END

if [[ -n $MMA_LICENSE_SERVER ]]; then
	cd
	mkdir -p .Mathematica/Licensing
	echo '!'"${LICENSE_SERVER}" > .Mathematica/Licensing/mathpass
	wolframscript -configure WOLFRAMSCRIPT_KERNELPATH=/usr/local/software/Wolfram/Mathematica/12.1/Executables/WolframKernel
	~/WolframLanguageForJupyter/configure-jupyter.wls add
	mv ~/WolframLanguageForJupyter /tmp/
fi

