# Build command: docker build -t sciencedata/ubuntu_focal_caddy_sciencedata .
# Push command: docker push sciencedata/ubuntu_focal_caddy_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_focal_caddy_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_focal_caddy_sciencedata

FROM ubuntu:20.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Focal for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates

# Add universe
#RUN echo "deb http://dk.archive.ubuntu.com/ubuntu focal universe" >> /etc/apt/sources.list
# Add Caddy
RUN echo "deb [trusted=yes] https://apt.fury.io/caddy/ /" | tee -a /etc/apt/sources.list.d/caddy-fury.list
# Add duck
RUN echo  "deb [trusted=yes] https://s3.amazonaws.com/repo.deb.cyberduck.io stable main" | tee -a /etc/apt/sources.list.d/cyberduck.list

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gpg gpgv1

RUN DEBIAN_FRONTEND=noninteractive apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FE7097963FEFBE72

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang cron \
apt-transport-https wget jq nfs-common caddy php-cli php-fpm dropbear iputils-ping traceroute php-yaml duck

# Create user www with UID 80 - to support r/w on NFS-mounted ScienceData partition.
# When starting caddy as root, it switches to the user with $HOME /var/lib/caddy
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    deluser caddy && \
    adduser --uid 80 --home /var/lib/caddy --disabled-password --gecos '' www && \
    chown -R www:www /var/lib/caddy

#RUN echo "www:secret" | chpasswd
RUN echo "www ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/www && chmod 0440 /etc/sudoers.d/www

# Configure caddy
RUN sed -i 's|www-data|www|' /etc/php/*/fpm/pool.d/www.conf
ADD Caddyfile /etc/caddy/Caddyfile
ADD index.php /tmp/index.php
ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh
RUN rmdir /var/log/caddy && touch /var/log/caddy.log && chown www:www /var/log/caddy.log

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales
RUN locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8
# systemd stuff - not working under docker
#RUN localectl set-locale LANGUAGE="en_US:en"
#RUN localectl set-locale LANG="en_US.utf8"

# Configure keyboard - not necessary
#RUN DEBIAN_FRONTEND=noninteractive apt-get -y install console-data

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc &&\
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc &&\
  mkdir /var/lib/caddy/.ssh && touch /var/lib/caddy/.ssh/authorized_keys  && \
  chown -R www:www /var/lib/caddy/.ssh && chmod -R go-rw /var/lib/caddy/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22
EXPOSE 80
# Caddy runs admin endpoint on port 2019
#EXPOSE 2019

CMD ["/usr/local/sbin/start.sh"]
