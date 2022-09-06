# Build command: docker build -t kube.sciencedata.dk:5000/ubuntu_jammy_sciencedata .
# Run command: docker run -p 8080:80 -p 4022:22 [-e ROOT_PASSWORD=my_root_password] -e SSH_PUBLIC_KEY=my_public_key kube.sciencedata.dk:5000/ubuntu_jammy_sciencedata

FROM ubuntu:22.04
MAINTAINER Joshua Clement "https://github.com/joshuadclement"

LABEL vendor="sciencedata.dk"
LABEL version="1.0"
LABEL description="image for testing kubernetes backend"

ADD start.sh /usr/local/sbin/start.sh
RUN chmod +x /usr/local/sbin/start.sh

CMD ["/usr/local/sbin/start.sh"]
