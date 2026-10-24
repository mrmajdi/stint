#!/usr/bin/env python3
"""stint audit: where your Claude Code usage actually goes.

Reads the transcripts Claude Code keeps on this machine (~/.claude/projects) and
prints aggregates only. Nothing is sent anywhere. Python 3.9+, standard library only.
"""
import argparse
import datetime as dt
import glob
import json
import os
import statistics
from collections import Counter, defaultdict

# Relative cost of each token type, from public Claude API price ratios.
# Anthropic does not publish how plan limits weigh tokens, so treat every share as an estimate.
WEIGHTS = {"input": 1.0, "output": 5.0, "cache_read": 0.1, "cache_write_5m": 1.25, "cache_write_1h": 2.0}
LONG_CONTEXT = 200_000     # history size where every message gets expensive
SPIKE_TOKENS = 150_000     # history re-cached in a single call
IDLE_MINUTES = 60          # gap after which the prompt cache has usually expired
GOAL_CLEAR = {"clear", "stop", "off", "reset", "none", "cancel"}
BUCKETS = [("< 50k", 50_000), ("50-100k", 100_000), ("100-200k", 200_000), ("> 200k", float("inf"))]


def parse_time(value):
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def cost(usage):
    """Weighted cost of one model call, split by token type."""
    cache = usage.get("cache_creation") or {}
    write_1h = cache.get("ephemeral_1h_input_tokens") or 0
    write_5m = cache.get("ephemeral_5m_input_tokens") or 0
    if not cache:
        write_5m = usage.get("cache_creation_input_tokens") or 0
    output = usage.get("output_tokens") or 0
    thinking = min((usage.get("output_tokens_details") or {}).get("thinking_tokens") or 0, output)
    parts = {
        "history reads": WEIGHTS["cache_read"] * (usage.get("cache_read_input_tokens") or 0),
        "history writes": WEIGHTS["cache_write_5m"] * write_5m + WEIGHTS["cache_write_1h"] * write_1h,
        "new input": WEIGHTS["input"] * (usage.get("input_tokens") or 0),
        "writing": WEIGHTS["output"] * (output - thinking),
        "thinking": WEIGHTS["output"] * thinking,
    }
    return parts


def goal_command(record):
    """Return ('set'|'clear', time) for a /goal command record, else None."""
    content = (record.get("message") or {}).get("content")
    text = content if isinstance(content, str) else json.dumps(content or "")
    if "<command-name>/goal</command-name>" in text:
        start = text.find("<command-args>")
        stop = text.find("</command-args>")
        args = text[start + 14:stop].strip() if start >= 0 and stop > start else ""
        if not args:
            return None
        return ("clear" if args.split()[0].lower() in GOAL_CLEAR else "set"), parse_time(record.get("timestamp"))
    if "Goal cleared" in text and record.get("type") == "system":
        return "clear", parse_time(record.get("timestamp"))
    return None


def read_transcripts(root, since):
    """Yield one dict per model call made since `since`."""
    seen = set()
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        calls, goals = [], []
        is_subagent_file = os.sep + "subagents" + os.sep in path
        try:
            handle = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with handle:
            for line in handle:
                if '"usage"' not in line and "/goal" not in line and "Goal cleared" not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                command = goal_command(record)
                if command and command[1]:
                    goals.append(command)
                message = record.get("message") or {}
                usage = message.get("usage")
                if record.get("type") != "assistant" or not usage or message.get("model") == "<synthetic>":
                    continue  # "<synthetic>" marks messages Claude Code made locally, not model calls
                key = (message.get("id"), record.get("requestId"))
                if key in seen:
                    continue
                seen.add(key)
                when = parse_time(record.get("timestamp"))
                if when is None:
                    continue
                calls.append({
                    "time": when,
                    "parts": cost(usage),
                    "context": (usage.get("input_tokens") or 0) + (usage.get("cache_read_input_tokens") or 0)
                    + (usage.get("cache_creation_input_tokens") or 0),
                    "rewrite": usage.get("cache_creation_input_tokens") or 0,
                    "output": usage.get("output_tokens") or 0,
                    "input": usage.get("input_tokens") or 0,
                    "model": message.get("model") or "?",
                    "subagent": bool(record.get("isSidechain")) or is_subagent_file,
                    "chat": record.get("sessionId") or path,
                    "project": os.path.basename(record.get("cwd") or "") or "?",
                })
        calls.sort(key=lambda c: c["time"])
        goals.sort(key=lambda g: g[1])
        previous = None
        for call in calls:
            call["idle"] = (call["time"] - previous).total_seconds() / 60 if previous else None
            if not call["subagent"]:
                previous = call["time"]
            state = None
            for kind, when in goals:
                if when <= call["time"]:
                    state = kind
            call["goal"] = state == "set"
            if call["time"] >= since:
                yield call


