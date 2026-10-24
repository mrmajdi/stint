#!/usr/bin/env bash
# Tests for install.sh in a throwaway HOME. Run: bash tests/test_install.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
install() { env -i HOME="$tmp/home" PATH="$PATH" bash "$here/install.sh" "$@" >/dev/null; }
blocks() { awk -v b="<!-- stint:begin -->" '$0 == b { n++ } END { print n + 0 }' "$1" 2>/dev/null || echo 0; }

mkdir -p "$tmp/home/.claude" "$tmp/home/.codex" "$tmp/proj"
printf '# My rules\nBe kind.\n' > "$tmp/home/.claude/CLAUDE.md"
git -C "$tmp/proj" init -q 2>/dev/null

install || fail "default install runs"
[ -f "$tmp/home/.claude/skills/stint/SKILL.md" ] && ok "claude skill installed" || fail "claude skill installed"
[ -f "$tmp/home/.claude/skills/stint/scripts/audit.py" ] && ok "audit script ships with the skill" || fail "audit script ships with the skill"
[ "$(blocks "$tmp/home/.claude/CLAUDE.md")" = 1 ] && ok "claude rules added once" || fail "claude rules added once"
grep -q 'Be kind.' "$tmp/home/.claude/CLAUDE.md" && ok "existing CLAUDE.md content kept" || fail "existing CLAUDE.md content kept"
[ -f "$tmp/home/.codex/skills/stint/SKILL.md" ] && [ "$(blocks "$tmp/home/.codex/AGENTS.md")" = 1 ] && ok "codex installed" || fail "codex installed"
[ ! -e "$tmp/home/.gemini" ] && ok "missing agents are skipped" || fail "missing agents are skipped"

install && install
[ "$(blocks "$tmp/home/.claude/CLAUDE.md")" = 1 ] && ok "re-running does not duplicate rules" || fail "re-running does not duplicate rules"
[ "$(grep -c '^$' "$tmp/home/.claude/CLAUDE.md")" -le 3 ] && ok "re-running does not pile up blank lines" || fail "re-running does not pile up blank lines"

install --gemini --project "$tmp/proj" || fail "gemini + project install runs"
[ "$(blocks "$tmp/home/.gemini/GEMINI.md")" = 1 ] && ok "gemini rules added" || fail "gemini rules added"
[ "$(blocks "$tmp/proj/AGENTS.md")" = 1 ] && ok "project AGENTS.md added" || fail "project AGENTS.md added"
head -n 4 "$tmp/proj/.cursor/rules/stint.mdc" | grep -q 'alwaysApply: true' && ok "cursor rule is always-on" || fail "cursor rule is always-on"
grep -qxF '.stint/' "$tmp/proj/.git/info/exclude" && ok ".stint/ kept out of git" || fail ".stint/ kept out of git"

mkdir -p "$tmp/linked" && printf 'mine\n' > "$tmp/dotfile.md" && ln -s "$tmp/dotfile.md" "$tmp/linked/GEMINI.md"
env -i HOME="$tmp/home" PATH="$PATH" GEMINI_DIR="$tmp/linked" bash "$here/install.sh" --gemini >/dev/null
[ -L "$tmp/linked/GEMINI.md" ] && grep -q 'stint:begin' "$tmp/dotfile.md" && grep -q mine "$tmp/dotfile.md" && ok "symlinked dotfile written through" || fail "symlinked dotfile written through"

install --uninstall
install --uninstall --gemini --project "$tmp/proj"
[ ! -e "$tmp/home/.claude/skills/stint" ] && ok "uninstall removes the skill" || fail "uninstall removes the skill"
[ "$(blocks "$tmp/home/.claude/CLAUDE.md")" = 0 ] && grep -q 'Be kind.' "$tmp/home/.claude/CLAUDE.md" && ok "uninstall keeps user content" || fail "uninstall keeps user content"
[ ! -e "$tmp/home/.codex/AGENTS.md" ] && ok "uninstall deletes files it created" || fail "uninstall deletes files it created"
[ ! -e "$tmp/proj/.cursor/rules/stint.mdc" ] && [ ! -e "$tmp/proj/AGENTS.md" ] && ok "project uninstall" || fail "project uninstall"

mkdir -p "$tmp/home/.claude/plugins" && echo '{"plugins":{"stint@stint":[{}]}}' > "$tmp/home/.claude/plugins/installed_plugins.json"
out=$(env -i HOME="$tmp/home" PATH="$PATH" bash "$here/install.sh")
printf '%s' "$out" | grep -q 'plugin is already installed' && [ ! -e "$tmp/home/.claude/skills/stint" ] && ok "plugin users are not double-installed" || fail "plugin users are not double-installed"

env -i HOME="$tmp/home" PATH="$PATH" bash "$here/install.sh" --bogus >/dev/null 2>&1
[ $? = 2 ] && ok "unknown option is rejected" || fail "unknown option is rejected"

[ "$fails" = 0 ] && echo "install: all passed" || { echo "install: $fails failed"; exit 1; }
