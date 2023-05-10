# Build command: docker build -t kube.sciencedata.dk:5000/ubuntu_jammy_caddy_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_focal_caddy_sciencedata

FROM ubuntu:22.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu Jammy for deployment on sciencedata.dk"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y ca-certificates

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    bind9-dnsutils \
    bind9-host \
    dkms \
    cron \
    curl \
    debian-keyring \
    debian-archive-keyring \
    git \
    gpg \
    golang \
    inetutils-tools \
    iputils-ping \
    jq \
    man-db \
    net-tools \
    nfs-common \
    openssh-client \
    openssh-server \
    pciutils \
    php-cli \
    php-fpm \
    php-yaml \
    psmisc \
    traceroute \
    unicode-data \
    vim \
    vlan \
    wget

# Add cyberduck, get key manually due to apt-key deprecation
RUN echo "deb [signed-by=/usr/local/share/keyrings/cyberduck.gpg] https://s3.amazonaws.com/repo.deb.cyberduck.io stable main" | tee -a /etc/apt/sources.list.d/cyberduck.list \
    && mkdir -p /usr/local/share/keyrings \
    && gpg --keyserver keyserver.ubuntu.com --recv-keys FE7097963FEFBE72 \
    && gpg --export FE7097963FEFBE72 > /usr/local/share/keyrings/cyberduck.gpg \
    && rm -rf /root/.gnupg \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y duck

# Add caddy
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && \
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list && \
    DEBIAN_FRONTEND=noninteractive apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y caddy

# "unminimize" script provided by ubuntu:22.04 container restores expected shell features like installing
# man pages. The script itself is interactive, so this a modified version that runs without interaction
RUN sed -i 's/^read.*//g' /usr/local/sbin/unminimize \
    && sed -i 's/exit 1/echo "skip"/g' /usr/local/sbin/unminimize \
    && sed -i 's/apt-get upgrade/apt-get upgrade -y/g' /usr/local/sbin/unminimize \
    && /usr/local/sbin/unminimize

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8


# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc \
    && echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc \
    && mkdir /root/.ssh \
    && touch /root/.ssh/authorized_keys \
    && chmod -R go-rw /root/.ssh \
    && mkdir /run/sshd \
    && sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -ri 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config

#RUN apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure caddy
ADD Caddyfile /root/Caddyfile
ADD index.php /root/index.php
ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh \
    && chmod go+rx /root/

EXPOSE 22
EXPOSE 80
# Caddy runs admin endpoint on port 2019
#EXPOSE 2019

CMD ["/usr/local/sbin/start.sh"]