def replay(chat, cap, note_tokens=1_500, reorient_tokens=20_000):
    """Re-run one chat's main-thread calls as if a fresh chat started from a handoff note
    whenever the history would pass `cap` tokens or the user came back after IDLE_MINUTES.
    Replies and tool output stay identical; only the history carried between calls changes.
    Each handoff pays for writing the note and for re-reading files in the new chat."""
    cost_sum, contexts, worst, history, previous, base = 0.0, [], 0, 0, None, 0
    for call in chat:
        writing = WEIGHTS["output"] * call["output"] + WEIGHTS["input"] * call["input"]
        if previous is None:
            base = min(call["context"], 60_000)  # system prompt, tools and memory of a fresh chat
            history = call["context"]
            cost_sum += sum(call["parts"].values())
        else:
            growth = call["context"] - previous
            if growth < 0:  # the original chat compacted; keep the smaller history
                growth, history = 0, min(history, call["context"])
            came_back = call["idle"] is not None and call["idle"] >= IDLE_MINUTES
            if came_back or history + growth > cap:
                fresh = base + note_tokens + reorient_tokens + growth
                cost_sum += WEIGHTS["output"] * note_tokens + WEIGHTS["cache_write_1h"] * fresh + writing
                history = fresh
                worst = max(worst, fresh)
            else:
                cost_sum += WEIGHTS["cache_read"] * history + WEIGHTS["cache_write_1h"] * growth + writing
                history += growth
                worst = max(worst, growth)
        contexts.append(history)
        previous = call["context"]
    return cost_sum, contexts, worst


def bar(share, width=24):
    full = int(round(share * width))
    return "█" * full + "░" * (width - full)


def pct(part, total):
    return f"{100 * part / total:3.0f}%" if total else "  0%"


def auto_compact_configured():
    if os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW"):
        return True
    path = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"), "settings.json")
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle).get("autoCompactWindow")
        return value not in (None, "auto")
    except (OSError, ValueError, AttributeError):
        return False


