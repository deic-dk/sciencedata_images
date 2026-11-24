#!/bin/bash
#
# license_relay_client.sh - run on login.gbar.dtu.dk (from cron, as an ordinary user).
#
# Starts the chisel client that dials out to kube's license relay (unless it already
# runs) and opens reverse ports there for DTU's MATLAB and Mathematica license servers,
# which gbar can reach and kube cannot. Pods then use licenses:1711/1712/16286.
#
# Needs, in ~/.license_relay (mode 600):
#   CHISEL=~/bin/chisel                       # chisel 1.10.1, linux_amd64
#   AUTH=gbar:<password from users.json>
#   FINGERPRINT=<the server's fingerprint>    # printed by setup, pins kube's identity
# crontab:  */5 * * * * ~/bin/license_relay_client.sh >/dev/null 2>&1
#

CONF=~/.license_relay
LOG=~/license_relay.log
[ -r "$CONF" ] || { echo "No $CONF" >&2; exit 1; }
. "$CONF"

# One client per user on this login node
pgrep -u "$(id -u)" -f "chisel client .*kube.sciencedata.dk:4443" >/dev/null && exit 0

# AUTH is read from the environment, so the password does not show up in ps
export AUTH
nohup "$CHISEL" client --fingerprint "$FINGERPRINT" --keepalive 25s --max-retry-interval 1m \
	https://kube.sciencedata.dk:4443 \
	R:0.0.0.0:1711:license1.cc.dtu.dk:1711 \
	R:0.0.0.0:1712:license1.cc.dtu.dk:1712 \
	R:0.0.0.0:16286:mathematica-ls.mbar.dtu.dk:16286 \
	>> "$LOG" 2>&1 &
