# Build command: docker build -t sciencedata/ubuntu_focal_sciencedata .
# Push command: docker push sciencedata/ubuntu_focal_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_focal_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_focal_sciencedata

FROM ubuntu:20.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Focal for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y install ca-certificates

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gpg gpgv1
RUN DEBIAN_FRONTEND=noninteractive apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FE7097963FEFBE72

# Add universe
#RUN echo "deb http://dk.archive.ubuntu.com/ubuntu focal universe" >> /etc/apt/sources.list
# Add duck
RUN echo  "deb [trusted=yes] https://s3.amazonaws.com/repo.deb.cyberduck.io stable main" | tee -a /etc/apt/sources.list.d/cyberduck.list

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq dropbear openssh-sftp-server iputils-ping traceroute php-yaml \
libxcb-shm0 libxcb-render0 libxrender1 libxpm4 libpciaccess0

ADD start.sh /root/start.sh
RUN chmod +x /root/start.sh

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales
RUN locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8
# systemd stuff - not working under docker
#RUN localectl set-locale LANGUAGE="en_US:en"
#RUN localectl set-locale LANG="en_US.utf8"

# Configure keyboard - not necessary
#RUN DEBIAN_FRONTEND=noninteractive apt-get -y install console-data

RUN mkdir /var/run/sshd

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc &&\
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc &&\
  mkdir /root/.ssh && touch /root/.ssh/authorized_keys && chmod -R go-rw /root/.ssh

#RUN sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
#RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config

RUN apt-get -y autoremove && apt-get clean &&\
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22

#CMD ["/usr/sbin/sshd", "-D"]
#ENTRYPOINT ["/root/start.sh"]
CMD ["/root/start.sh"]
