# Build command: docker build -t sciencedata/ubuntu_noble_immich_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_immich_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/ubuntu_noble_immich_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/ubuntu_noble_immich_sciencedata
#
# Two stages: "build" compiles immich (node toolchain, pnpm, extism-js, rust for the
# python wheels) and is thrown away; "runtime" gets only what start.sh needs and a
# single, already-owned copy of the built app. Nothing built, cached or cloned ends
# up in a layer of the final image.
#
# Immich - we're following https://github.com/arter97/immich-native/tree/master

ARG REV=v2.7.5
ARG IMMICH_PATH=/var/lib/immich

###########################################################
# Stage 1: build immich
###########################################################
FROM ubuntu:24.04 AS build
ARG REV
ARG IMMICH_PATH
ENV REV=$REV
ENV IMMICH_PATH=$IMMICH_PATH
ENV APP=$IMMICH_PATH/app
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
        ca-certificates curl wget gnupg git unzip jq \
        build-essential autoconf pkg-config \
        python3 python3-venv python3-dev python3-pip \
        rustup libclang-dev \
        perl libnet-ssleay-perl libio-socket-ssl-perl libcapture-tiny-perl libfile-which-perl \
        libfile-chdir-perl libpkgconfig-perl libffi-checklib-perl libtest-warnings-perl \
        libtest-fatal-perl libtest-needs-perl libtest2-suite-perl libsort-versions-perl \
        libpath-tiny-perl libtry-tiny-perl libterm-table-perl libany-uri-escape-perl \
        libmojolicious-perl libfile-slurper-perl liblcms2-2 libgl1 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt install -y nodejs

# extism/js-pdk (extism-js) for the plugins build
RUN mkdir -p /root/.local/bin && cd /root && curl -O https://raw.githubusercontent.com/extism/js-pdk/main/install.sh \
    && sed -i -e 's@sudo@@g' -e "s@/usr/local/binaryen@$HOME/binaryen@g" -e "s@/usr/local/bin@$HOME/.local/bin@g" install.sh \
    && bash install.sh
ENV PATH=$PATH:/root/.local/bin

WORKDIR $IMMICH_PATH/home
RUN git clone https://github.com/immich-app/immich --depth=1 -b $REV && cd immich && git reset --hard $REV \
    && grep -Rl /usr/src . | xargs -n1 sed -i -e "s@/usr/src@$IMMICH_PATH@g" \
    && grep -RlE "\"/build\"|'/build'" . | xargs -n1 sed -i -e "s@\"/build\"@\"$APP\"@g" -e "s@'/build'@'$APP'@g" \
    && mkdir -p $IMMICH_PATH/cache $APP $IMMICH_PATH/home/media $APP/machine-learning

RUN corepack enable pnpm && corepack use pnpm@latest \
    && cd immich/server && COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm install --frozen-lockfile --force && pnpm run build \
    && pnpm prune --prod --no-optional --config.ci=true
RUN cd immich/open-api/typescript-sdk && pnpm install --frozen-lockfile --force && pnpm run build
RUN cd immich/web && NODE_OPTIONS="--max-old-space-size=4096" pnpm install --frozen-lockfile --force && pnpm run build
RUN cd immich/plugins && pnpm install --frozen-lockfile --force && pnpm run build

# Assemble $APP. sharp is installed in the same step that creates $APP/node_modules:
# pnpm replaces entries in node_modules by renaming directories, and overlayfs refuses
# to rename a directory that lives in a lower layer ("Invalid cross-device link").
RUN cd immich && cp -aL server/node_modules server/dist server/bin $APP/ && cp -a web/build $APP/www \
    && cp -a server/src server/package.json pnpm-lock.yaml $APP/ && cp -a LICENSE $APP/ && cp -a i18n $APP/../ \
    && mkdir -p $APP/corePlugin && cp -a plugins/dist $APP/corePlugin/ && cp -a plugins/manifest.json $APP/corePlugin/ \
    && cd $APP && pnpm --dangerously-allow-all-builds install sharp && pnpm store prune

# machine-learning venv (uv sync, CPU extra) and the GeoNames data, into $APP
ADD install.sh /usr/local/bin/install.sh
RUN chmod +x /usr/local/bin/install.sh && export APP IMMICH_PATH && /usr/local/bin/install.sh

###########################################################
# Stage 2: the image that runs
###########################################################
FROM ubuntu:24.04
ARG REV
ARG IMMICH_PATH
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Ubuntu noble for deployment on sciencedata.dk"

ENV REV=$REV
ENV IMMICH_PATH=$IMMICH_PATH
ENV APP=$IMMICH_PATH/app

RUN DEBIAN_FRONTEND=noninteractive apt update &&  apt install -y openssh-client net-tools inetutils-tools curl \
bind9-dnsutils bind9-host psmisc vim pciutils dkms vlan unicode-data gnupg git golang duck cron \
apt-transport-https wget jq nfs-common dropbear openssh-sftp-server gpg gpgv1 ca-certificates \
iputils-ping traceroute transmission-cli libgl1 \
    && apt-get -y clean && rm -rf /var/lib/apt/lists/*

# Configure locale
RUN DEBIAN_FRONTEND=noninteractive apt update && apt install -y locales \
    && locale-gen --purge en_US.UTF-8 en_DK.UTF-8 da_DK.UTF-8 \
    && apt-get -y clean && rm -rf /var/lib/apt/lists/*

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

# Runtime dependencies: node, redis (Ubuntu's, as before), postgres 17 + pgvector +
# VectorChord, jellyfin's ffmpeg, python for the machine-learning venv (same python as the build stage, so the
# copied venv's interpreter links resolve), gunicorn which start.sh runs from the system.
ADD jellyfin.sources /etc/apt/sources.list.d/jellyfin.sources
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && curl https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor --yes --output /etc/apt/keyrings/jellyfin.gpg && chmod 644 /etc/apt/keyrings/jellyfin.gpg \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && DEBIAN_FRONTEND=noninteractive apt update && apt install -y \
        nodejs redis postgresql-17 postgresql-17-pgvector jellyfin-ffmpeg7 \
        python3 python3-venv gunicorn python3-pydantic uuid-runtime liblcms2-2 \
    && curl -LO https://github.com/tensorchord/VectorChord/releases/download/0.5.3/postgresql-17-vchord_0.5.3-1_amd64.deb \
    && dpkg -i postgresql-17-vchord_0.5.3-1_amd64.deb && rm postgresql-17-vchord_0.5.3-1_amd64.deb \
    && apt-get -y clean && rm -rf /var/lib/apt/lists/*

ADD immich.sql $IMMICH_PATH/immich.sql
RUN /etc/init.d/postgresql start && sudo -u postgres psql postgres -c 'ALTER SYSTEM SET shared_preload_libraries = "vchord"' && /etc/init.d/postgresql restart &&  sudo -u postgres psql < $IMMICH_PATH/immich.sql

# The built app, its machine-learning venv, geodata and the translations - one copy,
# owned by immich from the start (no separate chown layer).
COPY --from=build --chown=immich:immich $IMMICH_PATH/app $IMMICH_PATH/app
COPY --from=build --chown=immich:immich $IMMICH_PATH/i18n $IMMICH_PATH/i18n
RUN mkdir -p $IMMICH_PATH/cache $IMMICH_PATH/home/media && chown immich:immich $IMMICH_PATH $IMMICH_PATH/cache $IMMICH_PATH/home/media

EXPOSE 22
EXPOSE 8096

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]

WORKDIR $IMMICH_PATH/home
USER immich
