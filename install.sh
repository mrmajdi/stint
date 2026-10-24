#!/usr/bin/env bash
# stint installer for agents that read instruction files (Codex, Gemini CLI, Cursor and other
# AGENTS.md readers) and for Claude Code without the plugin. Safe to re-run.
# --uninstall removes only what this script added; everything else in those files is kept.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
rules="$here/rules/stint.md"
skill="$here/skills/stint"
begin='<!-- stint:begin -->'
end='<!-- stint:end -->'

claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}
gemini_dir=${GEMINI_DIR:-$HOME/.gemini}

usage() {
  cat <<'EOF'
Usage: ./install.sh [targets] [--uninstall]

Targets (default: every agent found on this machine):
  --claude        Claude Code without the plugin: skill + rules in ~/.claude/CLAUDE.md
  --codex         Codex CLI: skill in ~/.codex/skills + rules in ~/.codex/AGENTS.md
  --gemini        Gemini CLI: rules in ~/.gemini/GEMINI.md
  --project DIR   One repo, for any agent that reads AGENTS.md (Cursor, Copilot, Windsurf,
                  Zed, Aider, Codex...): rules in DIR/AGENTS.md + DIR/.cursor/rules/stint.mdc

  --uninstall     Remove stint from the chosen targets
  -h, --help      Show this help

For Claude Code, the plugin is the better install: it adds a start-of-chat hook.
  /plugin marketplace add mrmajdi/stint
  /plugin install stint@stint
EOF
}

say() { printf '  %s\n' "$*"; }

# Print FILE without the stint block and without trailing blank lines.
without_block() {
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { lines[++n] = $0 }
    END     { while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }
  ' "$1"
}

# Write through `cat >` rather than mv, so a symlinked dotfile keeps pointing where it did.
add_block() {
  local file=$1 body
  mkdir -p "$(dirname "$file")"
  body=$([ -f "$file" ] && without_block "$file" || true)
  { [ -n "$body" ] && printf '%s\n\n' "$body"; printf '%s\n' "$begin"; cat "$rules"; printf '%s\n' "$end"; } > "$file.stint.tmp"
  cat "$file.stint.tmp" > "$file" && rm -f "$file.stint.tmp"
  say "rules  -> $file"
}

remove_block() {
  local file=$1 body
  [ -f "$file" ] && grep -qxF "$begin" "$file" || return 0
  body=$(without_block "$file")
  if [ -n "$body" ]; then printf '%s\n' "$body" > "$file.stint.tmp" && cat "$file.stint.tmp" > "$file" && rm -f "$file.stint.tmp"
  else rm -f "$file"; fi
  say "removed rules from $file"
}

add_skill() {
  mkdir -p "$1"
  rm -rf "$1/stint"
  cp -R "$skill" "$1/stint"
  say "skill  -> $1/stint"
}

remove_skill() {
  [ -d "$1/stint" ] || return 0
  rm -rf "$1/stint"
  say "removed skill $1/stint"
}

cursor_rule() {
  printf '%s\n' '---' 'description: stint handoff notes between chats' 'alwaysApply: true' '---' ''
  cat "$rules"
}

exclude_note_dir() {  # keep .stint/ out of commits without touching tracked files
  local f
  f=$(git -C "$1" rev-parse --git-path info/exclude 2>/dev/null) || return 0
  case $f in /*) ;; *) f="$1/$f" ;; esac
  grep -qxF '.stint/' "$f" 2>/dev/null || { mkdir -p "$(dirname "$f")"; echo '.stint/' >> "$f"; say "git    -> .stint/ added to $f"; }
}

plugin_installed() { grep -qs '"stint@' "$claude_dir/plugins/installed_plugins.json"; }

uninstall=0 any=0 do_claude=0 do_codex=0 do_gemini=0 project=""
while [ $# -gt 0 ]; do
  case $1 in
    --claude) do_claude=1 any=1 ;;
    --codex) do_codex=1 any=1 ;;
    --gemini) do_gemini=1 any=1 ;;
    --project) [ $# -ge 2 ] || { usage; exit 2; }; project=$2; any=1; shift ;;
    --uninstall) uninstall=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [ "$any" = 0 ]; then
  [ -d "$claude_dir" ] && do_claude=1
  [ -d "$codex_dir" ] && do_codex=1
  [ -d "$gemini_dir" ] && do_gemini=1
  if [ "$uninstall" = 0 ] && [ "$do_claude" = 1 ] && plugin_installed; then
    say "Claude Code: the stint plugin is already installed, skipping (it covers everything)"
    do_claude=0
  fi
  if [ "$do_claude$do_codex$do_gemini" = 000 ]; then
    echo "No Claude Code, Codex or Gemini CLI config found. Use --project DIR for a single repo."
    exit 1
  fi
fi

if [ -n "$project" ]; then
  [ -d "$project" ] || { echo "not a directory: $project" >&2; exit 2; }
  project=$(cd "$project" && pwd)
fi

echo "stint: $([ "$uninstall" = 1 ] && echo uninstalling || echo installing)"
if [ "$uninstall" = 0 ]; then
  [ "$do_claude" = 1 ] && { add_skill "$claude_dir/skills"; add_block "$claude_dir/CLAUDE.md"; }
  [ "$do_codex" = 1 ] && { add_skill "$codex_dir/skills"; add_block "$codex_dir/AGENTS.md"; }
  [ "$do_gemini" = 1 ] && add_block "$gemini_dir/GEMINI.md"
  if [ -n "$project" ]; then
    add_block "$project/AGENTS.md"
    mkdir -p "$project/.cursor/rules"
    cursor_rule > "$project/.cursor/rules/stint.mdc"
    say "rules  -> $project/.cursor/rules/stint.mdc"
    exclude_note_dir "$project"
  fi
  echo "Done. Start a new chat; work is handed off through .stint/handoff.md in each project."
else
  [ "$do_claude" = 1 ] && { remove_skill "$claude_dir/skills"; remove_block "$claude_dir/CLAUDE.md"; }
  [ "$do_codex" = 1 ] && { remove_skill "$codex_dir/skills"; remove_block "$codex_dir/AGENTS.md"; }
  [ "$do_gemini" = 1 ] && remove_block "$gemini_dir/GEMINI.md"
  if [ -n "$project" ]; then
    remove_block "$project/AGENTS.md"
    [ -f "$project/.cursor/rules/stint.mdc" ] && rm -f "$project/.cursor/rules/stint.mdc" && say "removed $project/.cursor/rules/stint.mdc"
  fi
  echo "Done. Handoff notes in .stint/ folders were left in place."
fi
