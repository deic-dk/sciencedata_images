# Copyright (c) Jupyter Development Team.
# Modified/extended by the ScienceData team
# Distributed under the terms of the Modified BSD License.

# Build command: docker build -t sciencedata/jupyter_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 sciencedata/jupyter_sciencedata

FROM jupyter/scipy-notebook:3d10155c955f@sha256:5bce431c1b63525dc8749747b09133b2a66a01df10b533ad70a106add7a65bb5

ADD --chown=root:root ["before-notebook.d", "/usr/local/bin/before-notebook.d"]
