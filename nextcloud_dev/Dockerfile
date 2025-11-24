# Build command: docker build -t sciencedata/nextcloud_dev .
# Push command: docker push sciencedata/nextcloud_dev
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/nextcloud_dev
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/nextcloud_dev

FROM sciencedata/ubuntu_noble_caddy_sciencedata
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Nextcloud on Ubuntu noble for deployment on sciencedata.dk"

RUN curl -L -o /tmp/nextcloud.tar.gz https://silo2.sciencedata.dk/public/kubefiles_public/nextcloud.tar.gz

RUN sed -i 's|root \* /var/www|root * /var/www/nextcloud/nextcloud|' /etc/caddy/Caddyfile

RUN touch /var/log/nextcloud.log && chown www:www /var/log/nextcloud.log

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh
