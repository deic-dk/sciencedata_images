# Build command: docker build -t sciencedata/ubuntu_noble_lyrion_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_lyrion_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_lyrion_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_lyrion_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble with the Lyrion music server for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common caddy dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute libcrypt-openssl-rsa-perl

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Create user lyrion with UID 80 - to support r/w on NFS-mounted ScienceData partition.
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid 80 --home /home/lyrion --disabled-password --gecos '' lyrion && \
    mkdir /home/lyrion/music && \
    chown -R lyrion /home/lyrion

#RUN echo "lyrion:secret" | chpasswd
RUN echo "lyrion ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/lyrion && chmod 0440 /etc/sudoers.d/lyrion

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir /home/lyrion/.ssh && touch /home/lyrion/.ssh/authorized_keys && \
  chown -R lyrion:lyrion /home/lyrion/.ssh && chmod -R go-rw /home/lyrion/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add lyrion

RUN curl -LO https://downloads.lms-community.org/LyrionMusicServer_v9.0.3/lyrionmusicserver_9.0.3_amd64.deb
RUN dpkg -i lyrionmusicserver_9.0.3_amd64.deb
ADD RadioNowPlaying.svg /usr/share/squeezeboxserver/HTML/EN/html/images/RadioNowPlaying.svg
RUN sed -i 's|http://dabdig.co.uk/slimserver-rep/images/RadioNowPlaying.svg|/html/images/RadioNowPlaying.svg|' /usr/share/squeezeboxserver/HTML/EN/settings/wizard.json

RUN chgrp audio /home/lyrion && chmod g+rwx /home/lyrion

EXPOSE 22
EXPOSE 9000

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]
