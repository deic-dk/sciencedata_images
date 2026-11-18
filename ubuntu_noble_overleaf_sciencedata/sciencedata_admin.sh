#!/bin/bash
# Runs as /etc/my_init.d/950_sciencedata_admin.sh - after Overleaf's migrations.
# A new instance gets an admin account for the pod's owner (SD_UID, their
# ScienceData user ID - an e-mail address for institution and invited
# accounts). Overleaf answers with a link to set the password; it is written to
# the pod log and kept in the instance's state. With ScienceData login
# (OpenID Connect) the owner can log in that way instead.
#
# The Containers page links to the pod's address plus /tmp/URI (a relative
# path) and shows "Starting..." until then (catalog/wait-for-token). Once
# Overleaf's web service answers - it starts after these scripts - a background
# waiter writes the path: "set your password" on a new instance (valid once),
# the login page otherwise; after 30 minutes without an answer, the login page.

STATE=/var/lib/overleaf/data/sciencedata
path=login

if [[ ! -e "$STATE/admin_created" ]]; then
	if [[ "$SD_UID" == *@* ]]; then
		out=$(cd /overleaf/services/web && /sbin/setuser www-data node modules/server-ce-scripts/scripts/create-user.mjs --admin --email="$SD_UID" 2>&1)
		echo "$out"
		if echo "$out" | grep -q "Successfully created"; then
			# the link is the indented line after "Please visit the following URL";
			# the output before it also holds the welcome e-mail's HTML, full of URLs
			link=$(echo "$out" | grep -E '^[[:space:]]+https?://[^[:space:]]+[[:space:]]*$' | tail -1 | tr -d '[:space:]')
			echo "$link" > "$STATE/admin_password_link.txt"
			date > "$STATE/admin_created"
			path="${link#*://*/}"
		fi
	else
		echo "No e-mail-like SD_UID: no admin account created"
	fi
fi

setsid sh -c 'for i in $(seq 1 360); do
	curl -fs -o /dev/null --max-time 5 http://127.0.0.1/login && break
	sleep 5
done
echo "$1" > /tmp/URI' sh "$path" </dev/null >/dev/null 2>&1 &
exit 0
