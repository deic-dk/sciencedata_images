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
    'r-gplots' \
    'r-minpack.lm' \
    'r-rjags' \
    'jags' \
    'r-r2jags' \
    'r-idpmisc' \
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

# Proteomics example notebook (S. aureus dataset): the author's analysis uses limma, DEqMS,
# EnhancedVolcano and fgsea (Bioconductor) plus pheatmap, naniar and corrplot.
mamba install --yes -c conda-forge -c bioconda \
    'bioconductor-limma' \
    'bioconductor-deqms' \
    'bioconductor-enhancedvolcano' \
    'bioconductor-fgsea' \
    'r-pheatmap' \
    'r-naniar' \
    'r-corrplot'
