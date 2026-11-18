# Build command: docker build -t sciencedata/ubuntu_noble_overleaf_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_overleaf_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" -e HTTPS_PORT=8080 -e SD_UID=me@example.org sciencedata/ubuntu_noble_overleaf_sciencedata

# Overleaf Community Edition, extended (github.com/yu-i-i/overleaf-cep): adds
# OpenID Connect login, comments and track changes. Ubuntu 24.04 (phusion
# baseimage: my_init + runit), Node and a minimal TeX Live.
FROM overleafcep/sharelatex:6.3.0-ext-v5.1
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Overleaf (extended community edition) for deployment on sciencedata.dk"

# The full TeX Live, so that templates and papers compile without missing
# packages (a few GB). Build with --build-arg TEXLIVE_SCHEME=scheme-medium for a
# smaller image.
ARG TEXLIVE_SCHEME=scheme-full

# MongoDB and Redis in the pod: Overleaf 6 needs MongoDB >= 8.0 (as a replica
# set) and Redis >= 7.4 (Ubuntu 24.04 has 7.0, so from redis.io).
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y gnupg curl dropbear-bin cron && \
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.2 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.2.list && \
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb noble main" > /etc/apt/sources.list.d/redis.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org redis && \
    apt-get -y clean && rm -rf /var/lib/apt/lists/*

# texlive-scripts right after tlmgr itself: the new tlmgr runs fmtutil with
# several --by* options at once, which the image's older fmtutil rejects
# ("multiple commands found").
RUN tlmgr update --self && tlmgr update texlive-scripts && \
    tlmgr install $TEXLIVE_SCHEME && tlmgr path add

# Overleaf's settings: databases in the pod, behind kube's HTTPS proxy
ENV OVERLEAF_MONGO_URL=mongodb://127.0.0.1:27017/sharelatex
ENV OVERLEAF_REDIS_HOST=127.0.0.1
ENV REDIS_HOST=127.0.0.1
ENV OVERLEAF_SECURE_COOKIE=true
ENV OVERLEAF_APP_NAME=Overleaf
ENV OVERLEAF_NAV_TITLE=Overleaf
ENV ENABLED_LINKED_FILE_TYPES=project_file,project_output_file
ENV ENABLE_CONVERSIONS=true
ENV EMAIL_CONFIRMATION_DISABLED=true
ENV OVERLEAF_OIDC_PROVIDER_NAME=ScienceData
ENV OVERLEAF_OIDC_IDENTITY_SERVICE_NAME="Log in with ScienceData"
ENV OVERLEAF_OIDC_USER_ID_FIELD=username
ENV OVERLEAF_OIDC_UPDATE_USER_DETAILS_ON_LOGIN=true

# Before ALL of Overleaf's own start-up scripts (my_init runs them in name order;
# 000_check_missing_secrets.sh already needs OVERLEAF_INVITE_TOKEN_SECRET, and
# 500_check_db_access / 900_migrations need the databases): SSH, restore from
# the backup, MongoDB + Redis, secrets, address.
ADD sciencedata_init.sh /etc/my_init.d/000_000_sciencedata_init.sh
# After the migrations: on a new instance, an admin account for the owner.
ADD sciencedata_admin.sh /etc/my_init.d/950_sciencedata_admin.sh
# Backup to the owner's ScienceData folder Containers - nightly and at shutdown
# (after Overleaf's pre-shutdown flushes; MongoDB is still running then).
ADD overleaf_backup.sh /usr/local/sbin/overleaf_backup.sh
ADD sciencedata_post_shutdown.sh /etc/my_init.post_shutdown.d/10_sciencedata_backup
RUN chmod +x /etc/my_init.d/000_000_sciencedata_init.sh /etc/my_init.d/950_sciencedata_admin.sh \
      /usr/local/sbin/overleaf_backup.sh /etc/my_init.post_shutdown.d/10_sciencedata_backup && \
    echo "23 3 * * * root /usr/local/sbin/overleaf_backup.sh >> /var/log/overleaf_backup.log 2>&1" > /etc/cron.d/overleaf_backup && \
    chmod 644 /etc/cron.d/overleaf_backup

# SSH (key only) as a runit service
RUN mkdir -p /etc/service/dropbear /etc/dropbear /root/.ssh && chmod 700 /root/.ssh && \
    printf '#!/bin/sh\nexec /usr/sbin/dropbear -F -E -R -s -p 22 2>&1\n' > /etc/service/dropbear/run && \
    chmod +x /etc/service/dropbear/run

EXPOSE 22
EXPOSE 80
