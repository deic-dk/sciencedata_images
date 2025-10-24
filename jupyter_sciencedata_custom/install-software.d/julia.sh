#!/bin/bash

#####################
# Julia installation
#####################

set -e

cd /tmp
# Default values can be overridden at build time
# (ARGS are in lower case to distinguish them from ENV)
# Check https://julialang.org/downloads/
#export julia_version="1.5.3"
export julia_version="1.11.7"
# SHA256 checksum
#export julia_checksum="f190c938dd6fed97021953240523c9db448ec0a6760b574afd4e9924ab5615f1"
export julia_checksum="aa5924114ecb89fd341e59aa898cd1882b3cb622ca4972582c1518eff5f68c05"

# Julia dependencies
# install Julia packages in /opt/julia instead of $HOME
export JULIA_DEPOT_PATH=/opt/julia \
    JULIA_PKGDIR=/opt/julia \
    JULIA_VERSION="${julia_version}"

# hadolint ignore=SC2046
sudo mkdir "/opt/julia-${JULIA_VERSION}" && sudo chown $NB_USER "/opt/julia-${JULIA_VERSION}"

wget -q https://julialang-s3.julialang.org/bin/linux/x64/$(echo "${JULIA_VERSION}" | cut -d. -f 1,2)"/julia-${JULIA_VERSION}-linux-x86_64.tar.gz"
echo "${julia_checksum} *julia-${JULIA_VERSION}-linux-x86_64.tar.gz" | sha256sum -c - && \
tar xzf "julia-${JULIA_VERSION}-linux-x86_64.tar.gz" -C "/opt/julia-${JULIA_VERSION}" --strip-components=1
rm -f "/tmp/julia-${JULIA_VERSION}-linux-x86_64.tar.gz"
sudo ln -fs /opt/julia-${JULIA_VERSION}/bin/julia /usr/local/bin/julia

# Show Julia where conda libraries are \
sudo mkdir /etc/julia && sudo chown $NB_USER /etc/julia
echo "push\!(Libdl.DL_LOAD_PATH, \"$CONDA_DIR/lib\")" >> /etc/julia/juliarc.jl
# Create JULIA_PKGDIR
sudo mkdir "${JULIA_PKGDIR}" && sudo chown "${NB_USER}" "${JULIA_PKGDIR}"

# Add Julia packages. Only add HDF5 if this is not a test-only build since
# it takes roughly half the entire build time of all of the images on Travis
# to add this one package and often causes Travis to timeout.
#
# Install IJulia as $NB_USER and then move the kernelspec out
# to the system share location. Avoids problems with runtime UID change not
# taking effect properly on the .local folder in the $NB_USER home dir.
julia -e 'import Pkg; Pkg.update()'
(test $TEST_ONLY_BUILD || julia -e 'import Pkg; Pkg.add("HDF5")') && \
julia -e "using Pkg; pkg\"add IJulia\"; pkg\"precompile\""

# move kernelspec out of home
mv "${HOME}/.local/share/jupyter/kernels/julia"* "${CONDA_DIR}/share/jupyter/kernels/"
rm -rf "${HOME}/.local"


