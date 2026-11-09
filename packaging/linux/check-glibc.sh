#!/usr/bin/env bash
# Fails if anything in the exported game needs a newer glibc than the oldest
# Linux we support. Simple-Track's PyInstaller build broke this way when
# GitHub moved ubuntu-latest to Ubuntu 26 (glibc 2.43) and died at once on
# Pop!_OS 24.04 (glibc 2.39). Godot's export templates are built against an
# old glibc so this should always pass, but it makes sure before we ship.
#
# Usage: packaging/linux/check-glibc.sh build/linux [max version, default 2.39]
set -euo pipefail

BUNDLE="${1:?usage: check-glibc.sh <export folder> [max glibc]}"
MAX="${2:-2.39}"  # Pop!_OS / Ubuntu 24.04

NEEDED="$(find "$BUNDLE" -type f \( -name '*.so*' -o -perm -u+x -o -name '*.x86_64' \) -print0 \
  | xargs -0 objdump -T 2>/dev/null \
  | grep -o 'GLIBC_[0-9]*\.[0-9]*' | sed 's/GLIBC_//' | sort -u -V | tail -1)"

echo "bundle needs glibc ${NEEDED:-?}; allowed up to $MAX"
if [ -n "$NEEDED" ] && [ "$(printf '%s\n%s\n' "$NEEDED" "$MAX" | sort -V | tail -1)" != "$MAX" ]; then
  echo "error: built against too new a glibc — build on an older Ubuntu" >&2
  exit 1
fi
