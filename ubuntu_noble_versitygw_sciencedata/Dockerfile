# Build command: docker build -t sciencedata/ubuntu_noble_versitygw_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_versitygw_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_versitygw_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_versitygw_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute s3cmd

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Create user s3 with UID 80 - to support r/w on NFS-mounted ScienceData partition.
RUN bash -c "sed -i -E 's|(UID_MIN\s+)1000|\179|' /etc/login.defs"
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid 80 --home /home/s3 --disabled-password --gecos '' s3 && \
    mkdir /home/s3/vgw /home/s3/accounts && \
    chown -R s3:s3 /home/s3

#RUN echo "s3:secret" | chpasswd
RUN echo "s3 ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/s3 && chmod 0440 /etc/sudoers.d/s3

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir /home/s3/.ssh && touch /home/s3/.ssh/authorized_keys && \
  chown -R s3:s3 /home/s3/.ssh && chmod -R go-rw /home/s3/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add VersityGW
RUN curl -LO https://github.com/versity/versitygw/releases/download/v1.4.1/versitygw_1.4.1_linux_amd64.deb
RUN dpkg -i versitygw_1.4.1_linux_amd64.deb

# Add AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && ./aws/install

EXPOSE 22
EXPOSE 7070

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]
