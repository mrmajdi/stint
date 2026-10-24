#!/usr/bin/env bash
# stint UserPromptSubmit hook: when the 5-hour or the weekly usage window crosses 80, 90 or 95
# percent, tell the agent once per window and level to update the handoff note.
# Reads what hooks/statusline.sh saved; prints nothing otherwise.

input=""
IFS= read -r -t 2 -d '' input || true
session=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)

state="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/stint"
[ -f "$state/limits" ] || exit 0
get() { sed -n "s/^$1=//p" "$state/limits"; }

# Stale numbers (no status line refresh for 20 minutes) are not worth acting on.
[ $(( $(date +%s) - $(get updated || echo 0) )) -le 1200 ] || exit 0

level() { local p=${1:-0}; if [ "$p" -ge 95 ]; then echo 95; elif [ "$p" -ge 90 ]; then echo 90; elif [ "$p" -ge 80 ]; then echo 80; else echo 0; fi; }
at() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }

warnings=""
for window in five_hour seven_day; do
  used=$(get "$window"); reset=$(get "${window}_resets")
  now=$(level "$used")
  [ "$now" -gt 0 ] || continue
  seen="$state/warned-${session:-unknown}-$window"
  [ "$(cat "$seen" 2>/dev/null || echo 0)" -ge "$now" ] && continue
  echo "$now" > "$seen"
  if [ "$window" = five_hour ]; then
    name="5-hour window"; when=${reset:+, resets at $(at "$reset" %H:%M)}
  else
    name="weekly limit"; when=${reset:+, resets $(at "$reset" '%a %H:%M')}
  fi
  warnings="$warnings${warnings:+; }$used% of the $name$when"
done

[ -n "$warnings" ] || exit 0
echo "stint: the user has used $warnings. Update .stint/handoff.md now, before continuing, so the work survives if the limit cuts this chat off. Mention it in one short line."
exit 0
