#!/bin/bash
# Claude Code status line: model │ 5h usage bar │ 7d usage bar.
# Reads rate limits from Claude Code's stdin JSON and from the menu bar app's cache, and
# shows whichever reading is newer.
input=$(cat)
CACHE="$HOME/.claude/usage-meter-cache.json"
MAX_CACHE_AGE=600
# Reset times this close together (seconds) are the same window.
SAME_WINDOW=60
CELLS=10

model=$(jq -r '.model.display_name // empty' <<<"$input" 2>/dev/null)

# jq filter turning a window object into "<tenths of a percent> <resets epoch or nothing>".
# Emits nothing unless the percentage (field named by $pct) is a number, so a malformed
# window is dropped rather than drawn.
FORMAT='select(type == "object" and (.[$pct] | type) == "number")
  | "\(.[$pct] * 10 | round) \(.resets_at | if type == "number" then floor else "" end)"'

# newer <reading> <reading> -> the more recent of two "<tenths> <resets>" readings.
# Neither source says when it was measured, but usage only grows within a window, so:
# a later reset time means a newer window, and within one window the higher usage is
# the later measurement.
newer() {
  local a=$1 b=$2 pa ra pb rb
  [ -z "$a" ] && { echo "$b"; return; }
  [ -z "$b" ] && { echo "$a"; return; }
  read -r pa ra <<<"$a"
  read -r pb rb <<<"$b"
  if [ -n "$ra" ] && [ -n "$rb" ]; then
    [ $(( ra - rb )) -gt "$SAME_WINDOW" ] && { echo "$a"; return; }
    [ $(( rb - ra )) -gt "$SAME_WINDOW" ] && { echo "$b"; return; }
  fi
  [ "$pb" -gt "$pa" ] && { echo "$b"; return; }
  echo "$a"
}

# Claude Code's numbers come from this session's last API response, so they go stale
# while the session idles or you use Claude elsewhere; the app's cache is account-wide
# and at most a minute old while the app runs.
window() {
  local key=$1 session cached=""
  session=$(jq -r --arg k "$key" --arg pct used_percentage \
    ".rate_limits[\$k]? // empty | $FORMAT" <<<"$input" 2>/dev/null)
  if [ -f "$CACHE" ]; then
    cached=$(jq -r --arg k "$key" --arg pct utilization --argjson max "$MAX_CACHE_AGE" \
      "select(now - .timestamp < \$max) | .[\$k] // empty | $FORMAT" "$CACHE" 2>/dev/null)
  fi
  newer "$session" "$cached"
}

# severity <tenths of a percent used> <tenths of a percent elapsed, or empty>
#   -> 0 normal, 1 warning, 2 critical, 3 exhausted.
# Mirrors UsageWindow.severity in the app: the elapsed-time marker is "even pace", not a
# limit, so past it is orange (once 10%+ is used) and red only when also at 85%+ of the
# real limit. Falls back to absolute levels when there's no reset time.
severity() {
  local p=$1 e=$2
  [ "$p" -ge 1000 ] && { echo 3; return; }
  if [ -z "$e" ]; then
    [ "$p" -ge 800 ] && { echo 2; return; }
    [ "$p" -ge 500 ] && { echo 1; return; }
    echo 0; return
  fi
  { [ "$p" -le "$e" ] || [ "$p" -lt 100 ]; } && { echo 0; return; }
  [ "$p" -ge 850 ] && { echo 2; return; }
  echo 1
}

color() {
  case $1 in
    0) printf '\033[32m' ;;
    1) printf '\033[33m' ;;
    *) printf '\033[31m' ;;
  esac
}

# segment <label> <window-seconds> <tenths of a percent used> <resets_epoch>
segment() {
  local label=$1 length=$2 p10=$3 resets=$4
  local pct filled marker=-1 e10="" bar="" i sev c
  pct=$(( (p10 + 5) / 10 ))
  filled=$(( (p10 * CELLS + 500) / 1000 ))
  [ "$filled" -gt "$CELLS" ] && filled=$CELLS

  # Elapsed-time marker: drawn *between* cells at the boundary "even pace" has reached.
  if [ -n "$resets" ]; then
    local remaining=$(( resets - $(date +%s) ))
    [ "$remaining" -lt 0 ] && remaining=0
    [ "$remaining" -gt "$length" ] && remaining=$length
    e10=$(( (length - remaining) * 1000 / length ))
    marker=$(( (e10 * CELLS + 500) / 1000 ))
    # Ten cells can't show both values exactly, so keep the picture truthful about the
    # one thing it's for: fill reaches past the marker exactly when usage is ahead of pace.
    if [ "$p10" -gt "$e10" ]; then
      [ "$marker" -ge "$CELLS" ] && marker=$(( CELLS - 1 ))
      [ "$filled" -le "$marker" ] && filled=$(( marker + 1 ))
    elif [ "$filled" -gt "$marker" ]; then
      filled=$marker
    fi
  fi

  sev=$(severity "$p10" "$e10")
  c=$(color "$sev")

  local when=""
  if [ -n "$resets" ]; then
    if [ "$length" -le 18000 ]; then
      when=" 🔄 $(date -r "$resets" '+%-I:%M%p')"
    else
      when=" 🔄 $(date -r "$resets" '+%a %-I%p')"
    fi
  fi

  if [ "$sev" -eq 3 ]; then
    printf '\033[1;31m%s ███████████ LIMIT\033[0;31m%s\033[0m' "$label" "$when"
    return
  fi

  for (( i = 0; i <= CELLS; i++ )); do
    # Reset after the bold marker so the cells to its right aren't bold too.
    [ "$i" -eq "$marker" ] && bar+=$'\033[1;37m│\033[0m'"$c"
    [ "$i" -eq "$CELLS" ] && break
    if [ "$i" -lt "$filled" ]; then bar+="▓"; else bar+="░"; fi
  done

  printf '\033[90m%s\033[0m %s%s\033[0m %s%%\033[90m%s\033[0m' \
    "$label" "$c" "$bar" "$pct" "$when"
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
