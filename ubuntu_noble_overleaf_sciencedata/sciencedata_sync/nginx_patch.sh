#!/bin/sh
# Build time: wire the ScienceData sync into Overleaf's nginx template
# (/etc/nginx/templates/overleaf.conf.template, rendered at start by
# 200_nginx_config_template.sh, whose envsubst only replaces a fixed list of
# Overleaf's variables - nginx variables such as $sd_csp_nonce survive).
#  - /sciencedata/ goes to the helper (server.mjs, 127.0.0.1:8899);
#  - pages get <script src="/sciencedata/ui.js"> with the nonce of the page's
#    own Content-Security-Policy, which Overleaf sends with a fresh nonce per
#    page ('strict-dynamic': only nonce-bearing scripts run);
#  - the upstream must not compress, or sub_filter cannot see </head>;
#  - existing static files are served by nginx itself (see the comment there).
# Fails the build if the template no longer has the expected shape.
set -e
T=/etc/nginx/templates/overleaf.conf.template
grep -q '^	location / {$' "$T" || { echo "nginx_patch: 'location / {' not found in $T"; exit 1; }
python3 - "$T" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
head = """# ScienceData sync (sciencedata_sync/nginx_patch.sh): the page's CSP nonce
map $upstream_http_content_security_policy $sd_csp_nonce {
	default "";
	"~'nonce-(?<sdnonce>[^']+)'" $sdnonce;
}

"""
loc = """	location /sciencedata/ {
		proxy_pass http://127.0.0.1:8899;
		proxy_set_header Host $host;
		proxy_read_timeout 15m;
		proxy_send_timeout 15m;
		client_max_body_size 1m;
	}

	# Files that exist in public/ (scripts, styles, fonts) straight from nginx:
	# Overleaf's web service crashes (Node 24, its static-file code) when a
	# browser abandons such a download - e.g. by clicking on while a page loads -
	# and the next requests get 502 until it has restarted.
	location / {
		try_files $uri @overleaf_web;
	}

	# "/" itself is public/ - a folder, which try_files would serve as such
	location = / {
		try_files /.no-such-file @overleaf_web;
	}

	location @overleaf_web {
		proxy_set_header Accept-Encoding "";
		sub_filter '</head>' '<script nonce="$sd_csp_nonce" src="/sciencedata/ui.js" defer></script></head>';
		sub_filter_once on;
"""
assert s.count("\tlocation / {\n") == 1
s = head + s.replace("\tlocation / {\n", loc, 1)
open(p, "w").write(s)
PY
grep -q 'sd_csp_nonce' "$T"
echo "nginx_patch: ScienceData sync wired into $T"
