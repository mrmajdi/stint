"""Tests for skills/stint/scripts/audit.py on synthetic transcripts. Run: python3 -m unittest discover tests"""
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import unittest

AUDIT = os.path.join(os.path.dirname(__file__), "..", "skills", "stint", "scripts", "audit.py")
NOW = dt.datetime.now(dt.timezone.utc)


def call(minutes_ago, read, write=0, output=100, session="s1", msg_id=None, sidechain=False):
    stamp = (NOW - dt.timedelta(minutes=minutes_ago)).isoformat().replace("+00:00", "Z")
    return {
        "type": "assistant", "timestamp": stamp, "sessionId": session, "cwd": "/work/demo-app",
        "isSidechain": sidechain, "requestId": msg_id or f"r{minutes_ago}{session}",
        "message": {"id": msg_id or f"m{minutes_ago}{session}", "model": "claude-opus-5-5", "usage": {
            "input_tokens": 2, "output_tokens": output, "cache_read_input_tokens": read,
            "cache_creation_input_tokens": write, "cache_creation": {"ephemeral_1h_input_tokens": write},
            "output_tokens_details": {"thinking_tokens": output // 4},
        }},
    }


def goal(minutes_ago, args):
    stamp = (NOW - dt.timedelta(minutes=minutes_ago)).isoformat().replace("+00:00", "Z")
    return {"type": "user", "timestamp": stamp, "message": {
        "content": f"<command-name>/goal</command-name><command-args>{args}</command-args>"}}


class AuditTest(unittest.TestCase):
    def run_audit(self, records, *extra):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "proj"))
            with open(os.path.join(root, "proj", "chat.jsonl"), "w") as handle:
                for record in records:
                    handle.write(json.dumps(record) + "\n")
            env = dict(os.environ, CLAUDE_CONFIG_DIR=root)
            result = subprocess.run([sys.executable, AUDIT, "--root", root, *extra],
                                    capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_long_chats_are_flagged(self):
        records = [call(600 - i, read=300_000 + i * 1000) for i in range(50)]
        out = self.run_audit(records)
        self.assertIn("> 200k", out)
        self.assertIn("spent in chats past 200k tokens", out)
        self.assertIn("demo-app", out)

    def test_short_chats_get_a_clean_bill(self):
        out = self.run_audit([call(100 - i, read=20_000) for i in range(20)])
        self.assertIn("Nothing stands out", out)

    def test_coming_back_after_a_break_is_counted(self):
        records = [call(900, read=300_000), call(600, read=0, write=600_000), call(590, read=600_000)]
        out = self.run_audit(records)
        self.assertIn("worst: 600k tokens in one call", out)

    def test_quick_rewrites_are_not_spikes(self):
        records = [call(100, read=300_000), call(95, read=0, write=400_000)]
        out = self.run_audit(records)
        self.assertIn("none", out.split("Coming back")[1].split("\n")[1])

    def test_goal_turns_are_measured_until_cleared(self):
        records = [call(500, read=10_000), goal(400, "all tests pass")]
        records += [call(399 - i, read=10_000) for i in range(10)]
        records += [goal(300, "clear"), call(200, read=10_000)]
        out = self.run_audit(records)
        self.assertIn("/goal turns: 83%", out)  # 10 of 12 equal calls ran under the goal

    def test_duplicate_records_count_once(self):
        records = [call(10, read=50_000, msg_id="same")] * 5
        out = self.run_audit(records)
        self.assertIn("1 model calls", out)

    def test_subagents_are_separated(self):
        records = [call(10, read=50_000), call(9, read=50_000, sidechain=True, msg_id="sub")]
        out = self.run_audit(records)
        self.assertIn("subagents: 50%", out)

    def saving(self, out):
        line = next(l for l in out.splitlines() if "estimated saving:" in l)
        return int(line.split("estimated saving:")[1].split("%")[0])

    def test_replay_saves_on_long_chats(self):
        records = [call(400 - i, read=30_000 + i * 3_000, write=3_000) for i in range(200)]
        self.assertGreater(self.saving(self.run_audit(records)), 30)

    def test_replay_is_neutral_for_short_chats(self):
        records = [call(100 - i, read=20_000 + i * 500, write=500) for i in range(30)]
        self.assertEqual(self.saving(self.run_audit(records)), 0)

    def test_replay_never_hides_a_cost_increase(self):
        # Coming back to a tiny chat: a handoff is pricier than the 30k it replaces.
        records = [call(500, read=30_000), call(400, read=0, write=30_000)]
        self.assertLessEqual(self.saving(self.run_audit(records)), 0)

    def test_no_activity(self):
        out = self.run_audit([call(60 * 24 * 90, read=10_000)], "--days", "7")
        self.assertIn("no Claude Code activity", out)


if __name__ == "__main__":
    unittest.main()
