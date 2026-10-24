# Changelog

All notable changes to stint are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Hooks are called by their path and written in plain shell, for the Claude plugin directory checks.
- The status line is now part of `hooks/limit-watch.sh`. Use `bash ~/.claude/stint/limit-watch.sh status` as the `statusLine` command. The old `~/.claude/stint/statusline.sh` copy keeps working, but it is no longer updated.
- The graphify hint only says that a graph exists. The agent is not told to run graphify.
- README: graphify setup steps, troubleshooting, support and security contact, and install steps for the VS Code extension.
- Plugin listing icon.

## [0.1.0] - 2026-10-24

### Added

- `stint` skill with the actions `save`, `resume`, `done`, `audit` and `status`.
- Handoff note format in `.stint/handoff.md`, kept out of git through `.git/info/exclude`.
- Claude Code plugin with two hooks:
  - `SessionStart` gives each new chat the handoff note, the standing rules, and graphify and ponytail hints. It also warns when a resumed chat is already large.
  - `UserPromptSubmit` warns the agent once when the 5-hour or the weekly usage window passes 80, 90 or 95 percent.
- Status line script that shows context and usage-limit levels and saves them for the warning hook.
- `audit.py`: a usage report from local Claude Code transcripts, with a before and after replay.
- `install.sh` for Claude Code without the plugin, Codex CLI, Gemini CLI, and any project that uses `AGENTS.md` or Cursor rules.
- Test suites for the hooks, the installer and the audit, plus CI on Linux and macOS.

[0.1.0]: https://github.com/mrmajdi/stint/releases/tag/v0.1.0
