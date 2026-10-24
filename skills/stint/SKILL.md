---
name: stint
description: Keep AI coding chats short and cheap by handing work off between chats through a small note. Use when the user wants to save progress, resume earlier work, start a fresh chat, says they are stopping or close to a usage limit, switches to an unrelated topic, or asks why their Claude usage runs out fast. Actions - save, resume, done, audit, status.
argument-hint: "[save|resume|done|audit|status]"
license: MIT
---

# stint

Every message re-reads the whole chat, and coming back to a long chat after a break re-sends all of it at once. stint keeps chats short: the state of the work lives in a small handoff note, `.stint/handoff.md` in the project root, and each new chat starts from that note instead of from a giant history.

Requested action: $ARGUMENTS

## Actions

**save**: write `.stint/handoff.md` in the format below. Overwrite it; never append. On the first save in a git repo, keep the note out of commits without touching tracked files:

```bash
f=$(git rev-parse --git-path info/exclude 2>/dev/null) && { grep -qxF '.stint/' "$f" 2>/dev/null || echo '.stint/' >> "$f"; }
```

Then answer in one line: the path, and that a new chat will pick it up.

**resume**: read `.stint/handoff.md`. If it is marked done, say so and ask what's next. Otherwise tell the user in one line what you are resuming and continue from Next steps. Check a "done" claim cheaply (run the test or open the file the note names) before building on it; don't re-explore the whole project.

**done**: set `Status: done` and replace Next steps with a one-line outcome.

**audit**: run `python3 scripts/audit.py` from this skill's directory (`--days 7` for the last week). Summarize the top findings and what to change in a few lines; don't paste the full report back.

**status** (or no action): say whether a note exists, its status and age, and whether this chat is long enough that a fresh one would be cheaper.

## Save without being asked

For multi-step work (not quick questions), keep the note current:

- after a subtask finishes or a decision is made,
- before a long-running step,
- right after a compaction,
- as soon as the user says they are stopping, leaving, or near a limit.

Don't wait for the end. You can't see the user's usage meter, and a limit can end the chat with no chance to save.

Suggest a fresh chat when the topic changes, or when the user comes back to a long chat after a break.

## Handoff format

At most 60 lines. Facts a fresh chat can act on, not the story of the session.

```markdown
# Handoff: <task in a few words>
Status: in progress
Updated: <YYYY-MM-DD HH:MM> by <agent>

## Goal
<one or two lines, plus the acceptance check if there is one>

## Done
- <finished item> (<file or command that proves it>)

## Decisions
- <decision>: <why>

## Dead ends
- <what was tried and why it failed, so nobody retries it>

## Next steps
1. <the very next action, concrete enough to start immediately>

## Key files and commands
- `<path>`: <role>
- `<command>`: <what it checks>
```

Never write secrets, tokens or passwords into the note.

## With graphify and ponytail

- **graphify** (`graphify-out/graph.json` exists and the user works with graphify): prefer `graphify query` or `graphify path` over reading many files, and run `graphify update .` after big code changes. Name nodes and files in the note; don't paste graph output into it.
- **ponytail** active: list any `shortcut:` comments you added under Next steps, so the next chat knows the deferred work.

Neither is required. Without them, stint works the same.
