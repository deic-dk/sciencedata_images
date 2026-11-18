# Build command: docker build --no-cache --pull -t sciencedata/batch_worker_whisper .
# Push command: docker push sciencedata/batch_worker_whisper
# Run command: docker run -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/batch_worker_whisper
# Run command: docker run -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/batch_worker_whisper

FROM sciencedata/batch_worker
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="OpenAI Whisper on Ubuntu noble for deployment on sciencedata.dk"

RUN adduser --uid 80 --home /home/gridfactory --disabled-password --gecos '' gridfactory
RUN cp -a /root/.ssh /home/gridfactory/ && chown -R gridfactory:gridfactory /home/gridfactory/.ssh

RUN apt update && apt install -y python3-pip ffmpeg
# CPU-only PyTorch: pip's default PyTorch for Linux is the CUDA build and pulls about
# 3 GB of NVIDIA libraries, and openai-whisper requires triton (GPU kernels only) -
# useless here, as this image has no GPU (batch_worker_cuda_whisper is the GPU one).
# So: a current pip (Ubuntu 22.04's cannot read the current openai-whisper sdist),
# PyTorch from its CPU index, whisper without its dependency list, then the
# dependencies it needs on a CPU. Python packages 5.6 GB -> 1.2 GB.
RUN su gridfactory -c "python3 -m pip install --user -U pip"
RUN su gridfactory -c "python3 -m pip install --user torch --index-url https://download.pytorch.org/whl/cpu"
RUN su gridfactory -c "python3 -m pip install --user --no-deps openai-whisper"
RUN su gridfactory -c "python3 -m pip install --user numba numpy tqdm more-itertools tiktoken"
RUN su gridfactory -c "pip install --pre ttconv"

RUN ln -s /home/gridfactory/.local /root/.local
RUN ln -s /root/.local/bin /root/bin

