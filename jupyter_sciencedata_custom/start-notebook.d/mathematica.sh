#!/bin/bash

# Copyright (c) ScienceData Development Team.
# Distributed under the terms of the Modified BSD License.

export EXTRA_SOFTWARE_DIR=/usr/local/software/extra
export USER_MAPPING=/usr/local/software/extra/user_mapping.txt
export NB_USER
export SD_UID

export SETUP_MATHEMATICA
export MATHEMATICA_SOFTWARE_DIR=`ls -d /usr/local/software/Wolfram/Mathematica/* | sort | tail -1`
export WOLFRAM_JUPYTER_DIR=/usr/local/software/Wolfram/WolframLanguageForJupyter

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

echo "Mathematica setup all done"
