#!/bin/bash
# Runs as /etc/my_init.d/000_000_sciencedata_init.sh - before all of Overleaf's
# own start-up scripts (000_check_missing_secrets.sh needs the secrets set here,
# 500_check_db_access.sh and 900_run_web_migrations.sh the databases). my_init
# imports /etc/container_environment after each script, so what is written there
# reaches the scripts and services that follow.
#
# Overleaf's data stays on the pod's local disk (its start-up chowns the data
# folders as root, which a root-squashed NFS mount refuses). Persistence is a
# backup in the owner's ScienceData folder Containers, as for the other images:
# overleaf_backup-<pod>.tar = MongoDB dump + project history (files) +
# templates + this instance's secrets. Restored here, written nightly and at
# shutdown (overleaf_backup.sh).

ENVDIR=/etc/container_environment
DATA=/var/lib/overleaf/data
STATE=$DATA/sciencedata
PROTO=${HOME_SERVER_PROTOCOL:-https}

# SSH access (key only)
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
	chmod 600 /root/.ssh/authorized_keys
fi

# ── Overleaf's processes may not reach private networks ──
# Everything Overleaf runs - compiles included, and a project's latexmkrc is
# Perl that a compile executes - runs as www-data. Inside a pod,
# https://sciencedata/files/ serves the pod OWNER's files without a password,
# and services on the cluster network trust it by address: in an instance
# shared with a group, a member's compile could otherwise read the owner's
# whole ScienceData. So www-data gets loopback (MongoDB, Redis, Overleaf's own
# services) and the public internet only - plus DNS to the pod's name server.
# root (the backups) is not restricted. No rule, no start.
wwwuid=$(id -u www-data)
ok=1
for ns in $(awk '/^nameserver/ {print $2}' /etc/resolv.conf | grep -v :); do
	iptables -A OUTPUT -m owner --uid-owner $wwwuid -d $ns -p udp --dport 53 -j ACCEPT || ok=""
	iptables -A OUTPUT -m owner --uid-owner $wwwuid -d $ns -p tcp --dport 53 -j ACCEPT || ok=""
done
# Only NEW connections are refused: Overleaf's nginx runs as www-data too, and
# its replies to kube's reverse proxy (a private address) must go out.
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10; do
	iptables -A OUTPUT -m owner --uid-owner $wwwuid -m conntrack --ctstate NEW -d $net -j REJECT || ok=""
done
for net in fc00::/7 fe80::/10; do
	ip6tables -A OUTPUT -m owner --uid-owner $wwwuid -m conntrack --ctstate NEW -d $net -j REJECT 2>/dev/null
done
if [[ -z "$ok" ]]; then
	echo "ERROR: could not restrict Overleaf's network access (iptables, NET_ADMIN) - refusing to start"
	exit 1
fi

# Resolve sciencedata to the address of the owner's home server
if [[ -n "$HOME_SERVER" ]]; then
	grep -q " sciencedata$\|	sciencedata$" /etc/hosts || echo "$HOME_SERVER	sciencedata" >> /etc/hosts
	echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
fi

# The backup's address; the pod name is stable for the same image and owner
DST_NAME=overleaf_backup-${HOSTNAME}.tar
BACKUP_URL=$PROTO://sciencedata/files/Containers/$DST_NAME
cat > /etc/overleaf_backup.env <<EOF
BACKUP_URL='$BACKUP_URL'
HOME_SERVER_PROTOCOL='$PROTO'
EOF

# ── MongoDB (single-node replica set, as Overleaf needs) and Redis ──
mkdir -p /var/lib/mongodb /var/log/mongodb
chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb 2>/dev/null
mongod --fork --replSet rs0 --bind_ip 127.0.0.1 --dbpath /var/lib/mongodb \
	--logpath /var/log/mongodb/mongod.log --wiredTigerCacheSizeGB 1
until mongosh --quiet --eval 'db.runCommand({ping: 1}).ok' >/dev/null 2>&1; do sleep 1; done
mongosh --quiet --eval 'try { rs.status().ok } catch (e) { rs.initiate({_id: "rs0", members: [{_id: 0, host: "127.0.0.1:27017"}]}).ok }'
until mongosh --quiet --eval 'db.hello().isWritablePrimary' 2>/dev/null | grep -q true; do sleep 1; done

redis-server --daemonize yes --bind 127.0.0.1 --save "" --appendonly no

# ── Restore ──
# Keep trying while the server is unreachable; 404 = first start, nothing to
# restore. Nothing is uploaded at shutdown unless this ends with a state.
restored=""
if [[ -n "$HOME_SERVER" ]]; then
	for i in $(seq 1 30); do
		status=$(curl -I --silent --insecure --max-time 30 "$BACKUP_URL" | grep ^HTTP | awk '{print $2}')
		[[ -z "$status" ]] && { sleep 10; continue; }
		if [[ "$status" -ge 400 ]]; then
			# 404 means nothing to restore - but only if the server knows this pod
			folder=$(curl -X PROPFIND -H 'Depth: 0' --silent --insecure --max-time 30 -o /dev/null -w '%{http_code}' "$PROTO://sciencedata/files/")
			[[ "$status" == 404 && "$folder" == 2* ]] && { restored="nothing to restore"; break; }
			sleep 10; continue
		fi
		mkdir -p /var/tmp/overleaf_restore
		curl -L --insecure --fail --silent --max-time 3600 "$BACKUP_URL" | tar -x -C /var/tmp/overleaf_restore && { restored="restored"; break; }
		rm -rf /var/tmp/overleaf_restore
		sleep 10
	done
