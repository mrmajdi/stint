## stint: short chats, handoff notes

Long chats are re-read on every message, and resuming one after a break re-sends the whole history at once. Keep chats short and carry the state of the work in `.stint/handoff.md` instead.

- **Starting a chat:** if `.stint/handoff.md` exists and is not `Status: done`, read it first, say in one line what you are resuming, and continue from its Next steps.
- **While working** on multi-step tasks, keep the note current (overwrite it, at most 60 lines) with a `Status:` line and the sections Goal, Done, Decisions (with why), Dead ends, Next steps, Key files and commands. Update it after each finished subtask or decision, before long-running steps, after a compaction, and as soon as the user is stopping or near a limit. Don't wait for the end: a usage limit can cut the chat off.
- **Finished:** set `Status: done`.
- **First save in a git repo:** keep the note out of commits with `f=$(git rev-parse --git-path info/exclude) && { grep -qxF '.stint/' "$f" || echo '.stint/' >> "$f"; }`.
- Suggest a fresh chat when the topic changes or when the user comes back to a long chat after a break.
- If `graphify-out/graph.json` exists, run `graphify update .` and query the graph before reading files.
- Never put secrets in the note.
