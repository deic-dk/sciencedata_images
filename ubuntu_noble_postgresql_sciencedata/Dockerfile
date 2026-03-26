# Build command: docker build -t sciencedata/ubuntu_noble_postgresql_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_postgresql_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_postgresql_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_postgresql_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

ARG MY_USER="sciencedata"
ARG MY_UID="80"
# Notice that SD_UID is the ScienceData user ID (someuser@somedomain.dk)

ENV SHELL=/bin/bash \
    MY_USER=$MY_USER \
    MY_UID=$MY_UID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    MY_HOME=/home/$MY_USER \
    SD_UID=$SD_UID

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt update && apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common php-cli php-fpm dropbear openssh-sftp-server \
iputils-ping traceroute php-yaml php-xml php-sqlite3 php-mbstring php-gd php-curl php-zip \
imagemagick ffmpeg zip unzip ca-certificates gpg gpgv1 curl apt-transport-https \
postgresql

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# 
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid $MY_UID --home $MY_HOME --disabled-password --gecos 'Default user' $MY_USER

#RUN echo "www:secret" | chpasswd
RUN echo "$MY_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$MY_USER && chmod 0440 /etc/sudoers.d/$MY_USER

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir $MY_HOME/.ssh && touch $MY_HOME/.ssh/authorized_keys && \
  chown -R $MY_USER $MY_HOME/.ssh && chmod -R go-rw $MY_HOME/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22
EXPOSE 5432

COPY postgresql.conf /etc/postgresql/16/main/postgresql.conf
COPY pg_hba.conf /etc/postgresql/16/main/pg_hba.conf
RUN chown -R postgres:postgres /etc/postgresql/16/main
COPY start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh && chown $MY_USER /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]

