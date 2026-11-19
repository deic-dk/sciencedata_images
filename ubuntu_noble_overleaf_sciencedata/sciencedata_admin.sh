#!/bin/bash
# Runs as /etc/my_init.d/950_sciencedata_admin.sh - after Overleaf's migrations.
# A new instance started just for the owner gets an admin account for them (SD_UID, their
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

# A pod started for a group logs everyone in with ScienceData (EXTERNAL_AUTH,
# set by the init script), the owner becoming administrator by their user ID:
# no local account, which - with an e-mail that differs from the ID, as at most
# universities - would be a second account of the owner.
if [[ "$(cat /etc/container_environment/EXTERNAL_AUTH 2>/dev/null)" == *oidc* ]]; then
	echo "ScienceData login: no local administrator account"
	# ScienceData logins are matched to accounts by ID only (oidc_patch.sh). An
	# account the owner already has (e.g. restored from a personal pod: e-mail
	# = SD_UID) gets the owner's ID recorded, so their login lands in it.
	if [[ -n "$SD_UID" ]]; then
		cat > /tmp/sd_owner_link.js <<'JS'
const uid = process.env.SD_UID
// First: no other ScienceData ID on the owner's account - one linked by
// e-mail before (the unpatched module) would let that other user in.
const c = db.users.updateOne({ email: uid },
	{ $pull: { thirdPartyIdentifiers: { providerId: 'oidc', externalUserId: { $ne: uid } } } })
if (c.modifiedCount) print("ScienceData login: removed other users' logins from the owner's account")
// Then: the owner's own ID, if not there yet.
const r = db.users.updateOne(
	{ email: uid, thirdPartyIdentifiers: { $not: { $elemMatch: { providerId: 'oidc', externalUserId: uid } } } },
	{ $push: { thirdPartyIdentifiers: { externalUserId: uid, externalData: null, providerId: 'oidc' } } })
if (r.modifiedCount) print("ScienceData login: linked the owner's existing account to " + uid)
JS
		mongosh --quiet sharelatex --file /tmp/sd_owner_link.js || true
		rm -f /tmp/sd_owner_link.js
	fi
elif [[ ! -e "$STATE/admin_created" ]]; then
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
