#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.

export EXTRA_SOFTWARE_DIR=/usr/local/software/extra
export USER_MAPPING=/usr/local/software/extra/user_mapping.txt
export PYTHON=/opt/conda/bin/python
export NB_USER
export SD_UID

export SETUP_MATHEMATICA
export MATHEMATICA_SOFTWARE_DIR=`ls -d /usr/local/software/Wolfram/Mathematica/* | sort | tail -1`
export WOLFRAM_JUPYTER_DIR=/usr/local/software/Wolfram/WolframLanguageForJupyter

export SETUP_MATLAB
export MATLAB_SOFTWARE_DIR=/usr/local/software/matlab
export MATLAB_SOFTWARE_DIR
export MATLAB_LICENSE_SERVER
export MATLAB_LICENSE_PORT

sudo bash<<END
export PATH=/opt/conda/bin:$PATH
if [[ ! -e /var/run/sciencedata_software ]]; then
	# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
	[[ -n "$HOME_SERVER" ]] && ( grep sciencedata /etc/hosts >& /dev/null || echo "$HOME_SERVER	sciencedata" >> /etc/hosts )
	[[ -n "$HOME_SERVER" ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
fi
END

# Make sure that in the container we're in the homedir (ROOT writes tmp files to cwd)
sed -i -E "s|(import sys)|\1\nimport os|" `ls -d /opt/conda/lib/python*/site-packages/JupyROOT/__init__.py | tail -1`
echo 'os.chdir(os.path.expanduser("~"))' >> `ls -d /opt/conda/lib/python*/site-packages/JupyROOT/__init__.py | tail -1`

# Fix what appears to be a Jupyter bug
if [[ -e /opt/conda/lib/python*/site-packages/nbclassic/nbserver.py && -n "$JUPYTER_ENABLE_LAB" ]]; then
	sed -i -r "s|^(manager\.link_extension\(name)(, serverapp\))|\1)\n                #\1\2|" /opt/conda/lib/python*/site-packages/nbclassic/nbserver.py || echo no nbserver.py
fi

if [[ -n "$SETUP_MATHEMATICA" && -d "$MATHEMATICA_SOFTWARE_DIR" ]]; then

sudo -u $NB_USER -E bash<<"END"

	# Patch Mathematica and WolframKernel
	sudo chown -R $NB_USER "$MATHEMATICA_SOFTWARE_DIR/Executables"
	for file in WolframKernel Mathematica; do
	grep OVERRIDE_USER "$MATHEMATICA_SOFTWARE_DIR/Executables/$file" >& /dev/null || \
		sed -E -i.orig "s|^(\#  Copyright .*)$|\1\nuser_domain=\`echo \$SD_UID \| sed -E 's\|^\([^@]+\)@\([^@]+\)$\|\\\2\|'\`\nuser_name=\`echo \$SD_UID \| sed -E 's\|^\([^@]+\)@\([^@]+\)$\|\\\1\|'\`\nuser_line=\`grep -E \"^\$SD_UID:\" $EXTRA_SOFTWARE_DIR/user_mapping.txt\`\nexport LD_PRELOAD=$EXTRA_SOFTWARE_DIR/getpwuid_modify.so\n. \$HOME/.bashrc\ntest -n \"\$user_line\" && export OVERRIDE_USER=\`echo \$user_line \| awk -F : '{print \$2}'\`\n. $HOME/.bashrc\ntest -z \"\$OVERRIDE_USER\" && export OVERRIDE_USER=\$user_name|" "$MATHEMATICA_SOFTWARE_DIR/Executables/$file"
	done

	# Symlink wolframscript
	ls /usr/bin/wolframscript >& /dev/null || sudo ln -s "$MATHEMATICA_SOFTWARE_DIR/Executables/wolframscript" /usr/bin/wolframscript
	sudo chown -R $NB_USER "$WOLFRAM_JUPYTER_DIR"
	if [[ -n "$MMA_LICENSE_SERVER" ]]; then
		# First check if we're an allowed test user
		user_line=`grep -E "^$SD_UID:" $USER_MAPPING`
		user_name=`echo $user_line | awk -F : '{print $2}'`
		#  Check if we're a DTU user
		if [ -z "$user_name" ]; then
			user_domain=`echo $SD_UID | sed -E 's|^([^@]+)@([^@]+)$|\2|'`
			user_name=`echo $SD_UID | sed -E 's|^([^@]+)@([^@]+)$|\1|'`
			if [[ "$user_domain" != "dtu.dk" || "$user_name" == "$SD_UI" || "$user_name" == "" ]]; then
				echo "Only DTU users are allowed to use Mathematica"
				exit 0
			fi
		fi
		echo "Setting up licensing"
		ls ~/.Mathematica/Licensing >& /dev/null || mkdir -p ~/.Mathematica/Licensing
		echo '!'"${MMA_LICENSE_SERVER}" > ~/.Mathematica/Licensing/mathpass
		export OVERRIDE_USER=$user_name
		export LD_PRELOAD="$EXTRA_SOFTWARE_DIR/getpwuid_modify.so"
		echo "export OVERRIDE_USER=$user_name" >> ~/.bashrc
		echo "export LD_PRELOAD=\"$EXTRA_SOFTWARE_DIR/getpwuid_modify.so\"" >> ~/.bashrc
		"$MATHEMATICA_SOFTWARE_DIR/Executables/wolframscript" -configure WOLFRAMSCRIPT_KERNELPATH=$MATHEMATICA_SOFTWARE_DIR/Executables/WolframKernel
		# This may take a long time (it's apparently running some license unprotect stuff with Wolfram HQ)
		"$WOLFRAM_JUPYTER_DIR/configure-jupyter.wls" add
	elif [[ -n "$MMA_MATHPASS" ]]; then
		mkdir -p ~/.Mathematica/Licensing
		echo "${MMA_MATHPASS}" > ~/.Mathematica/Licensing/mathpass
		wolframscript -configure WOLFRAMSCRIPT_KERNELPATH=$MATHEMATICA_SOFTWARE_DIR/Executables/WolframKernel
		"$WOLFRAM_JUPYTER_DIR/configure-jupyter.wls" add
	fi
fi

END

chown -R sciencedata /home/sciencedata/.local

fi

if [[ -n "$SETUP_MATLAB" && -d "$MATLAB_SOFTWARE_DIR" && -n "$MATLAB_LICENSE_SERVER" && -n "$MATLAB_LICENSE_PORT" ]]; then
  # First check if we're a DTU user
  user_domain=`echo $SD_UID | sed -E 's|^([^@]+)@([^@]+)$|\2|'`
  user_name=`echo $SD_UID | sed -E 's|^([^@]+)@([^@]+)$|\1|'`
  if [[ "$user_domain" != "dtu.dk" || "$user_name" == "$SD_UI" || "$user_name" == "" ]]; then
    echo "Only DTU users are allowed to use MATLAB"
    exit 0
  fi
  export LM_LICENSE_FILE="$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER"
  grep LM_LICENSE_FILE ~/.bashrc >& /dev/null || echo "export LM_LICENSE_FILE=$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER" >> ~/.bashrc
  sudo ln -s "$MATLAB_SOFTWARE_DIR/bin/matlab" /usr/local/bin/matlab
  pip install matlab_kernel
  sed -i -r "s|(import __version__)|\1\nos.environ['LM_LICENSE_FILE'] = \"$MATLAB_LICENSE_PORT@$MATLAB_LICENSE_SERVER\"\n|" /opt/conda/lib/python*/site-packages/matlab_kernel/kernel.py
  #sudo /opt/conda/bin/python -m matlab_kernel install
  cd "$MATLAB_SOFTWARE_DIR/extern/engines/python"
  sudo "$PYTHON" setup.py install
  # Two kernels are installed: matlab and matlab_connect. Don't see why we need more than one way to do the same...
  jupyter kernelspec remove -y matlab_connect
fi

# For LCG software, SETUP_SCRIPT could be /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-ubuntu2004-gcc9-opt/setup.sh
if [[ -n "$SETUP_SCRIPT" && -f "$SETUP_SCRIPT" ]]; then
	. "$SETUP_SCRIPT"
fi

echo "Software setup all done"
