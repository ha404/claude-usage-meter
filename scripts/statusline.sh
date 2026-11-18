#!/bin/bash
# Claude Code status line: model │ 5h usage bar │ 7d usage bar.
# Reads rate limits from Claude Code's stdin JSON; falls back to the menu bar app's cache.
input=$(cat)
CACHE="$HOME/.claude/usage-meter-cache.json"
MAX_CACHE_AGE=600

model=$(jq -r '.model.display_name // empty' <<<"$input")

# Emits "pct resets_epoch" for a window, or nothing.
window() {
  local key=$1 out
  out=$(jq -r --arg k "$key" '.rate_limits[$k] // empty | "\(.used_percentage) \(.resets_at // "")"' <<<"$input" 2>/dev/null)
  if [ -z "$out" ] && [ -f "$CACHE" ]; then
    out=$(jq -r --arg k "$key" --argjson max "$MAX_CACHE_AGE" '
      select(now - .timestamp < $max) | .[$k] // empty | "\(.utilization) \(.resets_at // "")"' "$CACHE" 2>/dev/null)
  fi
  echo "$out"
}

color() {
  local p=${1%.*}
  if   [ "$p" -lt 50 ]; then printf '\033[32m'
  elif [ "$p" -lt 80 ]; then printf '\033[33m'
  else printf '\033[31m'; fi
}

# segment <label> <window-seconds> <pct> <resets_epoch>
segment() {
  local label=$1 length=$2 pct=$3 resets=$4
  local p=${pct%.*} cells=10 filled marker=-1 bar="" i
  filled=$(( (p * cells + 50) / 100 ))
  [ "$filled" -gt "$cells" ] && filled=$cells

  # Elapsed-time marker: which cell "even pace" would reach by now.
  if [ -n "$resets" ]; then
    local remaining=$(( resets - $(date +%s) ))
    [ "$remaining" -lt 0 ] && remaining=0
    marker=$(( (length - remaining) * cells / length ))
    [ "$marker" -ge "$cells" ] && marker=$(( cells - 1 ))
  fi

  for (( i = 0; i < cells; i++ )); do
    if   [ "$i" -eq "$marker" ]; then bar+=$'\033[1;37m│'"$(color "$p")"
    elif [ "$i" -lt "$filled" ]; then bar+="▓"
    else bar+="░"; fi
  done

  local when=""
  if [ -n "$resets" ]; then
    if [ "$length" -le 18000 ]; then
      when=" ↻$(date -r "$resets" '+%-I:%M%p')"
    else
      when=" ↻$(date -r "$resets" '+%a %-I%p')"
    fi
  fi

  printf '\033[90m%s\033[0m %s%s\033[0m %s%%\033[90m%s\033[0m' \
    "$label" "$(color "$p")" "$bar" "$p" "$when"
}

parts=()
[ -n "$model" ] && parts+=("$model")
read -r p5 r5 <<<"$(window five_hour)"
[ -n "$p5" ] && parts+=("$(segment 5h 18000 "$p5" "$r5")")
read -r p7 r7 <<<"$(window seven_day)"
[ -n "$p7" ] && parts+=("$(segment 7d 604800 "$p7" "$r7")")

sep=$'\033[90m │ \033[0m'
out=""
for part in "${parts[@]}"; do
  out+="${out:+$sep}$part"
done
printf '%s\n' "$out"