fi
echo "persistence: ${restored:-no backup reachable at $BACKUP_URL - shutdown backup disabled}"

mkdir -p "$DATA"
if [[ "$restored" == "restored" ]]; then
	mongorestore --quiet --drop --gzip --archive=/var/tmp/overleaf_restore/mongo.archive.gz
	for d in history template_files sciencedata; do
		[[ -d /var/tmp/overleaf_restore/$d ]] && { rm -rf "$DATA/$d"; mv /var/tmp/overleaf_restore/$d "$DATA/"; }
	done
	rm -rf /var/tmp/overleaf_restore
fi
[[ -n "$restored" ]] && echo "$restored" > /run/overleaf_restored

# ── Secrets: kept with the data, the same across restarts ──
mkdir -p "$STATE"
for name in OVERLEAF_INVITE_TOKEN_SECRET OVERLEAF_SESSION_SECRET; do
	[[ -s "$STATE/$name" ]] || head -c 32 /dev/urandom | base64 | tr -d '\n/+=' > "$STATE/$name"
	cp "$STATE/$name" "$ENVDIR/$name"
done
chmod 700 "$STATE"

# ── The public address, from the port kube's reverse proxy got for this pod ──
if [[ -n "$HTTPS_PORT" ]]; then
	echo -n "https://kube.sciencedata.dk:$HTTPS_PORT" > "$ENVDIR/OVERLEAF_SITE_URL"
fi

# ── Login with ScienceData accounts, for a pod started for a group ──
# The Containers app gives the pod a login client of the OpenID Connect
# provider on the master, restricted to the group (its port is only known now,
# so the pod asks). Asked as root - Overleaf's own user cannot reach the home
# server - and authenticated as the pod's owner by the pod network's address
# login. {"oidc": false}: started just for the owner, who keeps the local login.
login=""
if [[ -n "$HOME_SERVER" ]]; then
	# 503 while the pod is not yet in the container list: ask again; 404: the
	# Containers app here is too old to know about it - no need to wait
	for i in $(seq 1 30); do
		login=$(curl -s --insecure --max-time 20 -w '\n%{http_code}' "$PROTO://sciencedata/index.php/apps/user_pods/api/pod-login")
		code=${login##*$'\n'}; login=${login%$'\n'*}
		echo "$login" | grep -q '"oidc"' && break
		login=""
		[[ "$code" == 404 ]] && break
		sleep 10
	done
fi
if echo "$login" | grep -q '"oidc":true'; then
	field() { echo "$login" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"; }
	echo -n "$(field issuer)" > "$ENVDIR/OVERLEAF_OIDC_ISSUER"
	echo -n "$(field authorization_url)" > "$ENVDIR/OVERLEAF_OIDC_AUTHORIZATION_URL"
	echo -n "$(field token_url)" > "$ENVDIR/OVERLEAF_OIDC_TOKEN_URL"
	echo -n "$(field userinfo_url)" > "$ENVDIR/OVERLEAF_OIDC_USER_INFO_URL"
	echo -n "$(field logout_url)" > "$ENVDIR/OVERLEAF_OIDC_LOGOUT_URL"
	echo -n "$(field client_id)" > "$ENVDIR/OVERLEAF_OIDC_CLIENT_ID"
	echo -n "$(field client_secret)" > "$ENVDIR/OVERLEAF_OIDC_CLIENT_SECRET"
	chmod 600 "$ENVDIR"/OVERLEAF_OIDC_CLIENT_SECRET
	echo -n "profile email" > "$ENVDIR/OVERLEAF_OIDC_SCOPE"   # openid is added by Overleaf itself
	# The owner (SD_UID) is Overleaf's administrator also when logging in this
	# way - recognised by the login's user name (preferred_username = the
	# ScienceData user ID), not the e-mail: outside DTU the two differ (the ID
	# is e.g. 561649@au.dk, the e-mail firstname.lastname@au.dk).
	if [[ -n "$SD_UID" ]]; then
		echo -n "username" > "$ENVDIR/OVERLEAF_OIDC_IS_ADMIN_FIELD"
		echo -n "$SD_UID" > "$ENVDIR/OVERLEAF_OIDC_IS_ADMIN_FIELD_VALUE"
	fi
	echo -n "oidc" > "$ENVDIR/EXTERNAL_AUTH"
	echo "login: ScienceData accounts, members of group $(field group)"
else
	echo "login: Overleaf's own accounts (${login:-no answer from the Containers app})"
fi

exit 0
