#!/usr/bin/env bash
# stint SessionStart hook for Claude Code: give each new chat the standing handoff rule,
# the project's handoff note, and graphify/ponytail hints. Prints plain text; never fails a session.

input=""
IFS= read -r -t 2 -d '' input || true

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
age() {
  local now changed hours days
  now=$(date +%s)
  changed=$(mtime "$1")
  hours=$(( (now - changed) / 3600 ))
  days=$(( hours / 24 ))
  if [ "$hours" -lt 1 ]; then echo "under an hour ago"; elif [ "$hours" -lt 48 ]; then echo "${hours}h ago"; else echo "$days days ago"; fi
}

kind=$(printf '%s' "$input" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
transcript=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
dir=$CLAUDE_PROJECT_DIR
[ -n "$dir" ] || dir=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$dir" ] && cd "$dir" 2>/dev/null
note=.stint/handoff.md
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

echo "stint: for multi-step work, keep .stint/handoff.md current: goal, done, decisions, dead ends, next steps and key files. Overwrite it, at most 60 lines. Update it after each finished subtask or decision, before long-running steps, after a compaction, and as soon as the user is stopping or near a limit: a usage limit can end the chat without warning. When the task is finished, write Status: done in it. Suggest a fresh chat when the topic changes. The stint skill has the format."

if [ -f "$note" ]; then
  if grep -qiE '^status:[[:space:]]*done' "$note"; then
    echo "stint: the last handoff note, $note, is marked done. Do not resume it unless the user asks."
  else
    updated=$(age "$note")
    echo "stint: handoff note from a previous chat: $note, updated $updated. Before anything else, tell the user in one line what you are resuming, then continue from its next steps:"
    head -c 6000 "$note"
    echo
  fi
fi

# A resumed chat re-sends its whole history; past ~150k tokens a fresh chat is far cheaper.
if [ "$kind" = resume ] && [ -f "$transcript" ]; then
  last=$(tail -c 400000 "$transcript" | grep '"usage"' | tail -n 1)
  tokens=$(printf '%s' "$last" | grep -oE '"(input_tokens|cache_read_input_tokens|cache_creation_input_tokens)":[0-9]+' | awk -F: '!seen[$1]++ { sum += $2 } END { print sum + 0 }')
  if [ "$tokens" -ge 150000 ]; then
    thousands=$(( tokens / 1000 ))
    echo "stint: this resumed chat already carries about ${thousands}k tokens of history, and every message re-reads all of it. In your first reply, suggest saving a handoff with /stint save and continuing in a fresh chat."
  fi
fi

if [ -f graphify-out/graph.json ]; then
  echo "stint: this project has a graphify knowledge graph in the graphify-out folder. If the user works with graphify, its query command can answer code questions with fewer file reads."
fi

# Keep a copy of the status line script at a stable path: the plugin folder changes on every update.
if [ -f "$CLAUDE_PLUGIN_ROOT/hooks/limit-watch.sh" ]; then
  mkdir -p "$config/stint" 2>/dev/null && cp "$CLAUDE_PLUGIN_ROOT/hooks/limit-watch.sh" "$config/stint/limit-watch.sh" 2>/dev/null
fi

flag="$config/.ponytail-active"
level=$(head -n 1 "$flag" 2>/dev/null | tr -d '[:space:]')
if [ -f "$flag" ] && [ "$level" != off ]; then
  echo "stint: ponytail is active. List any shortcut comments you add under Next steps in the handoff, so the next chat knows the deferred work."
fi
exit 0
