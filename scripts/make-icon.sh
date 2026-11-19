#!/bin/bash
# Regenerates assets/AppIcon.icns from scripts/icon/main.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swiftc -o "$WORK/render" scripts/icon/main.swift
"$WORK/render" "$WORK/AppIcon.iconset"
mkdir -p assets
iconutil -c icns "$WORK/AppIcon.iconset" -o assets/AppIcon.icns
echo "Wrote assets/AppIcon.icns"
