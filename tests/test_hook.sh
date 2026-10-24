#!/usr/bin/env bash
# Tests for hooks/session-start.sh. Run: bash tests/test_hook.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
hook="$here/hooks/session-start.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {  # check NAME OUTPUT PATTERN [absent]
  if [ "${4:-}" = absent ]; then
    printf '%s' "$2" | grep -qF -- "$3" && { echo "FAIL $1: unexpected '$3'"; fails=$((fails + 1)); return; }
  else
    printf '%s' "$2" | grep -qF -- "$3" || { echo "FAIL $1: missing '$3'"; fails=$((fails + 1)); return; }
  fi
  echo "ok   $1"
}

run() {  # run PROJECT_DIR STDIN_JSON [extra env...]
  local dir=$1 json=$2; shift 2
  printf '%s' "$json" | env -i HOME="$tmp/home" PATH=/usr/bin:/bin CLAUDE_PROJECT_DIR="$dir" "$@" bash "$hook"
}

mkdir -p "$tmp/home/.claude" "$tmp/empty" "$tmp/active/.stint" "$tmp/finished/.stint" "$tmp/graph/graphify-out"

out=$(run "$tmp/empty" '{"source":"startup"}'); code=$?
check "always exits 0" "$code" "0"
check "standing rule is always given" "$out" "keep .stint/handoff.md current"
check "no note, no resume line" "$out" "handoff note from a previous chat" absent

printf '# Handoff: auth\nStatus: in progress\n\n## Next steps\n1. fix "token" refresh\n' > "$tmp/active/.stint/handoff.md"
out=$(run "$tmp/active" '{"source":"startup"}')
check "open note is handed over" "$out" "handoff note from a previous chat"
check "note content is included" "$out" 'fix "token" refresh'

printf '# Handoff: auth\nStatus: done\n' > "$tmp/finished/.stint/handoff.md"
out=$(run "$tmp/finished" '{"source":"clear"}')
check "done note is not resumed" "$out" "is marked done"
check "done note content is not injected" "$out" "Before anything else" absent

big="$tmp/big.jsonl"
printf '{"type":"assistant","message":{"usage":{"input_tokens":3,"cache_read_input_tokens":410000,"cache_creation_input_tokens":2000}}}\n' > "$big"
out=$(run "$tmp/empty" "{\"source\":\"resume\",\"transcript_path\":\"$big\"}")
check "resuming a huge chat suggests a fresh one" "$out" "about 412k tokens"
out=$(run "$tmp/empty" "{\"source\":\"startup\",\"transcript_path\":\"$big\"}")
check "fresh start gets no size warning" "$out" "tokens of history" absent

small="$tmp/small.jsonl"
printf '{"type":"assistant","message":{"usage":{"input_tokens":3,"cache_read_input_tokens":20000}}}\n' > "$small"
out=$(run "$tmp/empty" "{\"source\":\"resume\",\"transcript_path\":\"$small\"}")
check "resuming a small chat gets no warning" "$out" "tokens of history" absent

echo '{}' > "$tmp/graph/graphify-out/graph.json"
out=$(run "$tmp/graph" '{"source":"startup"}')
check "a graphify graph is mentioned" "$out" "graphify knowledge graph"
out=$(run "$tmp/empty" '{"source":"startup"}')
check "no graph, no graphify line" "$out" "graphify" absent

out=$(cd "$tmp/active" && printf '{"source":"startup"}' | env -i HOME="$tmp/home" PATH=/usr/bin:/bin bash "$hook")
check "without a project dir, the current folder is used" "$out" "handoff note from a previous chat"
run "$tmp/empty" '{"source":"startup"}' CLAUDE_PLUGIN_ROOT="$here" >/dev/null
[ -f "$tmp/home/.claude/stint/limit-watch.sh" ] && check "status line copied to a stable path" "yes" "yes" || check "status line copied to a stable path" "no" "yes"

echo full > "$tmp/home/.claude/.ponytail-active"
out=$(run "$tmp/empty" '{"source":"startup"}')
check "active ponytail is noted" "$out" "ponytail is active"
echo off > "$tmp/home/.claude/.ponytail-active"
out=$(run "$tmp/empty" '{"source":"startup"}')
check "ponytail off is ignored" "$out" "ponytail is active" absent

out=$(run "$tmp/empty" '')
check "empty stdin still works" "$out" "keep .stint/handoff.md current"

limits() { env -i HOME="$tmp/home" PATH=/usr/bin:/bin bash "$here/hooks/limit-watch.sh" "$@"; }
out=$(printf '{"context_window":{"used_percentage":41.7},"rate_limits":{"five_hour":{"used_percentage":83.2,"resets_at":1761300000},"seven_day":{"used_percentage":47.9}}}' | limits status)
check "status line shows context and limits" "$out" "context 41% · 5h 83% · week 47%"
out=$(printf '{"session_id":"s1"}' | limits)
check "crossing 80% warns the agent" "$out" "83% of the 5-hour window, resets at"
out=$(printf '{"session_id":"s1"}' | limits)
check "same level warns only once" "$out" "stint:" absent
printf '{"rate_limits":{"five_hour":{"used_percentage":96}}}' | limits status >/dev/null
out=$(printf '{"session_id":"s1"}' | limits)
check "crossing 95% warns again" "$out" "96% of the 5-hour window"
out=$(printf '{"session_id":"s2"}' | limits)
check "a new chat gets its own warning" "$out" "96% of the 5-hour window"
sed -i.bak 's/^updated=.*/updated=1/' "$tmp/home/.claude/stint/limits"
out=$(printf '{"session_id":"s3"}' | limits)
check "stale numbers are ignored" "$out" "stint:" absent
out=$(printf '{"context_window":{"used_percentage":5}}' | limits status)
check "status line works without limit data" "$out" "context 5%"
printf '{"rate_limits":{"five_hour":{"used_percentage":30},"seven_day":{"used_percentage":91,"resets_at":1761800000}}}' | limits status >/dev/null
out=$(printf '{"session_id":"w1"}' | limits)
check "weekly limit warns on its own" "$out" "91% of the weekly limit, resets"
check "weekly warning skips a calm 5-hour window" "$out" "5-hour" absent
printf '{"rate_limits":{"five_hour":{"used_percentage":85},"seven_day":{"used_percentage":92}}}' | limits status >/dev/null
out=$(printf '{"session_id":"w1"}' | limits)
check "5-hour warning still comes after a weekly one" "$out" "85% of the 5-hour window"
check "weekly level already warned is not repeated" "$out" "weekly" absent

[ "$fails" = 0 ] && echo "hook: all passed" || { echo "hook: $fails failed"; exit 1; }
