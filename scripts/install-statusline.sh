#!/bin/bash
# Installs the status line script and points ~/.claude/settings.json at it.
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$HOME/.claude/usage-meter-statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

cp statusline.sh "$TARGET"
chmod +x "$TARGET"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
tmp=$(mktemp)
jq --arg cmd "bash $TARGET" '.statusLine = {type: "command", command: $cmd, padding: 0}' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
echo "Status line installed: $TARGET"
