#!/usr/bin/env bash
# Packages build/macos/Simple-Golf.zip (the .app exported by Godot) into a
# .dmg where dragging the app onto an Applications shortcut is the install
# step. Uses hdiutil, which ships with macOS, so CI needs no extra tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZIP="$ROOT/build/macos/Simple-Golf.zip"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")"
OUT="$ROOT/dist/Simple-Golf-$VERSION-macOS.dmg"
STAGING="$ROOT/dist/dmg-staging"

if [ ! -f "$ZIP" ]; then
  echo "error: $ZIP not found — export the macOS preset first" >&2
  exit 1
fi

rm -rf "$STAGING" "$OUT"
mkdir -p "$STAGING"
ditto -x -k "$ZIP" "$STAGING"
if [ ! -d "$STAGING/Simple-Golf.app" ]; then
  echo "error: Simple-Golf.app not found inside $ZIP" >&2
  exit 1
fi
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Simple-Golf" -srcfolder "$STAGING" -ov -format UDZO "$OUT"
rm -rf "$STAGING"

echo "wrote $OUT"
