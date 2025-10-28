# Build command: docker build -t sciencedata/ubuntu_noble_jellyfin_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_jellyfin_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_jellyfin_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_jellyfin_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute transmission-cli

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Create user jellyfin with UID 80 - to support r/w on NFS-mounted ScienceData partition.
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid 80 --home /home/jellyfin --disabled-password --gecos '' jellyfin && \
    mkdir /home/jellyfin/media && \
    chown -R jellyfin:jellyfin /home/jellyfin

#RUN echo "jellyfin:secret" | chpasswd
RUN echo "jellyfin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jellyfin && chmod 0440 /etc/sudoers.d/jellyfin

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir /home/jellyfin/.ssh && touch /home/jellyfin/.ssh/authorized_keys && \
  chown -R jellyfin:jellyfin /home/jellyfin/.ssh && chmod -R go-rw /home/jellyfin/.ssh

ADD jellyfin.sources /etc/apt/sources.list.d/jellyfin.sources

RUN curl https://repo.jellyfin.org/jellyfin_team.gpg.key | \
    gpg --dearmor --yes --output /etc/apt/keyrings/jellyfin.gpg && \
    chmod 644 /etc/apt/keyrings/jellyfin.gpg

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y jellyfin

RUN chown -R jellyfin:adm /etc/jellyfin /usr/share/jellyfin
RUN ln -s /usr/share/jellyfin/web /usr/lib/jellyfin/bin/jellyfin-web

RUN apt -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 22
EXPOSE 8096

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]
