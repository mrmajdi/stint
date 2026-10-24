<div align="center">

<img src="assets/banner.svg" alt="stint: work in short stints, not marathon chats. About half the usage for the same work. Claude Code, Codex, Gemini CLI, Cursor." width="100%">

<br>

[![Tests](https://img.shields.io/github/actions/workflow/status/mrmajdi/stint/ci.yml?branch=main&style=flat-square&label=tests)](https://github.com/mrmajdi/stint/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757?style=flat-square)](#claude-code)
[![Also for](https://img.shields.io/badge/also%20for-Codex%20%C2%B7%20Gemini%20CLI%20%C2%B7%20Cursor-555?style=flat-square)](#other-agents)
[![Dependencies: none](https://img.shields.io/badge/dependencies-none-3fb950?style=flat-square)](#privacy)

**[Install](#install)** · **[How it works](#how-stint-works)** · **[Commands](#use)** · **[Audit](#the-audit)** · **[FAQ](#faq)**

</div>

<br>

AI coding agents re-read the whole chat on every message. Long chats get expensive fast. **stint keeps chats short.** It saves the state of your work in a small note. Each new chat starts from that note, not from a huge history.

<p align="center">
  <img src="assets/before-after.svg" alt="Before and after: usage for the same work 100% to 47%. Median chat history per message 411k to 97k tokens. Biggest single cache write 928k to 136k tokens." width="860">
</p>

> [!NOTE]
> These numbers come from replaying 30 days of real Claude Code logs from one developer (the author). They are an estimate, not a promise. Run `/stint audit` to see your own numbers.

## What you get

<table>
<tr>
<td width="50%" valign="top">

### 📝 A handoff note

The agent keeps a short note in `.stint/handoff.md`: goal, what is done, decisions, dead ends and next steps. It saves **while it works**, not only at the end.

</td>
<td width="50%" valign="top">

### 🔁 Fresh chats that remember

A new chat gets the note at once. The agent says what it is resuming and continues. You do not explain the task again.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### ⚠️ Usage limit warnings

At **80%, 90% and 95%** of your 5-hour or weekly limit, the agent saves the note before the limit can stop the chat.

</td>
<td width="50%" valign="top">

### 📊 A usage audit

`/stint audit` reads your local logs. It shows where your usage goes and how much stint could save **for you**.

</td>
</tr>
</table>

## The problem

Your usage limit does not go to your questions or to the code the agent writes. It goes to the **chat history**.

1. **Every message re-sends the whole chat.** In a 400k-token chat, the history part of each message costs 10 times more than in a 40k-token chat.
2. **Coming back after a break is worse.** Claude Code keeps the chat history in a cache: for one hour on a Claude subscription, for five minutes with an API key. After that, your next message writes the whole history into the cache again. One message can use a big part of your 5-hour limit at once.
3. **You cannot see it happen.** The agent cannot see your usage meter either. When the limit stops the chat, your work state is lost.

<p align="center">
  <img src="assets/where-it-goes.svg" alt="Where 30 days of Claude Code usage went: re-reading chat history 70%, re-caching chat history 19%, writing answers 7%, thinking 4%." width="860">
</p>

The same 30-day audit also found:

- **88%** of the usage was spent while the chat was over 200k tokens.
- One "welcome back" message after a break re-cached up to **928k tokens**.

> [!TIP]
> Most token-saving tools make the agent write less, or shorten tool output. Here that was only about **11%** of the usage. stint works on the other **89%**.

## How stint works

<p align="center">
  <img src="assets/how-it-works.svg" alt="How stint works: chat 1 saves the handoff note while it works. Chat 2 loads the note at the start. A usage limit warning at 80, 90 or 95 percent tells the agent to save the note now." width="1000">
</p>

1. **The handoff note.** The agent keeps `.stint/handoff.md` up to date while it works.
2. **The start-of-chat hook.** Every new chat gets the note at once and continues from its next steps.
3. **Usage limit warnings.** When your 5-hour or weekly limit passes 80%, 90% or 95%, the agent is told to save the note.
4. **The audit.** `/stint audit` shows where your usage goes, with a before-and-after estimate for your own habits.

The note is a plain file in your project. Codex, Gemini CLI and Cursor can read it too. If you hit your Claude limit, you can continue the same task in another agent.

## Install

### Claude Code

Install the plugin. This is the best way, because it includes the hooks.

```text
/plugin marketplace add mrmajdi/stint
/plugin install stint@stint
```

Start a new chat. stint is active.

> [!TIP]
> **Turn on usage limit warnings (optional).** Claude Code only shares your usage-limit numbers with the status line. Add this to `~/.claude/settings.json`:
>
> ```json
> "statusLine": { "type": "command", "command": "bash ~/.claude/stint/statusline.sh" }
> ```
>
> The status line then shows `stint · context 34% · 5h 61% · week 42%`. This needs a Pro or Max plan. The script is copied to `~/.claude/stint/` each time a chat starts, so the path keeps working after plugin updates.

### Other agents

```bash
git clone https://github.com/mrmajdi/stint.git
cd stint
./install.sh                          # every agent found on this computer
./install.sh --project ~/code/my-app  # one project: AGENTS.md + Cursor rule
```

| Option | What it installs |
|---|---|
| `--codex` | Skill in `~/.codex/skills/stint` and rules in `~/.codex/AGENTS.md` |
| `--gemini` | Rules in `~/.gemini/GEMINI.md` |
| `--project DIR` | Rules in `DIR/AGENTS.md` and `DIR/.cursor/rules/stint.mdc`. Works for Cursor, Copilot, Windsurf, Zed, Aider and other agents that read `AGENTS.md`. |
| `--claude` | Claude Code without the plugin: skill and rules only, no hooks |
| `--uninstall` | Removes stint from the chosen targets. Your own text in those files stays. |

The installer is safe to run again. It only changes the text between `<!-- stint:begin -->` and `<!-- stint:end -->`.

## Use

Most of the time you do nothing. The agent saves the note while it works, and a new chat picks it up.

| Command | What it does |
|---|---|
| `/stint save` | Save the handoff note now. Use it before you stop. |
| `/stint` or `/stint status` | Show the note, and tell you if a fresh chat would be cheaper. |
| `/stint resume` | Read the note and continue. A new chat does this by itself. |
| `/stint done` | Mark the task as finished, so no chat resumes it. |
| `/stint audit` | Show where your usage goes, with a before-and-after estimate. |

In agents without slash commands, just write it: *"stint save"*, *"stint audit"*.

### A normal day

1. Open a chat and work. The agent keeps `.stint/handoff.md` up to date.
2. The task changes, or the chat gets long? Start a new chat.
3. Coming back after lunch, or after your limit resets? Start a **new** chat. Do not continue the old one.
4. The new chat reads the note and says, for example: *"Resuming: password reset form, next is the email step."*

### The audit

<p align="center">
  <img src="assets/audit.svg" alt="Sample /stint audit output: where usage went (history reads 70%, history writes 19%, writing 7%, thinking 4%), 88% of usage in chats over 200k tokens, 14 comebacks, before and after (usage 100% to 47%), and what to change." width="900">
</p>

You can also run it directly: `python3 skills/stint/scripts/audit.py --days 7`.

<details>
<summary><b>How the estimate works</b></summary>

<br>

The audit replays your real logs. The replies and tool output stay the same. Only the history changes:

- A fresh chat starts when the history passes 150k tokens (`--cap`), or when you come back after 60 minutes or more.
- Each fresh chat also pays for writing the note and for re-reading 20k tokens of files.
- Shares use public API price ratios, because Anthropic does not publish how plan limits count each token type.
- If a handoff would cost more than it saves, the audit shows that too.

</details>

## The handoff note

The note lives in `.stint/handoff.md` in your project. It has at most 60 lines.

```markdown
# Handoff: password reset
Status: in progress
Updated: 2026-10-24 14:05 by claude-code

## Goal
Users can reset their password by email. Check: `npm test -- reset` passes.

## Done
- Reset token table and API route (`src/api/reset.ts`, tests pass)

## Decisions
- Tokens expire after 30 minutes: security review asked for it

## Dead ends
- Sending email from the API route: too slow, moved to the job queue

## Next steps
1. Write the email job in `src/jobs/reset-email.ts`

## Key files and commands
- `src/api/reset.ts`: reset API
- `npm test -- reset`: reset tests
```

- The agent **overwrites** the note. It does not grow.
- On the first save, stint adds `.stint/` to `.git/info/exclude`. The note stays out of your commits, and your `.gitignore` is not changed. If your team wants to share notes, commit them.
- The agent never writes secrets into the note.

## Usage limit warnings

<p align="center">
  <img src="assets/limit-warning.svg" alt="Usage limits panel: 5-hour window 83%, weekly 47%. stint tells the agent: you have used 83% of the 5-hour window, update .stint/handoff.md now. The agent saves the note first." width="1000">
</p>

Claude Code gives usage-limit numbers to the status line only. Hooks do not get them. stint uses both:

1. The stint status line saves your 5-hour and weekly levels to `~/.claude/stint/limits`.
2. Before each of your messages, a small hook reads that file. When a window passes **80%, 90% or 95%**, the agent gets one short message: save the note now.

Each level warns only once per chat. Numbers older than 20 minutes are ignored. The weekly limit is watched the same way as the 5-hour window.

> [!IMPORTANT]
> Limit warnings need a Claude Pro or Max plan and the stint status line ([see Install](#claude-code)). They work in the Claude Code terminal app. If your Claude Code app does not run custom status lines, the warnings stay off. Everything else still works.

## Works with graphify and ponytail

stint works alone. If you also use these tools, it uses them:

| Tool | What stint does with it |
|---|---|
| [graphify](https://github.com/Graphify-Labs/graphify) | When the project has a graph, a new chat runs `graphify update .` and asks the graph first, instead of reading many files again. |
| [ponytail](https://github.com/DietrichGebert/ponytail) | When ponytail is active, the note lists the `shortcut:` comments the agent added, so the next chat knows the deferred work. |

## Supported agents

| Agent | Install | Start-of-chat check | Limit warnings | Tested |
|---|---|---|---|---|
| **Claude Code** | plugin | ✅ hook, automatic | ✅ with the status line | ✅ live sessions |
| Claude Code | `install.sh --claude` | rule in `CLAUDE.md` | — | 🧪 installer |
| **Codex CLI** | `install.sh --codex` | rule in `AGENTS.md` | — | 🧪 installer |
| **Gemini CLI** | `install.sh --gemini` | rule in `GEMINI.md` | — | 🧪 installer |
| **Cursor** | `install.sh --project` | always-on rule | — | 🧪 installer |
| Copilot, Windsurf, Zed, Aider, others | `install.sh --project` | rule in `AGENTS.md` | — | 🧪 installer |

🧪 means the tests check every file the installer writes. The behavior depends on the agent following its instruction file. Reports and fixes are welcome.

## Recommended settings

These are Claude Code settings. stint works without them, but they help.

- **Compact earlier.** Add `"autoCompactWindow": 300000` to `~/.claude/settings.json`. By default, Opus chats can grow to about 1M tokens before they compact.
- **Give `/goal` an end.** `/goal` keeps working until its condition is true. A vague goal can run for hundreds of turns. Write a check and a limit: `/goal tests in tests/api pass, or stop after 20 turns`.
- **Use a cheaper model for simple work.** Writing plans, emails and documents does not need Opus. Try `/model sonnet`.

> [!WARNING]
> **Do not lower the effort level to save usage.** In the audit above, thinking was only 4% of the usage. Lower effort costs quality and saves little. Short chats save much more.

## Privacy

- 🔒 stint runs only on your computer. It sends nothing over the network. There is no telemetry.
- 📦 There are no dependencies. stint uses only `bash` and `python3`.
- 🙈 The audit reads `~/.claude/projects/` and prints totals only. It never prints your prompts or code.
- 📁 Files stint writes: `.stint/handoff.md` in your projects, `~/.claude/stint/` (status line copy and limit levels), and the instruction files you choose during install.

## FAQ

<details>
<summary><b>Does a fresh chat lose context?</b></summary>

<br>

The note keeps what matters: goal, decisions, dead ends and next steps. Very long chats also make the agent less focused. A fresh chat with a clear note often works better.

</details>

<details>
<summary><b>Why not just use <code>/compact</code>?</b></summary>

<br>

Compaction is useful, and stint saves the note after it. But compaction happens late, and its summary is made automatically. It also does not help when you come back after a break and the cache has expired. A note and a fresh chat avoid both problems.

</details>

<details>
<summary><b>Does the agent know my usage?</b></summary>

<br>

Not by itself. That is why stint saves the note during the work, and why the limit warnings use the status line.

</details>

<details>
<summary><b>I already have a status line. Can I keep it?</b></summary>

<br>

Yes. Send the same input to both scripts, for example:

```json
"command": "bash -c 'in=$(cat); printf %s \"$in\" | bash ~/.claude/stint/statusline.sh >/dev/null; printf %s \"$in\" | your-status-line-command'"
```

</details>

<details>
<summary><b>Does it work on Windows?</b></summary>

<br>

It needs `bash`, so use WSL or Git Bash. Native PowerShell support is on the roadmap.

</details>

## Uninstall

- **Plugin:** `/plugin uninstall stint@stint`, then remove the `statusLine` entry if you added it.
- **Installer:** `./install.sh --uninstall` (add the same options you used to install).
- Handoff notes in `.stint/` folders are yours. stint never deletes them.

## Development

```bash
bash tests/run.sh   # hook, installer and audit tests
```

<details>
<summary><b>Project layout</b></summary>

<br>

```text
.claude-plugin/        plugin and marketplace manifests
hooks/                 session-start, limit-watch and status line scripts
skills/stint/          the skill, and scripts/audit.py
rules/stint.md         the always-on rules used by install.sh
install.sh             installer for other agents
assets/                README images
tests/                 test suites (bash and Python unittest)
```

</details>

CI runs the tests on Linux and macOS, and runs ShellCheck on every script.

### Roadmap

- [ ] Native hooks for Codex, Gemini CLI and Cursor
- [ ] Audit support for Codex and Gemini logs
- [ ] PowerShell version for Windows
- [ ] Notes per branch, for parallel work in git worktrees
- [ ] A real before-and-after study with more users

Ideas and pull requests are welcome. Please keep the tool small and free of dependencies.

## Credits

stint grew out of a long session of measuring real Claude Code usage. It learned from [graphify](https://github.com/Graphify-Labs/graphify), [ponytail](https://github.com/DietrichGebert/ponytail), [ccusage](https://github.com/ccusage/ccusage) and the [Claude Code docs](https://code.claude.com/docs).

## License

[MIT](LICENSE) © 2026 mrmajdi

<div align="center">
<br>
<sub>If stint saves you usage, a ⭐ helps other people find it.</sub>
</div>
