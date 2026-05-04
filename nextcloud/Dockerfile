# Build command: docker build -t sciencedata/nextcloud .
# Push command: docker push sciencedata/nextcloud
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/nextcloud
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/nextcloud

FROM sciencedata/ubuntu_noble_caddy_sciencedata
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Nextcloud on Ubuntu noble for deployment on sciencedata.dk"

ENV NC_VERSION=33.0.2

RUN curl -L -o /tmp/nc.tar.gz https://silo2.sciencedata.dk/public/kubefiles_public/nextcloud/nextcloud-$NC_VERSION.tar.gz
RUN mkdir -p /var/www/data /var/db && cd /var/www && tar -xzf /tmp/nc.tar.gz && mkdir /var/www/nextcloud/data && chown -R www:www /var/www /var/db
RUN rm /tmp/nc.tar.gz
RUN curl -L -o /var/www/nextcloud/config/config.php https://silo2.sciencedata.dk/public/kubefiles_public/nextcloud/nextcloud-config.php
RUN oc_version=`grep 'OC_Version ' /var/www/nextcloud/version.php | sed -E 's|.* array\((.*)\);|\1|' | sed 's|,|.|g'` && sed -i "s|OC_VERSION|$oc_version|" /var/www/nextcloud/config/config.php

RUN sed -i 's|root \* /var/www|root * /var/www/nextcloud|' /etc/caddy/Caddyfile
RUN sed -i "s|\$connectionParams\['path'\] = .*|\$connectionParams['path'] = '/var/db/owncloud.db';|" /var/www/nextcloud/lib/private/DB/ConnectionFactory.php

RUN touch /var/log/nextcloud.log && chown -R www:www /var/log/nextcloud.log /var/www/nextcloud/config/config.php /var/www/nextcloud/core/skeleton/

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh
