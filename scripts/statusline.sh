#!/usr/bin/env bash
# braindrain: Claude Code status-line script.
# Reads the session JSON on stdin and prints a colored one-line verdict:
#   - green "SMART" while total input tokens are below 100,000
#   - red   "DUMB"  once total input tokens reach 100,000

set -u

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "braindrain: install jq"
  exit 0
fi

input=$(cat)

tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
winsize=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // 200000')

case "$tokens" in ''|*[!0-9]*) tokens=0 ;; esac
case "$winsize" in ''|*[!0-9]*) winsize=200000 ;; esac

THRESHOLD=100000
BAR_WIDTH=10

if [ "$tokens" -lt "$THRESHOLD" ]; then
  label="SMART"
  color=$'\033[1;32m'
else
  label="DUMB "
  color=$'\033[1;31m'
fi

filled=$(( tokens * BAR_WIDTH / THRESHOLD ))
[ "$filled" -gt "$BAR_WIDTH" ] && filled="$BAR_WIDTH"
[ "$filled" -lt 0 ] && filled=0
empty=$(( BAR_WIDTH - filled ))

bar=""
[ "$filled" -gt 0 ] && { printf -v fill_pad "%${filled}s" ""; bar="${fill_pad// /▓}"; }
[ "$empty" -gt 0 ]  && { printf -v empty_pad "%${empty}s" ""; bar="${bar}${empty_pad// /░}"; }

fmt_k() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    local whole=$(( n / 1000000 ))
    local rem=$(( (n % 1000000) / 100000 ))
    if [ "$rem" -eq 0 ]; then
      printf '%dM' "$whole"
    else
      printf '%d.%dM' "$whole" "$rem"
    fi
  elif [ "$n" -ge 1000 ]; then
    local whole=$(( n / 1000 ))
    local rem=$(( (n % 1000) / 100 ))
    if [ "$rem" -eq 0 ]; then
      printf '%dk' "$whole"
    else
      printf '%d.%dk' "$whole" "$rem"
    fi
  else
    printf '%d' "$n"
  fi
}

used_fmt=$(fmt_k "$tokens")
win_fmt=$(fmt_k "$winsize")

reset=$'\033[0m'
printf '%b%s  %s  %s / %s%b\n' "$color" "$label" "$bar" "$used_fmt" "$win_fmt" "$reset"
