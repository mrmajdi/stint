#!/usr/bin/env bash
# stint status line for Claude Code: shows context and usage-limit levels, and saves the
# limit levels so the limit-watch hook can warn the agent before a limit cuts the chat off.
# Claude Code only gives usage limits to the status line (Pro/Max, after the first reply).

json=$(tr -d '\n')
num() { printf '%s' "$json" | sed -n "s/.*\"$1\"[^}]*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p" | head -n 1; }

five=$(num five_hour used_percentage)
week=$(num seven_day used_percentage)
five_reset=$(num five_hour resets_at)
week_reset=$(num seven_day resets_at)
context=$(num context_window used_percentage)

if [ -n "$five$week" ]; then
  state="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/stint"
  mkdir -p "$state" 2>/dev/null
  printf 'five_hour=%s\nseven_day=%s\nfive_hour_resets=%s\nseven_day_resets=%s\nupdated=%s\n' \
    "${five%.*}" "${week%.*}" "${five_reset%.*}" "${week_reset%.*}" "$(date +%s)" > "$state/limits.tmp" 2>/dev/null \
    && mv "$state/limits.tmp" "$state/limits" 2>/dev/null
fi

line="stint"
[ -n "$context" ] && line="$line · context ${context%.*}%"
[ -n "$five" ] && line="$line · 5h ${five%.*}%"
[ -n "$week" ] && line="$line · week ${week%.*}%"
printf '%s\n' "$line"
