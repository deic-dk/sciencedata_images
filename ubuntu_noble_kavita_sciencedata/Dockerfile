# Build command: docker build -t sciencedata/ubuntu_noble_kavita_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_kavita_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_kavita_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_kavita_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common caddy dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Create user kavita with UID 80 - to support r/w on NFS-mounted ScienceData partition.
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid 80 --home /home/kavita --disabled-password --gecos '' kavita && \
    mkdir /home/kavita/ebooks && \
    chown -R kavita:kavita /home/kavita

#RUN echo "kavita:secret" | chpasswd
RUN echo "kavita ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/kavita && chmod 0440 /etc/sudoers.d/kavita

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir /home/kavita/.ssh && touch /home/kavita/.ssh/authorized_keys && \
  chown -R kavita:kavita /home/kavita/.ssh && chmod -R go-rw /home/kavita/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add Kavita
RUN curl -L -o /home/kavita/kavita-linux-x64.tar.gz https://github.com/Kareadita/Kavita/releases/download/v0.8.7/kavita-linux-x64.tar.gz
RUN cd /home/kavita && tar -xvzf kavita-linux-x64.tar.gz && chown -R kavita:kavita kavita-linux-x64.tar.gz Kavita && chmod +x Kavita/Kavita

EXPOSE 22
EXPOSE 5000

ADD appsettings.json  /home/kavita/Kavita/config/appsettings.json
ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]
