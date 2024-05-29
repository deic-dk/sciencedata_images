# Build command: docker build -t sciencedata/batch_server .
# Push command: docker push sciencedata/batch_server
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/batch_server
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/batch_server

FROM ubuntu:22.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Jammy for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y install ca-certificates

RUN apt update && apt install -y gpg gpgv1 curl apt-transport-https software-properties-common apt-utils

# Add cyberduck, get key manually due to apt-key deprecation
RUN echo "deb [signed-by=/usr/local/share/keyrings/cyberduck.gpg] https://s3.amazonaws.com/repo.deb.cyberduck.io stable main" | tee -a /etc/apt/sources.list.d/cyberduck.list \
    && mkdir -p /usr/local/share/keyrings \
    && gpg --keyserver keyserver.ubuntu.com --recv-keys FE7097963FEFBE72 \
    && gpg --export FE7097963FEFBE72 > /usr/local/share/keyrings/cyberduck.gpg \
    && rm -rf /root/.gnupg

RUN add-apt-repository "deb http://archive.canonical.com/ jammy partner"

RUN apt update --fix-missing

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common php-cli dropbear openssh-sftp-server iputils-ping \
traceroute php-yaml default-jre \
curl apache2 mysql-server libaprutil1-dbd-mysql libxml2-utils

# "unminimize" script provided by ubuntu:22.04 container restores expected shell features like installing
# man pages. The script itself is interactive, so this a modified version that runs without interaction
#RUN sed -i 's/^read.*//g' /usr/local/sbin/unminimize \
#    && sed -i 's/exit 1/echo "skip"/g' /usr/local/sbin/unminimize \
#    && sed -i 's/apt-get upgrade/apt-get upgrade -y/g' /usr/local/sbin/unminimize \
#    && /usr/local/sbin/unminimize

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Configure keyboard - not necessary
#RUN DEBIAN_FRONTEND=noninteractive apt-get -y install console-data

#RUN echo "www:secret" | chpasswd
RUN echo "www ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/www && chmod 0440 /etc/sudoers.d/www

# GridFactory debs

RUN curl -LO https://sciencedata.dk/sites/frederik.orellana/blog/files/gridfactory-2024/mod_gacl_ubuntu_0_9_2.deb
RUN curl -LO  https://sciencedata.dk/sites/frederik.orellana/blog/files/gridfactory-2024/mod_gridfactory_ubuntu_0_1_7.deb
RUN curl -LO  https://sciencedata.dk/sites/frederik.orellana/blog/files/gridfactory-2024/gridfactory_server_linux_0_1_5.deb
RUN curl -LO  https://sciencedata.dk/sites/frederik.orellana/blog/files/gridfactory-2024/gridfactory_cli_linux_0_1_5.deb

RUN dpkg --add-architecture i386
RUN dpkg --force-all -i *.deb

ADD start.sh /usr/local/sbin/start.sh

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc &&\
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc &&\
  mkdir /root/.ssh && touch /root/.ssh/authorized_keys && chmod -R go-rw /root/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22
EXPOSE 443

CMD ["/usr/local/sbin/start.sh"]
