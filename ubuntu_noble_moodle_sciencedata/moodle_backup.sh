#!/bin/bash

# Dump Moodle's database and upload it to the folder Containers in the owner's
# ScienceData home folder. Run by start.sh at shutdown and nightly by cron.
# The addresses come from /etc/moodle_backup.env, written by start.sh.

. /etc/moodle_backup.env || exit 1
[[ -n "$BACKUP_URL" ]] || { echo "moodle_backup: no BACKUP_URL"; exit 1; }

dump=/var/cache/moodle/moodle_db.sql.gz
sudo -u www pg_dump --clean --if-exists --no-owner moodle | gzip > $dump.part || { echo "moodle_backup: pg_dump failed"; exit 1; }
mv -f $dump.part $dump

curl --insecure --silent --max-time 30 -o /dev/null -X MKCOL ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/
curl --insecure --silent --fail --max-time 3600 --upload $dump "$BACKUP_URL" || { echo "moodle_backup: upload to $BACKUP_URL failed"; exit 1; }
echo "moodle_backup: database uploaded to $BACKUP_URL"
