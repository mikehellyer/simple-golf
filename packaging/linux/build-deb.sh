#!/usr/bin/env bash
# Packages build/linux/simple-golf.x86_64 (already exported by Godot, with the
# game data embedded) into a .deb that installs to /opt/simple-golf and adds
# a menu entry and icon, so it behaves like a native app rather than a
# dropped binary. Uses dpkg-deb directly, which ships with Debian-based
# distros (Pop!_OS included), so CI needs no extra tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY="$ROOT/build/linux/simple-golf.x86_64"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")"
ARCH="amd64"
PKG_ROOT="$ROOT/dist/deb-staging"
OUT="$ROOT/dist/simple-golf_${VERSION}_${ARCH}.deb"

if [ ! -f "$BINARY" ]; then
  echo "error: $BINARY not found — export the Linux preset first" >&2
  exit 1
fi

rm -rf "$PKG_ROOT" "$OUT"
mkdir -p "$PKG_ROOT/DEBIAN" "$PKG_ROOT/opt/simple-golf" "$PKG_ROOT/usr/bin" \
  "$PKG_ROOT/usr/share/applications"

install -m 755 "$BINARY" "$PKG_ROOT/opt/simple-golf/simple-golf"
ln -s /opt/simple-golf/simple-golf "$PKG_ROOT/usr/bin/simple-golf"
cp "$ROOT/packaging/linux/simple-golf.desktop" "$PKG_ROOT/usr/share/applications/"

for size in 16 32 48 64 128 256 512; do
  dir="$PKG_ROOT/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  cp "$ROOT/packaging/icons/icon_${size}.png" "$dir/simple-golf.png"
done

cat > "$PKG_ROOT/DEBIAN/control" <<EOF
Package: simple-golf
Version: $VERSION
Section: games
Priority: optional
Architecture: $ARCH
Maintainer: Mike Hellyer
Description: A modern re-imagining of MicroProse Golf
 3D golf with a classic three-click swing meter, procedurally generated
 courses, a course editor, computer opponents, hot-seat and online
 multiplayer, and an in-game update check.
EOF

dpkg-deb --build --root-owner-group "$PKG_ROOT" "$OUT"
rm -rf "$PKG_ROOT"

echo "wrote $OUT"
