# Build command: docker build -t sciencedata/ubuntu_noble_claude_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_claude_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_claude_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_claude_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common caddy dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute php-cli php-xml php-mbstring php-curl php-zip php-gd php-intl php-sqlite3 \
php-bcmath php-apcu

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Create user claude with UID 80 - to support r/w on NFS-mounted ScienceData partition.
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid 80 --home /home/claude --disabled-password --gecos '' claude

#RUN echo "claude:secret" | chpasswd
RUN echo "claude ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/claude && chmod 0440 /etc/sudoers.d/claude

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir /home/claude/.ssh && touch /home/claude/.ssh/authorized_keys && \
  chown -R claude:claude /home/claude/.ssh && chmod -R go-rw /home/claude/.ssh

RUN apt-get -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add Claude
USER claude
RUN curl -L -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash 

#export NVM_DIR="$HOME/.nvm"
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

RUN cat .bashrc
RUN bash -c ". $HOME/.nvm/nvm.sh && nvm install --lts"
RUN bash -c ". $HOME/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-code"

USER root
EXPOSE 22
EXPOSE 5000

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]
