#!/bin/bash

set -e

# immich-machine-learning
cd /var/lib/immich/app
python3 -m venv /var/lib/immich/app/machine-learning/venv
(
  # Initiate subshell to setup venv
  . /var/lib/immich/app/machine-learning/venv/bin/activate
  pip3 install uv pydantic-settings
  cd /var/lib/immich/home/immich/machine-learning
  uv sync --no-install-project --no-install-workspace --extra cpu --no-cache --active --link-mode=copy
)
cp -a /var/lib/immich/home/immich/machine-learning/immich_ml /var/lib/immich/app/machine-learning/

# Install GeoNames
mkdir -p $APP/geodata
cd $APP/geodata
wget -o - https://download.geonames.org/export/dump/admin1CodesASCII.txt
wget -o - https://download.geonames.org/export/dump/admin2Codes.txt
wget -o - https://download.geonames.org/export/dump/cities500.zip
wget -o - https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson
wait
unzip cities500.zip
date --iso-8601=seconds | tr -d "\n" > geodata-date.txt
rm cities500.zip

# Install sharp
cd $APP
pnpm install sharp

# Set up upload directory
mkdir -p $IMMICH_PATH/upload
ln -s $IMMICH_PATH/upload $APP/
ln -s $IMMICH_PATH/upload $APP/machine-learning/

mkdir $APP/upload/encoded-video/
mkdir $APP/upload/library/
mkdir $APP/upload/upload
mkdir $APP/upload/profile/
mkdir $APP/upload/thumbs/
mkdir $APP/upload/backups/
touch $APP/upload/encoded-video/.immich
touch $APP/upload/library/.immich
touch $APP/upload/upload/.immich
touch $APP/upload/profile/.immich
touch $APP/upload/thumbs/.immich
touch $APP/upload/backups/.immich

chown -R immich:immich $IMMICH_PATH

