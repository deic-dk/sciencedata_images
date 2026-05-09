#!/bin/bash

set -e

# immich-machine-learning
cd /var/lib/immich/app
python3 -m venv /var/lib/immich/app/machine-learning/venv
(
  # Initiate subshell to setup venv
  . /var/lib/immich/app/machine-learning/venv/bin/activate
  pip3 install uv pydantic-settings
  rustup default stable
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

ln -s $IMMICH_PATH/home/media/upload $APP/
ln -s $IMMICH_PATH/home/media/upload $APP/machine-learning/

# Install sharp
cd $APP
pnpm --dangerously-allow-all-builds install sharp

