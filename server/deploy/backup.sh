#!/usr/bin/env bash
# Nightly backup of the society database (run from cron as simplegolf).
# Keeps 14 days of copies in /var/lib/simplegolf/backups.
set -euo pipefail
dir=/var/lib/simplegolf/backups
mkdir -p "$dir"
sqlite3 /var/lib/simplegolf/simplegolf.db ".backup '$dir/simplegolf-$(date +%F).db'"
find "$dir" -name 'simplegolf-*.db' -mtime +14 -delete