def main():
    default_root = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"), "projects")
    parser = argparse.ArgumentParser(description="Show where your Claude Code usage goes.")
    parser.add_argument("--days", type=int, default=30, help="how far back to look (default 30)")
    parser.add_argument("--top", type=int, default=5, help="how many chats to list (default 5)")
    parser.add_argument("--root", default=default_root, help="transcripts folder (default: ~/.claude/projects)")
    parser.add_argument("--cap", type=int, default=150_000,
                        help="history size where the replay starts a fresh chat (default 150000)")
    args = parser.parse_args()

    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)
    calls = list(read_transcripts(args.root, since))
    if not calls:
        print(f"stint audit: no Claude Code activity in the last {args.days} days under {args.root}")
        return

    by_part, by_bucket, by_model, chats = Counter(), Counter(), Counter(), defaultdict(list)
    spikes, goal_total, subagent_total = [], 0.0, 0.0
    for call in calls:
        weight = sum(call["parts"].values())
        call["weight"] = weight
        by_part.update(call["parts"])
        by_model[call["model"]] += weight
        by_bucket[next(name for name, limit in BUCKETS if call["context"] < limit)] += weight
        chats[call["chat"]].append(call)
        if call["subagent"]:
            subagent_total += weight
        if call["goal"]:
            goal_total += weight
        if call["rewrite"] >= SPIKE_TOKENS and (call["idle"] is None or call["idle"] >= IDLE_MINUTES) and not call["subagent"]:
            spikes.append(call)
    total = sum(by_part.values())
    main_contexts = [c["context"] for c in calls if not c["subagent"]] or [0]
    median_context = statistics.median(main_contexts)
    long_share = by_bucket["> 200k"] / total
    spike_share = sum(c["weight"] for c in spikes) / total
    goal_share = goal_total / total
    thinking_share = by_part["thinking"] / total
    subagent_share = subagent_total / total

    print(f"stint audit · last {args.days} days · {len(calls):,} model calls · {len(chats)} chats")
    print("Shares are estimates: tokens are weighted by public API price ratios.\n")

    print("Where it went")
    for name in ("history reads", "history writes", "writing", "thinking", "new input"):
        print(f"  {name:<16} {pct(by_part[name], total)}  {bar(by_part[name] / total)}")

    print("\nHow long the chat was when each message was sent")
    for name, _ in BUCKETS:
        print(f"  {name:<16} {pct(by_bucket[name], total)}  {bar(by_bucket[name] / total)}")
    print(f"  median history per message: {median_context / 1000:,.0f}k tokens")

    print(f"\nComing back to long chats (≥{SPIKE_TOKENS // 1000}k tokens re-cached after ≥{IDLE_MINUTES} min away)")
    if spikes:
        worst = max(spikes, key=lambda c: c["rewrite"])
        print(f"  {len(spikes)} calls · {pct(spike_share, 1).strip()} of usage · worst: {worst['rewrite'] / 1000:,.0f}k tokens in one call")
    else:
        print("  none")

    print("\nModels")
    for model, weight in by_model.most_common(4):
        print(f"  {model:<28} {pct(weight, total)}")
    print(f"  subagents: {pct(subagent_share, 1).strip()} · /goal turns: {pct(goal_share, 1).strip()}")

    print(f"\nMost expensive chats")
    ranked = sorted(chats.values(), key=lambda cs: -sum(c["weight"] for c in cs))
    for chat in ranked[:args.top]:
        weight = sum(c["weight"] for c in chat)
        contexts = [c["context"] for c in chat if not c["subagent"]] or [0]
        print(f"  {pct(weight, total)}  {chat[0]['time']:%Y-%m-%d}  {chat[0]['project'][:24]:<24} "
              f"{len(chat):>5} calls  avg {statistics.mean(contexts) / 1000:>4.0f}k  peak {max(contexts) / 1000:>4.0f}k")

    replayed, replay_contexts, replay_worst = subagent_total, [], 0
    for chat in chats.values():
        main_calls = [c for c in chat if not c["subagent"]]
        if main_calls:
            chat_cost, chat_contexts, chat_worst = replay(main_calls, args.cap)
            replayed += chat_cost
            replay_contexts += chat_contexts
            replay_worst = max(replay_worst, chat_worst)
    saving = 1 - replayed / total
    worst_before = max((c["rewrite"] for c in calls if not c["subagent"]), default=0)
    print(f"\nBefore and after (replay of these {args.days} days with stint habits)")
    print(f"  {'':<30} {'before':>10} {'with stint':>12}")
    print(f"  {'usage':<30} {'100%':>10} {100 * replayed / total:>11.0f}%")
    print(f"  {'median history per message':<30} {median_context / 1000:>9,.0f}k "
          f"{statistics.median(replay_contexts or [0]) / 1000:>11,.0f}k")
    print(f"  {'biggest single cache write':<30} {worst_before / 1000:>9,.0f}k {replay_worst / 1000:>11,.0f}k")
    print(f"  estimated saving: {saving:.0%} · a fresh chat starts when history passes {args.cap // 1000}k tokens "
          f"or after {IDLE_MINUTES}+ min away;\n  each handoff costs a 1.5k-token note and 20k tokens of re-reading.")

    advice = []
    if long_share > 0.4:
        advice.append(f"{long_share:.0%} of your usage was spent in chats past 200k tokens. Work in short chats: "
                      "save a handoff (`/stint save`) and start a fresh chat when a task or topic changes.")
    if spikes and (spike_share > 0.03 or len(spikes) >= 3):
        advice.append(f"{len(spikes)} times, coming back to a long chat after a break re-cached its whole history at once. "
                      "After a break, open a new chat; the handoff note carries the work over.")
    if max(main_contexts) > 400_000 and not auto_compact_configured():
        advice.append("Chats grew past 400k tokens. Set \"autoCompactWindow\": 300000 in ~/.claude/settings.json "
                      "so they compact before they get that expensive.")
    if goal_share > 0.1:
        advice.append(f"/goal turns used {goal_share:.0%}. Give /goal a checkable condition and a cap, "
                      "e.g. \"/goal tests in tests/api pass, or stop after 20 turns\".")
    if subagent_share > 0.4:
        advice.append(f"Subagents used {subagent_share:.0%}. Each one starts cold; ask for fewer parallel agents on routine work.")
    if thinking_share > 0.25:
        advice.append(f"Thinking used {thinking_share:.0%}. Use a lower /effort for routine edits and keep the high setting for hard problems.")
    elif long_share > 0.4:
        advice.append(f"Thinking is only {thinking_share:.0%}, so lowering effort would cost quality for little gain. Shorten chats instead.")

    print("\nWhat to change")
    for number, line in enumerate(advice or ["Nothing stands out. Your chats stay short; keep it that way."], 1):
        print(f"  {number}. {line}")


if __name__ == "__main__":
    main()
