#!/bin/bash
# Installs the status line script and points ~/.claude/settings.json at it.
#   --uninstall   remove the script and its settings.json entry again
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$HOME/.claude/usage-meter-statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
COMMAND="bash \"$TARGET\""

command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 1; }

# write_settings <new-settings-file>: replaces settings.json, keeping a backup. Writes
# through the existing file (not mv) so a symlinked settings.json and its permissions survive.
write_settings() {
  cp "$SETTINGS" "$SETTINGS.bak"
  cat "$1" > "$SETTINGS"
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$TARGET"
  [ -f "$SETTINGS" ] || { echo "Status line removed"; exit 0; }
  # Only our own entry is removed; another tool's status line is left alone.
  jq --arg script "$(basename "$TARGET")" \
    'if (.statusLine.command // "" | contains($script)) then del(.statusLine) else . end' "$SETTINGS" > "$tmp"
  jq -e -n --slurpfile old "$SETTINGS" --slurpfile new "$tmp" '$old == $new' >/dev/null || write_settings "$tmp"
  echo "Status line removed (previous settings saved to $SETTINGS.bak)"
  exit 0
fi

mkdir -p "$HOME/.claude"
cp statusline.sh "$TARGET"
chmod +x "$TARGET"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Claude Code only re-runs a status line on session events, so an idle session would
# keep showing old numbers; refreshInterval (seconds) re-runs it on a timer as well.
REFRESH_INTERVAL=10

current=$(jq -r '.statusLine.command // empty' "$SETTINGS")

# Settings from an earlier install of this status line (padding, a refresh interval the
# user tuned) are kept; another tool's status line is replaced outright.
jq --arg cmd "$COMMAND" --arg script "$(basename "$TARGET")" --argjson refresh "$REFRESH_INTERVAL" '
  (if (.statusLine.command // "" | contains($script)) then .statusLine else {} end) as $ours
  | .statusLine = {
      type: "command",
      command: $cmd,
      padding: ($ours.padding // 0),
      refreshInterval: ($ours.refreshInterval // $refresh)
    }' "$SETTINGS" > "$tmp"

if jq -e -n --slurpfile old "$SETTINGS" --slurpfile new "$tmp" '$old == $new' >/dev/null; then
  echo "Status line updated: $TARGET (settings.json already points at it)"
  exit 0
fi
case "$current" in
  ""|*"$(basename "$TARGET")"*) ;;
  *) echo "Replacing existing status line: $current" ;;
esac

write_settings "$tmp"
echo "Status line installed: $TARGET (previous settings saved to $SETTINGS.bak)"
