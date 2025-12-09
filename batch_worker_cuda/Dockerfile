# Build command: docker build -t sciencedata/batch_worker_cuda .
# Push command: docker push sciencedata/batch_worker_cuda
# Run command: docker run -p 8443:443 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/batch_worker_cuda
# Run command: docker run -p 8443:443 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/batch_worker_cuda

FROM nvidia/cuda:12.5.0-base-ubuntu22.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Jammy with GridFactory batch worker for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt update && apt -y install ca-certificates

RUN apt update && apt install -y gpg gpgv1 curl apt-transport-https software-properties-common apt-utils

# Add cyberduck, get key manually due to apt-key deprecation
RUN echo "deb [signed-by=/usr/local/share/keyrings/cyberduck.gpg] https://s3.amazonaws.com/repo.deb.cyberduck.io stable main" | tee -a /etc/apt/sources.list.d/cyberduck.list \
    && mkdir -p /usr/local/share/keyrings \
    && gpg --keyserver keyserver.ubuntu.com --recv-keys FE7097963FEFBE72 \
    && gpg --export FE7097963FEFBE72 > /usr/local/share/keyrings/cyberduck.gpg \
    && rm -rf /root/.gnupg

RUN add-apt-repository "deb http://archive.canonical.com/ jammy partner"

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq dropbear openssh-sftp-server iputils-ping \
traceroute php-yaml default-jre curl libxml2-utils \
cuda-toolkit-12-5
#libnvidia-decode-555 libnvidia-encode-555
#libnppig12 libnppicc12 libnppidei12 libnppif12

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# GridFactory debs
RUN curl -LO  https://sciencedata.dk/sites/frederik.orellana/blog/files/gridfactory-2024/gridfactory_cli_linux_0_1_5.deb
RUN curl -LO  https://sciencedata.dk/sites/frederik.orellana/blog/files/gridfactory-2024/gridworker_daemon_linux_0_1_5.deb

RUN dpkg --force-all -i *.deb

ADD start.sh /usr/local/sbin/start.sh

# Install ffmpeg with nvidia support
#COPY install_ffmpeg_nvidia.sh .
#RUN chmod +x install_ffmpeg_nvidia.sh
#RUN ./install_ffmpeg_nvidia.sh

WORKDIR /root
# Copy over ffmpeg compiled on worker1
#COPY ffmpeg.tar.gz .
RUN curl -LO https://sciencedata.dk/public/kubefiles_public/ffmpeg_batchworker/ffmpeg.tar.gz
RUN tar -xvzf ffmpeg.tar.gz

# We need exacly the same version of this library as the one on the host system (worker1 for now)
#COPY libnvidia-encode.so.1 /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1
#COPY libnvcuvid.so.1 /usr/lib/x86_64-linux-gnu/libnvcuvid.so.1
RUN curl -L -o /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1 https://sciencedata.dk/public/kubefiles_public/ffmpeg_batchworker/libnvidia-encode.so.1
RUN curl -L -o /usr/lib/x86_64-linux-gnu/libnvcuvid.so.1 https://sciencedata.dk/public/kubefiles_public/ffmpeg_batchworker/libnvcuvid.so.1

# Configure ssh access + paths
RUN echo "alias ls='ls --color=auto'" >> .bashrc &&\
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:~/ffmpeg" >> ~/.bashrc &&\
  echo "export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:~/ffmpeg/libavcodec:~/ffmpeg/libavdevice:~/ffmpeg/libavfilter:~/ffmpeg/libavformat:~/ffmpeg/libavutil:~/ffmpeg/libpostproc:~/ffmpeg/libswresample:~/ffmpeg/libswscale" >> ~/.bashrc &&\
  mkdir /root/.ssh && touch /root/.ssh/authorized_keys && chmod -R go-rw /root/.ssh

# Make a random 1 out of the 10 GPUs visible
RUN gpus=$(echo $(shuf -i 0-9 -n 1 | sort -n | sed "s|$|,|") | sed 's| ||g' | sed 's|,$||') &&  echo "export CUDA_VISIBLE_DEVICES=$gpus" >>  ~/.bashrc

RUN apt -y autoremove && apt -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22
EXPOSE 443

CMD ["/usr/local/sbin/start.sh"]
