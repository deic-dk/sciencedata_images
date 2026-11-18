# Build command: docker build -t sciencedata/ubuntu_noble_moodle_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_moodle_sciencedata
# Run command: docker run -p 8080:80 -p 4022:22 -e SSH_PUBLIC_KEY="`cat ~/.ssh/id_rsa.pub`" -e HTTPS_PORT=8080 sciencedata/ubuntu_noble_moodle_sciencedata

FROM sciencedata/ubuntu_noble_caddy_sciencedata
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Moodle on Ubuntu noble for deployment on sciencedata.dk"

# Moodle 5.3 is the long-term support release (October 2026). It needs PHP >= 8.3
# (noble has 8.3) and PostgreSQL >= 17 (noble has 16: take it from postgresql.org).
ENV MOODLE_BRANCH=MOODLE_503_STABLE

RUN echo "deb http://apt.postgresql.org/pub/repos/apt noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

RUN DEBIAN_FRONTEND=noninteractive apt update && apt install -y postgresql-17 \
    php-pgsql php-intl php-soap php-bcmath php-opcache php-readline sudo && \
    apt-get -y autoremove && apt-get -y clean && rm -rf /var/lib/apt/lists/*

# Moodle's requirements and sensible limits for course uploads
RUN for ini in /etc/php/*/fpm/php.ini /etc/php/*/cli/php.ini; do \
      sed -i -E 's|^;?max_input_vars = .*|max_input_vars = 5000|' $ini; \
    done

# The code, from git so that an update is a 'git pull' (and a rebuild picks up fixes)
RUN git clone --depth 1 -b $MOODLE_BRANCH https://github.com/moodle/moodle.git /var/www/moodle && \
    chown -R www:www /var/www/moodle

# Local, volatile caches - the data root (on ScienceData) only holds what must persist
RUN mkdir -p /var/cache/moodle/local /var/cache/moodle/temp /var/cache/moodle/cache && \
    chown -R www:www /var/cache/moodle

ADD Caddyfile /etc/caddy/Caddyfile
ADD config.php /var/www/moodle/config.php
RUN chown www:www /var/www/moodle/config.php

# Install Moodle into the image, so that a new pod is ready in seconds. The database
# lives in the image's PostgreSQL; the files of a fresh site go to /var/moodledata-seed,
# which start.sh copies into an empty mounted folder. start.sh replaces the password
# and the site identifier set here.
RUN mkdir -p /var/moodledata-seed && chown www:www /var/moodledata-seed && \
    sed -i "s|'/var/moodledata'|'/var/moodledata-seed'|; s|'WWWROOT'|'http://localhost'|" /var/www/moodle/config.php && \
    service postgresql start && until pg_isready -q; do sleep 1; done && \
    sudo -u postgres createuser www && sudo -u postgres createdb -O www -E UTF8 moodle && \
    sudo -u www php /var/www/moodle/admin/cli/install_database.php --agree-license \
      --lang=en --adminuser=admin --adminpass='Preinstalled-1!' --adminemail=admin@localhost.localdomain \
      --fullname="Moodle on ScienceData" --shortname="Moodle" && \
    service postgresql stop && \
    sed -i "s|'/var/moodledata-seed'|'/var/moodledata'|" /var/www/moodle/config.php && \
    rm -rf /var/cache/moodle/local/* /var/cache/moodle/temp/* /var/cache/moodle/cache/*

ADD moodle_backup.sh /usr/local/sbin/moodle_backup.sh
ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh /usr/local/sbin/moodle_backup.sh

# Moodle's scheduled tasks, every minute
RUN echo "* * * * * www /usr/bin/php /var/www/moodle/admin/cli/cron.php >/dev/null 2>&1" > /etc/cron.d/moodle

EXPOSE 22
EXPOSE 80

CMD ["/usr/local/sbin/start.sh"]
