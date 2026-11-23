#!/bin/bash
# Runs as www for the life of the container (started by start.sh): builds the
# Jupyter Book whose sources are mounted at /book, and builds it again whenever
# they change. Only a successful build replaces what is served, so a broken
# edit never takes the book down; the build's output is at /_sciencedata/build.log.
#
# Changes are noticed by polling (file times and sizes; NFS gives no change
# events), every 20 seconds, with a short wait for a burst of saves to settle.

SRC=/book
WORK=/var/lib/book/work
SITE=/var/lib/book/site
META=/var/lib/book/meta
JB=/opt/jupyterbook/bin/jupyter-book
LOG=$META/build.log
cp /usr/local/share/sciencedata/run.js "$META/run.js"

fingerprint() {
	find "$SRC" \( -name _build -o -name '.*' \) -prune -o -type f -printf '%T@ %s %p\n' 2>/dev/null | sort | md5sum
}

placeholder() { # $1: the message
	cat > "$SITE/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Jupyter Book</title><style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:4rem auto;padding:0 1rem;line-height:1.5}</style></head>
<body><h1>Jupyter Book</h1><p>$1</p><p><a href="/_sciencedata/build.log">The build log</a></p></body></html>
HTML
}

build() {
	if [[ ! -f "$SRC/_toc.yml" ]]; then
		echo "$(date -Is) no _toc.yml in the folder - nothing to build" > "$LOG"
		[[ -f "$SITE/.built" ]] || placeholder "The folder holds no book yet: a Jupyter Book needs a <code>_toc.yml</code> (and usually a <code>_config.yml</code>) next to its pages."
		return
	fi
	[[ -f "$SITE/.built" ]] || placeholder "The book is being built - reload this page in a minute."
	echo "$(date -Is) building" > "$LOG"
	mkdir -p "$WORK"
	# outside the (read-only) sources; the execution cache stays in $WORK between builds
	if nice -n 10 "$JB" build "$SRC" --path-output "$WORK" >> "$LOG" 2>&1 && [[ -f "$WORK/_build/html/index.html" ]]; then
		rsync -a --delete --exclude .built "$WORK/_build/html/" "$SITE/"
		touch "$SITE/.built"
		php /usr/local/sbin/sciencedata_book_run.php "$SITE" "$META" >> "$LOG" 2>&1
		echo "$(date -Is) built" >> "$LOG"
	else
		echo "$(date -Is) the build FAILED - the previous version of the book stays online" >> "$LOG"
	fi
}

last=""
while true; do
	fp=$(fingerprint)
	if [[ "$fp" != "$last" ]]; then
		sleep 5 # let a burst of saves settle
		fp=$(fingerprint)
		build
		last=$fp
	fi
	sleep 20
done
