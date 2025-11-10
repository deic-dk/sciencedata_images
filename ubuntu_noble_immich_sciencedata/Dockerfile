# Build command: docker build -t sciencedata/ubuntu_noble_immich_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_immich_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_immich_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_immich_sciencedata

FROM ubuntu:24.04
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

ENV REV=v2.2.0
ENV IMMICH_PATH=/var/lib/immich
ENV APP=$IMMICH_PATH/app

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute transmission-cli libgl1

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8

# Create user immich with UID 80 - to support r/w on NFS-mounted ScienceData partition.
RUN sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    adduser --uid 80 --home $IMMICH_PATH/home --disabled-password --gecos '' immich && \
    chown -R immich:immich $IMMICH_PATH/home

#RUN echo "immich:secret" | chpasswd
RUN echo "immich ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/immich && chmod 0440 /etc/sudoers.d/immich

# Configure ssh access
RUN echo "alias ls='ls --color=auto'" >> .bashrc && \
  echo "PATH=${PATH}:/sbin/:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin" >> ~/.bashrc && \
  mkdir -p $IMMICH_PATH/home/.ssh && touch $IMMICH_PATH/home/.ssh/authorized_keys && \
  chown -R immich:immich $IMMICH_PATH/home/.ssh && chmod -R go-rw $IMMICH_PATH/home/.ssh

###########################################################
# Immich - we're following
# https://github.com/arter97/immich-native/tree/master
###########################################################

# Dependencies

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -

RUN curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg

ADD jellyfin.sources /etc/apt/sources.list.d/jellyfin.sources

RUN curl https://repo.jellyfin.org/jellyfin_team.gpg.key | \
    gpg --dearmor --yes --output /etc/apt/keyrings/jellyfin.gpg && \
    chmod 644 /etc/apt/keyrings/jellyfin.gpg

# Postgres 17
RUN sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y nodejs redis postgresql-17 postgresql-17-pgvector rustup libclang-dev postgresql-server-dev-17 jellyfin-ffmpeg7 python3-pip gunicorn python3-pydantic \
        python3-venv \
        python3-dev \
        uuid-runtime \
        autoconf \
        build-essential \
        unzip \
        jq \
        perl \
        libnet-ssleay-perl \
        libio-socket-ssl-perl \
        libcapture-tiny-perl \
        libfile-which-perl \
        libfile-chdir-perl \
        libpkgconfig-perl \
        libffi-checklib-perl \
        libtest-warnings-perl \
        libtest-fatal-perl \
        libtest-needs-perl \
        libtest2-suite-perl \
        libsort-versions-perl \
        libpath-tiny-perl \
        libtry-tiny-perl \
        libterm-table-perl \
        libany-uri-escape-perl \
        libmojolicious-perl \
        libfile-slurper-perl \
        liblcms2-2

#RUN rustup install nightly && rustup default nightly

# Postgres Vectorchord
#RUN curl -fsSL https://github.com/tensorchord/VectorChord/archive/refs/tags/0.5.3.tar.gz | tar -xz
# This is no longer necessary
#RUN cd VectorChord-* && find . -name Cargo.toml | while read name; do sed -i '1icargo-features = ["edition2024"]' "$name"; done
#RUN find . -name Cargo.toml | while read name; do sed -i 's|resolver = "3"|resolver = "2"|' "$name"; done
#RUN rm Cargo.lock
#RUN cd VectorChord-* && make build && make install

RUN curl -LO https://github.com/tensorchord/VectorChord/releases/download/0.5.3/postgresql-17-vchord_0.5.3-1_amd64.deb && dpkg -i postgresql-17-vchord_0.5.3-1_amd64.deb

ADD immich.sql $IMMICH_PATH/immich.sql

RUN /etc/init.d/postgresql start && sudo -u postgres psql postgres -c 'ALTER SYSTEM SET shared_preload_libraries = "vchord"' && /etc/init.d/postgresql restart &&  sudo -u postgres psql < $IMMICH_PATH/immich.sql

WORKDIR $IMMICH_PATH/home

RUN git clone https://github.com/immich-app/immich --depth=1 -b $REV && cd immich && git reset --hard $REV
RUN grep -Rl /usr/src | xargs -n1 sed -i -e "s@/usr/src@$IMMICH_PATH@g"
RUN grep -RlE "\"/build\"|'/build'" | xargs -n1 sed -i -e "s@\"/build\"@\"$APP\"@g" -e "s@'/build'@'$APP'@g"
RUN mkdir $IMMICH_PATH/cache $IMMICH_PATH/app $IMMICH_PATH/home/media $APP/machine-learning
RUN corepack enable pnpm && corepack use pnpm@latest && cd immich/server && COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm install --frozen-lockfile --force && pnpm run build && pnpm prune --prod --no-optional --config.ci=true
RUN cd immich/open-api/typescript-sdk && pnpm install --frozen-lockfile --force && pnpm run build
RUN cd immich/web && NODE_OPTIONS="--max-old-space-size=4096" pnpm install --frozen-lockfile --force && pnpm run build
RUN cd immich && cp -aL server/node_modules server/dist server/bin $APP/ && cp -a web/build $APP/www && cp -a server/resources server/package.json pnpm-lock.yaml $APP/ && cp -a LICENSE $APP/ && cp -a i18n $APP/../

RUN chown -R immich:immich $IMMICH_PATH

ADD install.sh /usr/local/bin/install.sh
RUN chmod +x /usr/local/bin/install.sh;

USER immich
RUN export APP IMMICH_PATH; /usr/local/bin/install.sh

# Clean up

RUN cd $APP && pnpm store prune

USER root

RUN apt -y autoremove && apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    $IMMICH_PATH/home/.pnpm \
    $IMMICH_PATH/home/.local/share/pnpm \
    $IMMICH_PATH/home/.cache

EXPOSE 22
EXPOSE 8096

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]

USER immich
