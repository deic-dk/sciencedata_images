# Build command: docker build -t kube.sciencedata.dk:5000/ubuntu_jammy_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key kube.sciencedata.dk:5000/ubuntu_jammy_sciencedata

FROM ubuntu:6e3729cf69e0@sha256:27cb6e6ccef575a4698b66f5de06c7ecd61589132d5a91d098f7f3f9285415a9
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Jammy for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt-get update

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bzip2 \
    ca-certificates \
    curl \
    git \
    gnupg \
    inetutils-tools \
    man-db \
    net-tools \
    openssh-client \
    openssh-server \
    vim \
    wget

# "unminimize" script provided by ubuntu:22.04 container restores expected shell features like installing
# man pages. The script itself is interactive, so this a modified version that runs without interaction
RUN sed -i 's/^read.*//g' /usr/local/sbin/unminimize
RUN sed -i 's/exit 1/echo "skip"/g' /usr/local/sbin/unminimize
RUN sed -i 's/apt-get upgrade/apt-get upgrade -y/g' /usr/local/sbin/unminimize
RUN /usr/local/sbin/unminimize

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales
RUN locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

RUN mkdir /run/sshd

# Configure ssh access
RUN echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc
RUN mkdir /root/.ssh
RUN touch /root/.ssh/authorized_keys
RUN chmod -R go-rw /root/.ssh

RUN sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -ri 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config && \
    sed -ri 's/^#?PasswordAuthentication\s.*/PasswordAuthentication no/g' /etc/ssh/sshd_config

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

EXPOSE 22

CMD ["/usr/local/sbin/start.sh"]
