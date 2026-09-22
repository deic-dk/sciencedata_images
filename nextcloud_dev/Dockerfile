# Build command: docker build -t sciencedata/nextcloud_dev .
# Push command: docker push sciencedata/nextcloud_dev
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key sciencedata/nextcloud_dev
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" sciencedata/nextcloud_dev

FROM sciencedata/ubuntu_noble_caddy_sciencedata
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Nextcloud on Ubuntu noble for deployment on sciencedata.dk"

RUN apt update && apt install -y rsync file sqlite3 php-gmp php-bcmath

  # mailhotel.i2.dk (legacy Qmail/EL7) offers weak DH params that OpenSSL 3 rejects
  # at the default SECLEVEL=2, so PHP's SMTP STARTTLS fails silently. Drop to SECLEVEL=1.
  # TODO: remove once the relay is replaced.
  RUN grep -q system_default_sect /etc/ssl/openssl.cnf || { \
    sed -i '/^providers = provider_sect/a ssl_conf = ssl_sect' /etc/ssl/openssl.cnf && \
    printf '\n[ssl_sect]\nsystem_default = system_default_sect\n\n[system_default_sect]\nCipherString = DEFAULT@SECLEVEL=1\n' >> /etc/ssl/openssl.cnf \
  ; }

#RUN curl -L -o /tmp/nextcloud.tar.gz https://silo2.sciencedata.dk/public/kubefiles_public/nextcloud-33.0.2.tar.gz

#RUN sed -i 's|root \* /var/www|root * /var/www/nextcloud|' /etc/caddy/Caddyfile

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh
