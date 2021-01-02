
FROM       ubuntu:20.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

# Add universe
RUN echo "deb http://dk.archive.ubuntu.com/ubuntu focal universe" >> /etc/apt/sources.list

RUN apt-get update

RUN apt-get install -y openssh-server openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang \
apt-transport-https wget jq nfs-common

# Configure locale
RUN apt-get install -y locales
RUN locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8
RUN localectl set-locale LANGUAGE="en_US:en"
RUN localectl set-locale LANG="en_US.utf8"

RUN mkdir /var/run/sshd

RUN echo 'root:root' | chpasswd

RUN sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config

RUN mkdir /root/.ssh

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22

CMD    ["/usr/sbin/sshd", "-D"]