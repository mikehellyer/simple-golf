#!/usr/bin/env bash
# Installs (or updates) the Simple-Golf society server.
#
# On a Raspberry Pi (or any Debian/Ubuntu box at home), shared through
# Tailscale Funnel: no router changes, works behind any home internet:
#   curl -fsSL https://raw.githubusercontent.com/mikehellyer/simple-golf/main/server/deploy/install.sh \
#     | sudo bash -s -- --funnel
#
# On a cloud machine with its own domain name (Caddy for HTTPS):
#   curl -fsSL .../install.sh | sudo bash -s -- --domain yourname.duckdns.org
#
# Options:
#   --port N          local port for the server (default 8000; change it if
#                     something else on the machine already uses 8000)
#   --funnel-port N   public HTTPS port for Funnel: 443, 8443 or 10000
#                     (default: 443, or 8443 if 443 is already in use)
#
# Safe to run again later: it updates to the latest code and keeps the data.
set -euo pipefail

MODE=""
DOMAIN=""
PORT=8000
FUNNEL_PORT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--funnel) MODE=funnel ;;
		--domain) MODE=domain; DOMAIN="${2:?--domain needs a name}"; shift ;;
		--port) PORT="${2:?}"; shift ;;
		--funnel-port) FUNNEL_PORT="${2:?}"; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done
[ -n "$MODE" ] || { echo "usage: install.sh --funnel | --domain NAME  [--port N] [--funnel-port N]" >&2; exit 2; }

REPO=https://github.com/mikehellyer/simple-golf.git
SRC=/opt/simple-golf
DATA=/var/lib/simplegolf

echo "==> Checking this machine"
case "$(uname -m)" in
	aarch64|x86_64) ;;
	*) echo "This needs a 64-bit OS (found $(uname -m)). On a Raspberry Pi, install Raspberry Pi OS (64-bit)." >&2; exit 1 ;;
esac
if ss -ltn "sport = :$PORT" | grep -q LISTEN && ! systemctl is-active --quiet simplegolf; then
	echo "Port $PORT is already in use by something else. Re-run with --port and a free port, e.g. --port 8090." >&2
	exit 1
fi

echo "==> Packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git python3-venv sqlite3 curl

echo "==> Service account and data folder"
id simplegolf >/dev/null 2>&1 || useradd --system --home "$DATA" --create-home --shell /usr/sbin/nologin simplegolf
mkdir -p "$DATA/backups"
chown -R simplegolf:simplegolf "$DATA"

echo "==> Code"
if [ -d "$SRC/.git" ]; then
	git -C "$SRC" pull --ff-only
else
	git clone --depth 1 "$REPO" "$SRC"
fi
python3 -m venv "$SRC/server/.venv"
"$SRC/server/.venv/bin/pip" install -q --upgrade pip
"$SRC/server/.venv/bin/pip" install -q -r "$SRC/server/requirements.txt"

echo "==> systemd service (port $PORT)"
sed "s/--port 8000/--port $PORT/" "$SRC/server/deploy/simplegolf.service" > /etc/systemd/system/simplegolf.service
systemctl daemon-reload
systemctl enable --now simplegolf
systemctl restart simplegolf

echo "==> Nightly backup at 03:30"
install -m 755 "$SRC/server/deploy/backup.sh" /usr/local/bin/simplegolf-backup
echo "30 3 * * * simplegolf /usr/local/bin/simplegolf-backup" > /etc/cron.d/simplegolf-backup

sleep 2
curl -fsS "http://127.0.0.1:$PORT/api/v1/health" > /dev/null && echo "Server is running on port $PORT."

if [ "$MODE" = funnel ]; then
	echo "==> Tailscale Funnel"
	command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
	if ! tailscale status >/dev/null 2>&1; then
		echo "Sign this machine in to Tailscale: open the link that appears next."
		tailscale up
	fi
	if [ -z "$FUNNEL_PORT" ]; then
		# Leave anything already shared on 443 (another app) alone.
		USED_443="$(tailscale serve status --json 2>/dev/null | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: d = {}
print("yes" if "443" in (d.get("TCP") or {}) else "no")')"
		if [ "$USED_443" = yes ]; then
			FUNNEL_PORT=8443
		else
			FUNNEL_PORT=443
		fi
	fi
	echo "Sharing the server publicly on HTTPS port $FUNNEL_PORT."
	echo "(If Tailscale asks you to enable Funnel or HTTPS for your tailnet, open its link, approve, and this continues.)"
	tailscale funnel --bg --https="$FUNNEL_PORT" "$PORT"
	NAME="$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
	ADDRESS="$NAME"
	[ "$FUNNEL_PORT" = 443 ] || ADDRESS="$NAME:$FUNNEL_PORT"
else
	echo "==> HTTPS (Caddy) for $DOMAIN"
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq caddy
	# Cloud images (e.g. Oracle's Ubuntu) block web ports in the machine's
	# own firewall as well as the provider's; open 80 and 443 here.
	if iptables -S INPUT 2>/dev/null | grep -q REJECT; then
		DEBIAN_FRONTEND=noninteractive apt-get install -y -qq netfilter-persistent iptables-persistent
		for p in 80 443; do
			iptables -C INPUT -p tcp --dport "$p" -m state --state NEW -j ACCEPT 2>/dev/null \
				|| iptables -I INPUT 5 -p tcp --dport "$p" -m state --state NEW -j ACCEPT
		done
		netfilter-persistent save
	fi
	sed "s/YOUR-NAME.duckdns.org/$DOMAIN/; s/127.0.0.1:8000/127.0.0.1:$PORT/" "$SRC/server/deploy/Caddyfile" > /etc/caddy/Caddyfile
	systemctl reload caddy || systemctl restart caddy
	ADDRESS="$DOMAIN"
fi

echo
echo "Done. Check it in a browser (it can take a minute to get its certificate):"
echo "  https://$ADDRESS/api/v1/health"
echo "Then enter this as the server in Simple-Golf's Online society tab:"
echo "  $ADDRESS"
