#!/bin/bash
# Run by start.sh at each start: a book folder that is EMPTY gets a small starter
# book (starter/: _config.yml, _toc.yml, intro.md, notebook.ipynb), so someone who
# just wants to start writing has a book online a minute later. Written into the
# owner's files over WebDAV - the mount at /book is read-only - through the pod
# network's address login (no credentials in the pod). A folder with anything in
# it is never touched, nor the root of the owner's files; If-None-Match keeps an
# existing file from being overwritten even in a race.

. /etc/sciencedata_book.env
STARTER=/usr/local/share/sciencedata/starter
[[ -n "$HOME_SERVER" ]] || exit 0
[[ -z "$(ls -A /book 2>/dev/null)" ]] || exit 0
# the mounted folder, relative to the owner's files: /tank/data/<dir>/<owner>/files/<path>
rel=$(echo "$NFS_VOLUME_PATH" | sed -nE 's#^/tank/data/[^/]+/[^/]+/files/(.*)$#\1#p' | sed 's#/*$##')
[[ -n "$rel" ]] || exit 0
enc() { /opt/jupyterbook/bin/python -c 'import sys, urllib.parse; print("/".join(urllib.parse.quote(p) for p in sys.argv[1].split("/")))' "$1"; }
base="${HOME_SERVER_PROTOCOL:-https}://sciencedata/files/$(enc "$rel")"
for f in "$STARTER"/*; do
	code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' -H 'If-None-Match: *' -T "$f" "$base/$(enc "$(basename "$f")")")
	echo "starter book: $(basename "$f") -> HTTP $code"
done
