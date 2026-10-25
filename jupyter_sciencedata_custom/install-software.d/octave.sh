#!/bin/bash

#############################
# Octave + its Jupyter kernel
#############################
# Runs the MATLAB-language notebooks of the collection without a MATLAB licence.

set -e

sudo apt-get update
# fonts-freefont-otf: Octave's default font (FreeSans). Without it every axes fails
#   with "ft_text_renderer: invalid bounding box, cannot render".
# ghostscript: needed for print() to PNG, which the kernel uses for inline figures.
# gnuplot-nox: the only Octave graphics toolkit that works without a display.
# xvfb: a virtual X display for MATLAB (R2025+ draws even invisible figures with
#   web graphics that need one; start-notebook.d/matlab.sh starts it).
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    octave gnuplot-nox fonts-freefont-otf ghostscript xvfb xauth
sudo rm -rf /var/lib/apt/lists/*

pip install --no-cache-dir octave_kernel

# gnuplot prints a long "discouraged" warning on first use; keep it out of notebooks.
sudo mkdir -p /usr/share/octave/site/m/startup
echo "warning('off', 'Octave:gnuplot-graphics');" | sudo tee -a /usr/share/octave/site/m/startup/octaverc >/dev/null
