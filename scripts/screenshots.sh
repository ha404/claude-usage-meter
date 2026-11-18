#!/bin/bash
# Regenerates the README screenshots in docs/ from sample data.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN=$WORK/render
swiftc -o "$BIN" $(ls Sources/ClaudeUsageMeter/*.swift | grep -v App.swift) scripts/screenshots/main.swift

# Sample status lines, produced by the real status line script.
now=$(date +%s)
line() {
  echo "{\"model\":{\"display_name\":\"$1\"},\"rate_limits\":{
    \"five_hour\":{\"used_percentage\":$2,\"resets_at\":$((now + $3))},
    \"seven_day\":{\"used_percentage\":$4,\"resets_at\":$((now + $5))}}}" | bash scripts/statusline.sh
}

mkdir -p docs
"$BIN" docs \
  "$(line 'Opus 5.5' 20 9900 36 302400)" \
  "$(line 'Opus 5.5' 48 12600 36 302400)" \
  "$(line 'Opus 5.5' 90 5400 62 272160)" \
  "$(line 'Opus 5.5' 100 3600 70 241920)"
