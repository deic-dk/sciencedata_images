# Build command: docker build -t sciencedata/ubuntu_noble_mongodb_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_mongodb_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_mongodb_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_mongodb_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

ARG MY_USER="sciencedata"
ARG MY_UID="80"

ENV SHELL=/bin/bash \
    MY_USER=$MY_USER \
    MY_UID=$MY_UID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    MY_HOME=/home/$MY_USER \
    SD_UID=$SD_UID

RUN DEBIAN_FRONTEND=noninteractive apt update && apt -y install ca-certificates

RUN apt update && apt install -y gpg gpgv1 curl apt-transport-https

# Add MongoDB

RUN curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
RUN echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.2 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-8.2.list

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common php-cli php-fpm dropbear openssh-sftp-server \
iputils-ping traceroute php-yaml php-xml php-sqlite3 php-mbstring php-gd php-curl php-zip \
imagemagick ffmpeg zip unzip mongodb-org numactl

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# 
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid $MY_UID --home $MY_HOME --disabled-password --gecos 'Default user' $MY_USER

RUN echo "$MY_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$MY_USER && chmod 0440 /etc/sudoers.d/$MY_USER

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir $MY_HOME/.ssh && touch $MY_HOME/.ssh/authorized_keys && \
  chown -R $MY_USER $MY_HOME/.ssh && chmod -R go-rw $MY_HOME/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22
EXPOSE 27017

COPY mongod.conf /etc/mongod.conf
RUN chown $MY_USER /etc/mongod.conf
COPY start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh && chown $MY_USER /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]

