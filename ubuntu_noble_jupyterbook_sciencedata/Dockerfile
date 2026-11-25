# Build command: docker build -t sciencedata/ubuntu_noble_jupyterbook_sciencedata .
# Push command: docker push sciencedata/ubuntu_noble_jupyterbook_sciencedata
# Run command: docker run -p 8080:80 -v /path/to/book:/book:ro sciencedata/ubuntu_noble_jupyterbook_sciencedata

# A Jupyter Book, built and published from a ScienceData folder: the book's
# sources (Markdown, notebooks, _config.yml, _toc.yml) are mounted read-only at
# /book; whenever they change the book is built again and served by Caddy. On
# pages made from notebooks, a "Run on ScienceData" button opens the notebook
# in the reader's own notebook server on ScienceData.
FROM sciencedata/ubuntu_noble_caddy_sciencedata
MAINTAINER Frederik Orellana "https://github.com/deltafunction"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="Jupyter Book built and published from a ScienceData folder"

# Jupyter Book 1 (Sphinx; what DTU's course books use) in its own environment,
# with a Python kernel and the common scientific packages, so that books whose
# notebooks are executed at build time build out of the box
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y python3-venv python3-dev rsync && \
    python3 -m venv /opt/jupyterbook && \
    /opt/jupyterbook/bin/pip install --no-cache-dir "jupyter-book>=1,<2" ipykernel numpy scipy pandas matplotlib sympy && \
    /opt/jupyterbook/bin/python -m ipykernel install --prefix /opt/jupyterbook --name python3 && \
    apt-get -y autoremove && apt-get -y clean && rm -rf /var/lib/apt/lists/*

ADD Caddyfile /etc/caddy/Caddyfile
ADD sciencedata_book.sh /usr/local/sbin/sciencedata_book.sh
ADD sciencedata_book_run.php /usr/local/sbin/sciencedata_book_run.php
ADD run.js /usr/local/share/sciencedata/run.js
ADD sciencedata_book_starter.sh /usr/local/sbin/sciencedata_book_starter.sh
ADD starter /usr/local/share/sciencedata/starter
ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh /usr/local/sbin/sciencedata_book.sh /usr/local/sbin/sciencedata_book_starter.sh && \
    mkdir -p /var/lib/book/site /var/lib/book/meta && chown -R www:www /var/lib/book

EXPOSE 22
EXPOSE 80

CMD ["/usr/local/sbin/start.sh"]
