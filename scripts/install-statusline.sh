#!/bin/bash
# Installs the status line script and points ~/.claude/settings.json at it.
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$HOME/.claude/usage-meter-statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
COMMAND="bash \"$TARGET\""

command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 1; }

mkdir -p "$HOME/.claude"
cp statusline.sh "$TARGET"
chmod +x "$TARGET"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

current=$(jq -r '.statusLine.command // empty' "$SETTINGS")
if [ "$current" = "$COMMAND" ]; then
  echo "Status line updated: $TARGET (settings.json already points at it)"
  exit 0
fi
[ -n "$current" ] && echo "Replacing existing status line: $current"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --arg cmd "$COMMAND" '.statusLine = {type: "command", command: $cmd, padding: 0}' "$SETTINGS" > "$tmp"
cp "$SETTINGS" "$SETTINGS.bak"
# Write through the existing file (not mv) so a symlinked settings.json and its
# permissions survive.
cat "$tmp" > "$SETTINGS"
echo "Status line installed: $TARGET (previous settings saved to $SETTINGS.bak)"
