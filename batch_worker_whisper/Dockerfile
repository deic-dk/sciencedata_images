# Build command: docker build -t sciencedata/batch_worker_whisper .
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
RUN su gridfactory -c "pip install -U openai-whisper"
RUN su gridfactory -c "pip install --pre ttconv"

RUN ln -s /home/gridfactory/.local /root/.local
RUN ln -s /root/.local/bin /root/bin

