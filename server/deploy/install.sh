#!/usr/bin/env bash
# Installs (or updates) the Simple-Golf society server on a fresh Ubuntu
# 24.04 machine, e.g. an Oracle Cloud Always Free VM. Run as a sudo user:
#
#   curl -fsSL https://raw.githubusercontent.com/mikehellyer/simple-golf/main/server/deploy/install.sh \
#     | sudo bash -s -- yourname.duckdns.org
#
# Safe to run again later to update to the latest code.
set -euo pipefail

DOMAIN="${1:?usage: install.sh your.domain.name}"
REPO=https://github.com/mikehellyer/simple-golf.git
SRC=/opt/simple-golf
DATA=/var/lib/simplegolf

echo "==> Packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git python3-venv sqlite3 caddy netfilter-persistent iptables-persistent

echo "==> Open the web ports in the machine's own firewall"
# Oracle's Ubuntu images block everything except SSH with iptables, on top
# of the cloud security list. (Add 80 and 443 there too; see DEPLOY.md.)
for port in 80 443; do
	iptables -C INPUT -p tcp --dport "$port" -m state --state NEW -j ACCEPT 2>/dev/null \
		|| iptables -I INPUT 5 -p tcp --dport "$port" -m state --state NEW -j ACCEPT
done
netfilter-persistent save

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

echo "==> systemd service"
cp "$SRC/server/deploy/simplegolf.service" /etc/systemd/system/simplegolf.service
systemctl daemon-reload
systemctl enable --now simplegolf
systemctl restart simplegolf

echo "==> HTTPS (Caddy)"
sed "s/YOUR-NAME.duckdns.org/$DOMAIN/" "$SRC/server/deploy/Caddyfile" > /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy

echo "==> Nightly backup at 03:30"
install -m 755 "$SRC/server/deploy/backup.sh" /usr/local/bin/simplegolf-backup
echo "30 3 * * * simplegolf /usr/local/bin/simplegolf-backup" > /etc/cron.d/simplegolf-backup

echo "==> Checking"
sleep 2
curl -fsS http://127.0.0.1:8000/api/v1/health && echo
echo
echo "Done. In a minute or two (once Caddy has its certificate) this should work:"
echo "  https://$DOMAIN/api/v1/health"
echo "Then enter $DOMAIN as the server in Simple-Golf's Online society tab."
