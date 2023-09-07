# Build command: docker build -t sciencedata/ubuntu_jammy_sciencedata .
# Push command: docker push sciencedata/ubuntu_jammy_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_jammy_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_jammy_sciencedata

FROM ubuntu:22.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Jammy for deployment on sciencedata.dk"

# temporary fix for 22.04 container, should be able to safely remove when newer docker version is available
#RUN sed -i -e 's/^DPkg/# DPkg/' -e 's/^APT/# APT/' /etc/apt/apt.conf.d/docker-clean

RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq iputils-ping traceroute man-db dropbear openssh-sftp-server php-yaml

# Add cyberduck, get key manually due to apt-key deprecation
RUN echo "deb [signed-by=/usr/local/share/keyrings/cyberduck.gpg] https://s3.amazonaws.com/repo.deb.cyberduck.io stable main" | tee -a /etc/apt/sources.list.d/cyberduck.list
RUN mkdir -p /usr/local/share/keyrings
RUN gpg --keyserver keyserver.ubuntu.com --recv-keys FE7097963FEFBE72
RUN gpg --export FE7097963FEFBE72 > /usr/local/share/keyrings/cyberduck.gpg
RUN rm -rf /root/.temp-keyring.gpg* /root/.gnupg
RUN apt update --fix-missing
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y duck

# "unminimize" script provided by ubuntu:22.04 container restores expected shell features like installing
# man pages. The script itself is interactive, so this a modified version that runs without interaction
#RUN sed -i 's/^read.*//g' /usr/local/sbin/unminimize
#RUN sed -i 's/exit 1/echo "skip"/g' /usr/local/sbin/unminimize
#RUN sed -i 's/apt-get upgrade/apt-get upgrade -y/g' /usr/local/sbin/unminimize
#RUN /usr/local/sbin/unminimize

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales
RUN locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8
# systemd stuff - not working under docker
#RUN localectl set-locale LANGUAGE="en_US:en"
#RUN localectl set-locale LANG="en_US.utf8"

# Configure keyboard - not necessary
#RUN DEBIAN_FRONTEND=noninteractive apt-get -y install console-data

RUN apt -y autoremove && apt clean

RUN mkdir /run/sshd

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc &&\
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc &&\
  mkdir /root/.ssh && touch /root/.ssh/authorized_keys && chmod -R go-rw /root/.ssh

#RUN sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
#RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config

RUN apt-get -y autoremove && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

EXPOSE 22

CMD ["/usr/local/sbin/start.sh"]
