#!/usr/bin/env bash
# stint usage limits. Claude Code gives usage-limit levels only to the status line, so this script runs two ways:
# as the status line ("limit-watch.sh status") it shows context and limits and saves the levels;
# as the UserPromptSubmit hook it tells the agent once per window and level (80, 90, 95 percent)
# to update the handoff note. Makes no network calls.

input=""
IFS= read -r -t 2 -d '' input || true
state="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/stint"

if [ "$1" = status ]; then
  json=$(printf '%s' "$input" | tr -d '\n')
  num() { printf '%s' "$json" | sed -n "s/.*\"$1\"[^}]*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p" | head -n 1; }
  five=$(num five_hour used_percentage)
  week=$(num seven_day used_percentage)
  five_reset=$(num five_hour resets_at)
  week_reset=$(num seven_day resets_at)
  context=$(num context_window used_percentage)
  # Limits come only on Pro and Max plans, after the first reply.
  if [ -n "$five$week" ]; then
    mkdir -p "$state" 2>/dev/null
    printf 'five_hour=%s\nseven_day=%s\nfive_hour_resets=%s\nseven_day_resets=%s\nupdated=%s\n' \
      "${five%.*}" "${week%.*}" "${five_reset%.*}" "${week_reset%.*}" "$(date +%s)" > "$state/limits.tmp" 2>/dev/null \
      && mv "$state/limits.tmp" "$state/limits" 2>/dev/null
  fi
  printf 'stint'
  [ -n "$context" ] && printf ' · context %s%%' "${context%.*}"
  [ -n "$five" ] && printf ' · 5h %s%%' "${five%.*}"
  [ -n "$week" ] && printf ' · week %s%%' "${week%.*}"
  echo
  exit 0
fi

session=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$session" ] || session=unknown
[ -f "$state/limits" ] || exit 0
get() { sed -n "s/^$1=//p" "$state/limits"; }

# Stale numbers (no status line refresh for 20 minutes) are not worth acting on.
now=$(date +%s)
updated=$(get updated)
[ -n "$updated" ] || updated=0
[ $((now - updated)) -le 1200 ] || exit 0

level() {
  local p=${1:-0}
  if [ "$p" -ge 95 ]; then echo 95; elif [ "$p" -ge 90 ]; then echo 90; elif [ "$p" -ge 80 ]; then echo 80; else echo 0; fi
}
clock() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }

warnings=""
for window in five_hour seven_day; do
  used=$(get "$window")
  reset=$(get "${window}_resets")
  current=$(level "$used")
  [ "$current" -gt 0 ] || continue
  seen="$state/warned-$session-$window"
  warned=$(cat "$seen" 2>/dev/null)
  [ "${warned:-0}" -ge "$current" ] && continue
  echo "$current" > "$seen"
  if [ "$window" = five_hour ]; then
    name="5-hour window"
    format=", resets at %H:%M"
  else
    name="weekly limit"
    format=", resets %a %H:%M"
  fi
  when=""
  if [ -n "$reset" ]; then
    when=$(clock "$reset" "$format")
  fi
  [ -n "$warnings" ] && warnings="$warnings; "
  warnings="$warnings$used% of the $name$when"
done

[ -n "$warnings" ] || exit 0
echo "stint: the user has used $warnings. Update .stint/handoff.md now, before continuing, so the work survives if the limit cuts this chat off. Mention it in one short line."
exit 0
