#!/usr/bin/env bash
# Starts a throwaway society server on localhost and runs the game's society
# client against it (tests/society_test.gd).
#
# Usage: tests/society_test.sh [path-to-godot]
# Needs the server's virtualenv: cd server && python3 -m venv .venv &&
#   .venv/bin/pip install -r requirements-dev.txt
set -euo pipefail

GODOT="${1:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
PORT=18765
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$TMP"' EXIT

(cd "$DIR/server" && SIMPLEGOLF_DB="$TMP/test.db" .venv/bin/uvicorn simplegolf_server.app:app \
	--host 127.0.0.1 --port "$PORT" > "$TMP/server.log" 2>&1) &
for _ in $(seq 50); do
	curl -sf "http://127.0.0.1:$PORT/api/v1/health" > /dev/null && break
	sleep 0.2
done

# Keep the test's sign-ins out of the real user data folder.
SOCIETY_URL="http://127.0.0.1:$PORT" XDG_DATA_HOME="$TMP/data" \
	"$GODOT" --headless --path "$DIR" --script res://tests/society_test.gd 2>&1 | grep -v "^ *at:"
