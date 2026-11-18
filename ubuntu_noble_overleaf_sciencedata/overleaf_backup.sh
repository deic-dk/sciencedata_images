#!/bin/bash
# Back Overleaf up to the owner's ScienceData folder Containers:
# overleaf_backup-<pod>.tar = MongoDB dump + project history (the projects'
# files) + templates + this instance's secrets. Run nightly by cron and at
# shutdown (after Overleaf's pre-shutdown flushes). The address comes from
# /etc/overleaf_backup.env, written by sciencedata_init.sh.

. /etc/overleaf_backup.env || exit 1
[[ -n "$BACKUP_URL" ]] || { echo "overleaf_backup: no BACKUP_URL"; exit 1; }
[[ -e /run/overleaf_restored ]] || { echo "overleaf_backup: no restore at start - not uploading (it would replace the backup)"; exit 0; }

work=/var/tmp/overleaf_backup
rm -rf $work && mkdir -p $work
mongodump --quiet --db sharelatex --gzip --archive=$work/mongo.archive.gz || { echo "overleaf_backup: mongodump failed"; exit 1; }
tar -cf $work/backup.tar -C $work mongo.archive.gz \
	-C /var/lib/overleaf/data history template_files sciencedata 2>/dev/null \
	|| { echo "overleaf_backup: tar failed"; exit 1; }

curl --insecure --silent --max-time 30 -o /dev/null -X MKCOL ${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/Containers/
if curl --insecure --silent --fail --max-time 7200 --upload $work/backup.tar "$BACKUP_URL"; then
	echo "overleaf_backup: $(du -h $work/backup.tar | cut -f1) uploaded to $BACKUP_URL"
else
	echo "overleaf_backup: upload to $BACKUP_URL failed"
fi
rm -rf $work
