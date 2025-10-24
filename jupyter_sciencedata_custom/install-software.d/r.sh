#!/bin/bash

##################
# R installation
##################

set -e

# R packages including IRKernel which gets installed globally.
mamba install --yes \
    'r-base'  \
    'r-caret' \
    'r-crayon' \
    'r-devtools' \
    'r-forecast' \
    'r-hexbin' \
    'r-htmltools' \
    'r-htmlwidgets' \
    'r-irkernel' \
    'r-nycflights13' \
    'r-randomforest' \
    'r-rcurl' \
    'r-rmarkdown' \
    'r-rsqlite' \
    'r-shiny' \
    'r-tidyverse' \
    'rpy2' && \
    conda clean --all -f -y && \
    . fix-permissions "${CONDA_DIR}" && \
    . fix-permissions "/home/${NB_USER}"