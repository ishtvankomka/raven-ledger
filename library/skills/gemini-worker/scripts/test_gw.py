#!/usr/bin/env python3
"""Offline tests for gw.py. A local mock of the Gemini endpoint scripts 429 / 503 / bad-key /
truncated responses so rotation, backoff, exit codes and the secret gates are checked without
network, real keys, or spending quota.   Run: python3 test_gw.py   (~5 s)"""
import contextlib
import io
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw  # noqa: E402


def ok(text, **extra):
    cand = {"content": {"parts": [{"text": text}]}, "finishReason": "STOP"}
    cand.update(extra)
    return 200, {"candidates": [cand], "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 3}}


def err(code, status, msg, details=None):
    return code, {"error": {"code": code, "status": status, "message": msg, "details": details or []}}


def rate(delay="7s", msg="quota"):
    return err(429, "RESOURCE_EXHAUSTED", msg, [{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": delay}])


BADKEY = err(400, "INVALID_ARGUMENT", "API key not valid. Please pass a valid API key.", [{"reason": "API_KEY_INVALID"}])
DOWN = err(503, "UNAVAILABLE", "The model is overloaded.")


class Mock(BaseHTTPRequestHandler):
    script, seen = {}, []  # key -> [(status, payload)] consumed in order, the last one repeats
    search_script = {}     # key -> (status, payload) used instead when the request carries a `tools` block

    def do_POST(self):
        key = self.headers.get("x-goog-api-key")
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        Mock.seen.append((key, body))
        seq = Mock.script.get(key) or [ok("answer-from-" + str(key))]
        status, payload = seq.pop(0) if len(seq) > 1 else seq[0]
        if "tools" in body and key in Mock.search_script:
            status, payload = Mock.search_script[key]
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


class GW(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), Mock)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = "http://127.0.0.1:%d/v1beta" % cls.srv.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def setUp(self):
        Mock.script, Mock.seen, Mock.search_script = {}, [], {}
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def run_gw(self, *argv, keys="k1", stdin=None):
        env = {"GEMINI_API_BASE": self.base, "RAVEN_STATE_DIR": self.tmp.name, "GW_BACKOFF_SCALE": "0",
               "GW_ENV_FILE": os.path.join(self.tmp.name, "absent.env"), "GEMINI_API_KEYS": keys}
        out, errb = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, env):
            for k in ("GW_ALLOW_SENSITIVE", "GW_NO_REDACT", "GEMINI_MODEL", "GEMINI_API_KEY"):
                os.environ.pop(k, None)
            stack = contextlib.ExitStack()
            stack.enter_context(contextlib.redirect_stdout(out))
            stack.enter_context(contextlib.redirect_stderr(errb))
            if stdin is not None:
                stack.enter_context(mock.patch.object(sys, "stdin", io.TextIOWrapper(io.BytesIO(stdin.encode()))))
            with stack:
                code = gw.main(list(argv))
        return code, out.getvalue(), errb.getvalue()

    def file(self, name, content, mode="w"):
        p = os.path.join(self.tmp.name, name)
        with open(p, mode) as f:
            f.write(content)
        return p

    # ---- happy path
    def test_ok_prints_only_the_answer(self):
        Mock.script = {"k1": [ok("hello")]}
        code, out, e = self.run_gw("q?")
        self.assertEqual((code, out, e), (0, "hello\n", ""))

    def test_files_are_line_numbered_and_question_comes_last(self):
        f = self.file("a.log", "first\nsecond\n")
        self.run_gw("what?", f)
        parts = Mock.seen[0][1]["contents"][0]["parts"]
        self.assertIn("1\tfirst\n2\tsecond", parts[0]["text"])
        self.assertTrue(parts[-1]["text"].startswith("TASK: what?"))

    def test_stdin_dash_and_prompt_file_and_json(self):
        pf = self.file("p.txt", "from file")
        code, out, _ = self.run_gw("-P", pf, "-", "--json", stdin="x\ny")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["slot"], 1)
        body = json.dumps(Mock.seen[0][1])
        self.assertIn("<stdin>", body)
        self.assertIn("TASK: from file", body)

    def test_search_adds_tool_and_sources(self):
        Mock.script = {"k1": [ok("A", groundingMetadata={"groundingChunks": [{"web": {"title": "example.org", "uri": "http://r/1"}}]})]}
        code, out, _ = self.run_gw("q", "--search")
        self.assertEqual(out, "A\n\nSources:\n- example.org\n")
        self.assertEqual(Mock.seen[0][1]["tools"], [{"google_search": {}}])

    # ---- rotation and cooldown
    def test_rotates_on_429_then_skips_the_cooling_key(self):
        Mock.script = {"a": [rate("30s")], "b": [ok("from-b")]}
        code, out, e = self.run_gw("q", keys="a,b")
        self.assertEqual((code, out, e), (0, "from-b\n", ""))
        self.assertEqual([k for k, _ in Mock.seen], ["a", "b"])
        Mock.seen.clear()
        code, out, _ = self.run_gw("q", keys="a,b")
        self.assertEqual((code, out), (0, "from-b\n"))
        self.assertEqual([k for k, _ in Mock.seen], ["b"], "a key that just hit 429 must not be retried by the next call")

    def test_all_keys_429_exits_4_with_one_line(self):
        Mock.script = {"a": [rate("120s")], "b": [rate("120s")]}
        code, out, e = self.run_gw("q", "--max-wait", "0", keys="a,b")
        self.assertEqual((code, out), (4, ""))
        self.assertEqual(len(e.strip().splitlines()), 1)
        self.assertIn("all 2 key(s) rate-limited", e)
        self.assertIn("soonest retry", e)

    def test_short_cooldown_is_waited_out(self):
        Mock.script = {"a": [rate("1s"), ok("later")]}
        code, out, _ = self.run_gw("q", "--max-wait", "10", keys="a")
        self.assertEqual((code, out), (0, "later\n"))

    def test_daily_quota_blocks_long(self):
        det = [{"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [{"quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier"}]}]
        Mock.script = {"a": [err(429, "RESOURCE_EXHAUSTED", "quota", det)]}
        self.run_gw("q", "--max-wait", "0", keys="a")
        with mock.patch.dict(os.environ, {"RAVEN_STATE_DIR": self.tmp.name}):
            until = list(gw.load_state()["blocked"].values())[0]
        self.assertGreater(until - time.time(), 600)

    def test_persistent_429_stops_instead_of_looping(self):
        Mock.script = {"a": [rate("1s")], "b": [rate("1s")]}
        t0 = time.time()
        code, out, e = self.run_gw("q", "--max-wait", "30", keys="a,b")
        self.assertEqual((code, out), (4, ""))
        self.assertEqual(len(Mock.seen), 4, "two rounds, then give up")
        self.assertLess(time.time() - t0, 15)
        self.assertIn("persisted", e)

    def test_search_quota_429_does_not_cool_the_key_for_plain_calls(self):
        Mock.script = {"a": [ok("plain-ok")]}
        Mock.search_script = {"a": (429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED", "message": "quota"}})}
        code, out, e = self.run_gw("q", "--search", "--max-wait", "0", keys="a")
        self.assertEqual((code, out), (4, ""))
        self.assertIn("--search", e)
        code, out, _ = self.run_gw("q", keys="a")
        self.assertEqual((code, out), (0, "plain-ok\n"), "plain calls must still work right after a search 429")

    def test_project_opt_out_marker_blocks_all_sending(self):
        proj = os.path.join(self.tmp.name, "proj")
        os.makedirs(os.path.join(proj, ".claude"))
        self.file("proj/.claude/no-worker", "")
        with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": proj}):
            code, out, e = self.run_gw("q", self.file("a.log", "x\n"))
        self.assertEqual((code, out), (2, ""))
        self.assertIn("disabled for this project", e)
        self.assertEqual(Mock.seen, [], "nothing may be sent when the project opted out")

    # ---- failures
    def test_all_keys_invalid_exits_6_and_is_remembered(self):
        Mock.script = {"a": [BADKEY], "b": [BADKEY]}
        code, out, e = self.run_gw("q", keys="a,b")
        self.assertEqual((code, out), (6, ""))
        self.assertIn("all 2 key(s) rejected", e)
        n = len(Mock.seen)
        code, _, e = self.run_gw("q", keys="a,b")
        self.assertEqual(code, 6)
        self.assertEqual(len(Mock.seen), n, "keys rejected moments ago must not be re-sent")

    def test_503_backs_off_then_succeeds(self):
        Mock.script = {"a": [DOWN, DOWN, ok("up")]}
        code, out, _ = self.run_gw("q", "--retries", "3", keys="a")
        self.assertEqual((code, out), (0, "up\n"))
        self.assertEqual(len(Mock.seen), 3)

    def test_503_moves_on_to_the_next_key_before_retrying_the_failed_one(self):
        Mock.script = {"a": [DOWN, ok("a-late")], "b": [ok("from-b")]}
        code, out, _ = self.run_gw("q", keys="a,b")
        self.assertEqual((code, out), (0, "from-b\n"))
        self.assertEqual([k for k, _ in Mock.seen], ["a", "b"])

    def test_503_exhausted_exits_5(self):
        Mock.script = {"a": [DOWN]}
        code, out, e = self.run_gw("q", "--retries", "1", keys="a")
        self.assertEqual((code, out), (5, ""))
        self.assertEqual(len(Mock.seen), 2)
        self.assertIn("unavailable", e)

    def test_network_down_exits_5(self):
        self.base = "http://127.0.0.1:1/v1beta"  # nothing listens there
        code, out, e = self.run_gw("q", "--retries", "0", keys="a")
        self.assertEqual((code, out), (5, ""))

    def test_no_keys_exits_3(self):
        code, out, e = self.run_gw("q", keys="")
        self.assertEqual((code, out), (3, ""))
        self.assertIn("GEMINI_API_KEYS", e)
        self.assertEqual(Mock.seen, [])

    def test_usage_errors_exit_2(self):
        self.assertEqual(self.run_gw()[0], 2)
        self.assertEqual(self.run_gw("q", os.path.join(self.tmp.name, "missing.log"))[0], 2)
        self.assertEqual(self.run_gw("q", self.tmp.name)[0], 2)  # a directory
        self.assertEqual(self.run_gw("q", self.file("b.bin", b"a\0b", "wb"))[0], 2)
        self.assertEqual(self.run_gw("q", self.file("big.log", "x" * 50), "--max-chars", "10")[0], 2)
        self.assertEqual(Mock.seen, [])

    def test_empty_answer_and_block_exit_6(self):
        Mock.script = {"a": [(200, {"candidates": [{"finishReason": "MAX_TOKENS", "content": {}}]})]}
        code, _, e = self.run_gw("q", keys="a")
        self.assertEqual(code, 6)
        self.assertIn("--max-out", e)
        Mock.script = {"a": [(200, {"promptFeedback": {"blockReason": "SAFETY"}})]}
        code, _, e = self.run_gw("q", keys="a")
        self.assertEqual(code, 6)
        self.assertIn("SAFETY", e)

    def test_unsupported_thinking_level_is_retried_without_it(self):
        Mock.script = {"a": [err(400, "INVALID_ARGUMENT", "Thinking level LOW is not supported for this model."), ok("fine")]}
        code, out, _ = self.run_gw("q", keys="a")
        self.assertEqual((code, out), (0, "fine\n"))
        self.assertIn("thinkingConfig", Mock.seen[0][1]["generationConfig"])
        self.assertNotIn("thinkingConfig", Mock.seen[1][1]["generationConfig"])

    def test_model_not_found_is_not_a_key_problem(self):
        Mock.script = {"a": [err(404, "NOT_FOUND", "model gone")], "b": [ok("x")]}
        code, out, e = self.run_gw("q", keys="a,b")
        self.assertEqual((code, out), (6, ""))
        self.assertEqual(len(Mock.seen), 1, "404 is request-level: rotating keys cannot fix it")
        self.assertIn("--list-models", e)

    # ---- secret gates
    def test_secret_files_are_refused_and_templates_allowed(self):
        for name in (".env", ".env.local", "prod.env", "server.pem", "id_rsa", "credentials.json", "gemini.env"):
            code, _, e = self.run_gw("q", self.file(name, "A=1\n"))
            self.assertEqual(code, 2, name)
            self.assertIn("refusing", e)
        self.assertEqual(Mock.seen, [])
        self.assertEqual(self.run_gw("q", self.file(".env.example", "A=\n"))[0], 0)

    def test_secrets_inside_text_are_redacted_before_sending(self):
        # built at runtime: a secret-shaped literal in source would trip this repo's own pre-commit gate
        secret1, secret2, secret3 = "AKIA" + "ABCDEFGHIJKLMNOP", "ghp_" + "a1B2" * 10, "".join(["z9Y8", "x7W6", "v5U4", "t3S2", "r1Q0"])
        f = self.file("app.log", "ok line\naws=%s\nGH %s\napi_key=%s\n" % (secret1, secret2, secret3))
        code, _, e = self.run_gw("what failed?", f)
        sent = json.dumps(Mock.seen[0][1])
        self.assertEqual(code, 0)
        for s in (secret1, secret2, secret3):
            self.assertNotIn(s, sent)
        self.assertIn("[REDACTED]", sent)
        self.assertIn("redacted", e)

    def test_keys_never_appear_in_output(self):
        Mock.script = {"sekrit-key-123": [err(500, "INTERNAL", "boom sekrit-key-123 leaked")]}
        code, out, e = self.run_gw("q", "--retries", "0", keys="sekrit-key-123")
        self.assertNotIn("sekrit-key-123", e + out)

    def test_check_reports_each_slot(self):
        Mock.script = {"a": [ok("pong")], "b": [rate()]}
        code, out, _ = self.run_gw("--check", keys="a,b")
        self.assertEqual(code, 4)
        self.assertIn("slot 1/2", out)
        self.assertIn("slot 2/2", out)
        self.assertNotIn("a,b", out)


if __name__ == "__main__":
    unittest.main(verbosity=1)
