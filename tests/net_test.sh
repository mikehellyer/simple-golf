#!/usr/bin/env bash
# End-to-end network test: a host and a client play a short stroke-play game
# over localhost (both humans auto-played, plus one computer golfer), then
# their logs must agree on every shot, hole score and the final result.
#
# Usage: tests/net_test.sh [path-to-godot]
# Optional env: MODE (Competition.Mode, default 0), CPUS (kinds, default "2"),
# PLAYERS (total players to wait for, default 3).
set -euo pipefail

GODOT="${1:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; [ -n "${KEEP_LOGS:-}" ] && cp -r "$OUT" "$KEEP_LOGS"; rm -rf "$OUT"' EXIT

COMMON=(--headless --path "$DIR" --fixed-fps 30)
ARGS=(--autoplay --net-log --quit-at-end)

"$GODOT" "${COMMON[@]}" -- --host --name=Host --mode="${MODE:-0}" --holes=2 \
	--cpus="${CPUS:-2}" --auto-start="${PLAYERS:-3}" \
	"${ARGS[@]}" > "$OUT/host.log" 2>&1 &
HOST=$!
sleep 2
"$GODOT" "${COMMON[@]}" -- --join=127.0.0.1 --name=Guest "${ARGS[@]}" > "$OUT/client.log" 2>&1 &
CLIENT=$!

# Give the round up to five minutes.
for _ in $(seq 300); do
	if ! kill -0 "$HOST" 2>/dev/null && ! kill -0 "$CLIENT" 2>/dev/null; then
		break
	fi
	sleep 1
done

summary() {
	# Authoritative results only (the "local=" part is each machine's own simulation).
	grep -E '^(SHOT|HOLE|ROUND)' "$1" | sed 's/ local=.*//'
}

fail=0
if ! grep -q '^ROUND' "$OUT/host.log"; then
	echo "FAIL: host did not finish the round"; fail=1
fi
if ! grep -q '^ROUND' "$OUT/client.log"; then
	echo "FAIL: client did not finish the round"; fail=1
fi
if ! diff <(summary "$OUT/host.log") <(summary "$OUT/client.log") > "$OUT/diff.txt"; then
	echo "FAIL: host and client disagree:"; cat "$OUT/diff.txt"; fail=1
fi
if grep -E 'SCRIPT ERROR|ERROR:' "$OUT/host.log" "$OUT/client.log" | grep -v 'at:' ; then
	echo "FAIL: script errors"; fail=1
fi

# How often did a machine's own simulation differ from the host's verdict?
# Penalty shots (water, out of bounds) are placed by the rules, not where
# the ball stopped, so only compare shots that came to rest or were holed.
drift=$(grep -E '^SHOT .*outcome=(0|1) ' "$OUT/client.log" | awk '{
	split($0, a, "pos="); split(a[2], p, " local="); split(p[1], x, ","); split(p[2], y, ",")
	d = (x[1]-y[1])^2 + (x[3]-y[3])^2; if (d > 0.0001) n++ } END { print n+0 }')

# For any drift, show what each machine fed into the simulation.
if [ "$drift" -gt 0 ]; then
	echo "Drift details (host decided / client simulated):"
	paste <(grep '^INPUT' "$OUT/host.log") <(grep '^LOCAL' "$OUT/client.log") | awk -F'\t' '{
		split($1, a, "INPUT "); split($2, b, "LOCAL "); if (a[2] != b[2]) { print "  host:   " a[2]; print "  client: " b[2] } }'
fi

shots=$(grep -c '^SHOT' "$OUT/host.log" || true)
echo "shots: $shots, holes: $(grep -c '^HOLE' "$OUT/host.log" || true), client sim drift: $drift"
grep '^ROUND' "$OUT/host.log" || true
if [ "$fail" -ne 0 ]; then
	echo "--- host log tail"; tail -20 "$OUT/host.log"
	echo "--- client log tail"; tail -20 "$OUT/client.log"
	exit 1
fi
echo "PASS"
