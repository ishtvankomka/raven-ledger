#!/usr/bin/env python3
"""gw - Orchestrator-Worker bridge: send a question plus files/stdin to Gemini Flash and print
ONLY the answer on stdout, so the calling agent spends tokens on the result, not on the raw
material. Stdlib only (python3.8+), no install step.

  gw.py "which tests fail and why? cite lines" build.log
  npm test 2>&1 | gw.py "root cause?" -          # '-' = stdin as a file
  gw.py --search "current stable release of <tool>?"
  gw.py --dry-run "q" app.log                    # show exactly what would be sent; nothing leaves

Keys come from GEMINI_API_KEYS (comma-separated) or ~/.config/raven-ledger/gemini.env and are
rotated on HTTP 429. Cooldowns are shared between invocations (state dir), so a key that just
hit its limit is skipped by the next call instead of being re-tried.

Exit codes: 0 ok | 2 usage/input | 3 no keys/config | 4 every key rate-limited (429)
            5 service unavailable (5xx/network) | 6 request rejected / keys invalid / blocked
            7 internal error. On failure stdout stays empty and stderr gets ONE line.
"""
import argparse
import base64
import hashlib
import http.client
import json
import math
import os
import random
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

VERSION = "1.0"
OK, USAGE, CONFIG, RATE, UNAVAIL, REJECTED, INTERNAL = 0, 2, 3, 4, 5, 6, 7

# An alias Google keeps pointed at the current Flash: pinning a version breaks the day it is
# retired (gemini-2.5-flash already answers 404 "no longer available" for new keys).
DEFAULT_MODEL = "gemini-flash-latest"
DEFAULT_BASE = "https://generativelanguage.googleapis.com/v1beta"

SYSTEM = (
    "You are a worker sub-agent for a coding orchestrator. Read the supplied material and "
    "answer ONLY what the task asks. Be terse and factual: bullets, no preamble, no restating "
    "the task. Default to under 200 words unless the task asks for more. When you cite "
    "evidence give file:line and a short exact quote so it can be verified; text files are "
    "line-numbered (NUMBER<TAB>line) - use those numbers, never invent one. If the material "
    "does not contain the answer, say 'not found' instead of guessing. Counts and exhaustive "
    "lists are error-prone: mark them approximate unless trivially checkable. Answer in the "
    "language of the task."
)

# Same intent as the Read deny rules in settings.template.json: the worker must not become a
# way around them, so these never leave the machine. No CLI flag overrides it (an agent could
# pass one); GW_ALLOW_SENSITIVE=1 in the human's environment does.
SENSITIVE = [
    ("env file", re.compile(r"(^|/)(\.env(\..+)?|[^/]+\.env)$", re.I)),
    ("private key / cert", re.compile(r"\.(pem|key|p12|pfx|keystore|jks|kdbx)$", re.I)),
    ("ssh key", re.compile(r"(^|/)id_(rsa|dsa|ecdsa|ed25519)[^/]*$", re.I)),
    ("credentials file", re.compile(r"(^|/)(\.netrc|\.npmrc|\.pypirc|credentials(\.json)?|\.mcp\.json|gemini\.env|[^/]*service[-_]?account[^/]*\.json)$", re.I)),
    ("secrets dir", re.compile(r"(^|/)(secrets?|\.ssh|\.aws|\.gnupg)/", re.I)),
]
TEMPLATE_SUFFIX = (".example", ".sample", ".template", ".dist")

MEDIA = {".pdf": "application/pdf", ".png": "image/png", ".jpg": "image/jpeg",
         ".jpeg": "image/jpeg", ".webp": "image/webp", ".heic": "image/heic", ".heif": "image/heif"}

POSIX = {"[:alnum:]": "A-Za-z0-9", "[:alpha:]": "A-Za-z", "[:digit:]": "0-9", "[:space:]": r"\s",
         "[:upper:]": "A-Z", "[:lower:]": "a-z", "[:xdigit:]": "0-9A-Fa-f"}
# The one limit on what the worker may be sent: env keys and secret values. Everything else goes.
# Shapes that are secrets wherever they appear. The shared list (guardrails/secret-patterns.txt) is
# loaded first; these cover what it does not: the worker's own key format, a whole JWT (the shared
# pattern stops before the signature) and common vendor tokens.
EXTRA_SECRET_PATTERNS = [
    r"AQ\.[A-Za-z0-9_-]{30,}",
    r"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}",
    r"\bsk-[A-Za-z0-9_-]{20,}",
    r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
    r"hooks\.slack\.com/services/[A-Za-z0-9/]{20,}",
    r"(?<!\d)\d{8,10}:[A-Za-z0-9_-]{35}(?![A-Za-z0-9_-])",   # Telegram bot token (sits right after "bot" in URLs)
    r"\b[rs]k_(?:live|test)_[A-Za-z0-9]{16,}",
    r"\bSG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}",
    r"\b(?:npm|glpat)[_-][A-Za-z0-9_-]{20,}",
]
# Structural rules. A PEM block is redacted whole (the shared list only catches its header line).
PEM_BLOCK = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|\Z)", re.S)
URL_CREDENTIALS = re.compile(r"(\b[a-z][a-z0-9+.-]*://[^/\s:@]*:)([^/\s@]{3,})(?=@)", re.I)  # user may be empty (redis://:pw@host)
AUTH_SCHEME = re.compile(r"(\b(?:bearer|basic)\s+)([A-Za-z0-9+/=_.~-]{12,})", re.I)
# name = value, name: value, "name": "value". Whether the NAME is sensitive is judged in code, by
# word segments rather than substrings: `monkey` and `keyboard` are fine, `apiKey` and DB_PASSWORD
# are not. Only the value is replaced, so a log stays readable (password=[REDACTED]).
ASSIGNMENT = re.compile(r"""([A-Za-z_][\w.-]*)(["']?\s*[:=]\s*)(["']?)([^\s"',;&)]{3,})""")
SENSITIVE_SUBSTR = ("secret", "token", "password", "passwd", "apikey", "accesskey", "privatekey",
                    "authorization", "bearer", "dsn", "databaseurl", "connectionstring", "signingkey",
                    "encryptionkey", "masterkey", "cookie")
STRONG_SEGMENT = {"key", "pwd"}
# Weak signals: prose and config say "Auth: magic-link" or "credential.helper = !gh" all the time, so
# these only count when the value itself looks like a secret (12+ chars, letters and digits).
WEAK_SEGMENT = {"auth", "private", "pass", "creds", "cred"}
BENIGN_KEY_PREFIX = {"primary", "foreign", "sort", "cache", "partition", "index", "unique", "composite", "group",
                     "order", "lookup", "hash", "shard", "idempotency", "storage", "translation", "message",
                     "object", "map", "lock", "dedupe", "routing"}
# Names that contain "token" but are not secrets: pagination cursors, counters, types.
BENIGN_NAME = re.compile(r"(?:next|prev|previous|page|continuation|cursor|csrf|xsrf)token|token(?:count|type|expiry|ttl|id|name|url|length|limit|usage|used)|tokens$|credentials?(?:helper|provider|type|store|manager)")
# Values that are references, placeholders or states, not secrets: password: required, token: ${TOKEN}.
BENIGN_VALUE = re.compile(
    r"^(?:\d+|true|false|null|none|nil|yes|no|on|off|undefined|empty|required|optional|string|number|value|bearer|basic"
    r"|expired|invalid|missing|valid|revoked|denied|failed|success|ok|error|unauthorized|forbidden"
    r"|\$\{?\w+\}?|<[^>]*>|%[sd]|\{\{.*|\[REDACTED.*|\*+|x{3,}|process\.env\..*|os\.environ.*|os\.getenv.*|getenv\(.*)$", re.I)


class Fail(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code, self.msg = code, msg


# ---------------------------------------------------------------- config / keys / state
def read_env_file(path):
    out = {}
    try:
        for line in Path(path).read_text(errors="replace").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            out[k.strip()] = v
    except OSError:
        pass
    return out


def load_config(env_file=None):
    """-> (keys, file_env, env_file_path). The process environment wins over the file."""
    path = env_file or os.environ.get("GW_ENV_FILE") or str(Path.home() / ".config" / "raven-ledger" / "gemini.env")
    fenv = read_env_file(path) if os.path.isfile(path) else {}
    raw = (os.environ.get("GEMINI_API_KEYS") or os.environ.get("GEMINI_API_KEY")
           or fenv.get("GEMINI_API_KEYS") or fenv.get("GEMINI_API_KEY") or "")
    keys = []
    for k in re.split(r"[,\s;]+", raw):
        k = k.strip().strip("\"'")
        if k and k not in keys:
            keys.append(k)
    return keys, fenv, path


def state_dir():
    return Path(os.environ.get("RAVEN_STATE_DIR") or Path.home() / ".cache" / "raven-ledger")


def kid(key):
    return hashlib.sha256(key.encode()).hexdigest()[:10]


def load_state():
    try:
        return json.loads((state_dir() / "gemini-keys.json").read_text())
    except (OSError, ValueError):
        return {}


def save_state(st):
    # Best effort and atomic; concurrent workers may overwrite each other, which only costs an
    # extra 429 on some key. Never fail a request over bookkeeping.
    try:
        d = state_dir()
        d.mkdir(parents=True, exist_ok=True)
        tmp = d / ("gemini-keys.json.%d" % os.getpid())
        tmp.write_text(json.dumps(st))
        os.replace(tmp, d / "gemini-keys.json")
    except OSError:
        pass


def log_usage(**kw):
    """One TSV line per call - counts only, never content - so offload volume can be audited."""
    try:
        d = state_dir()
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "gemini-worker.log", "a") as f:
            f.write("\t".join(str(kw.get(k, "")) for k in
                              ("ts", "status", "model", "slot", "prompt_tokens", "out_tokens", "chars_in", "chars_out", "ms")) + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------- inputs
def disabled_here():
    """A project opts out by creating .claude/no-worker; enforced here, not just advised in prose."""
    for base in (os.environ.get("CLAUDE_PROJECT_DIR"), os.getcwd()):
        if base and (Path(base) / ".claude" / "no-worker").exists():
            return str(Path(base) / ".claude" / "no-worker")
    return None


def sensitive_rule(path):
    if os.environ.get("GW_ALLOW_SENSITIVE") == "1":
        return None
    p = str(Path(path).resolve()).replace("\\", "/")
    if p.lower().endswith(TEMPLATE_SUFFIX):
        return None
    for name, rx in SENSITIVE:
        if rx.search(p):
            return name
    return None


def secret_regexes():
    pats = list(EXTRA_SECRET_PATTERNS)
    # <lib>/skills/gemini-worker/scripts/gw.py -> <lib>/guardrails/secret-patterns.txt: the one
    # list every other gate in the library reads.
    try:
        shared = Path(__file__).resolve().parents[3] / "guardrails" / "secret-patterns.txt"
        lines = shared.read_text(errors="replace").splitlines()
    except (IndexError, OSError):
        lines = []
    for line in lines:
        line = line.strip()
        if line and not line.startswith("#"):
            for posix, py in POSIX.items():
                line = line.replace(posix, py)
            pats.append(line)
    out = []
    for p in pats:
        try:
            out.append(re.compile(p, re.I))
        except re.error:
            continue  # an ERE feature Python lacks; one lost pattern beats a crash
    return out


def name_strength(name):
    """'strong' | 'weak' | None - how much a variable NAME suggests its value is a secret."""
    flat = re.sub(r"[^a-z0-9]", "", name.lower())
    if BENIGN_NAME.search(flat):
        return None
    if any(w in flat for w in SENSITIVE_SUBSTR):
        return "strong"
    segs = [s for s in re.split(r"[^a-z0-9]+", re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()) if s]
    if any(s in STRONG_SEGMENT and not (s == "key" and i and segs[i - 1] in BENIGN_KEY_PREFIX) for i, s in enumerate(segs)):
        return "strong"
    if "credential" in flat or any(s in WEAK_SEGMENT for s in segs):
        return "weak"
    return None


def redact(text, regexes):
    """Replace secret values; -> (text, number of replacements)."""
    text, n = PEM_BLOCK.subn("[REDACTED PRIVATE KEY]", text)
    for rx in regexes:
        text, k = rx.subn("[REDACTED]", text)
        n += k
    text, k = URL_CREDENTIALS.subn(r"\1[REDACTED]", text)
    n += k
    text, k = AUTH_SCHEME.subn(r"\1[REDACTED]", text)
    n += k
    hits = [0]

    def assignment(m):
        name, sep, quote, value = m.groups()
        strength = name_strength(name)
        if not strength or BENIGN_VALUE.match(value):
            return m.group(0)
        if strength == "weak" and not (len(value) >= 12 and re.search(r"\d", value) and re.search(r"[A-Za-z]", value)):
            return m.group(0)
        hits[0] += 1
        return name + sep + quote + "[REDACTED]"

    return ASSIGNMENT.sub(assignment, text), n + hits[0]


def build_parts(items, prompt, args):
    """-> (parts, chars_in, redacted). Files first, the question last (best for long context)."""
    regexes = [] if os.environ.get("GW_NO_REDACT") == "1" else secret_regexes()
    parts, chars, redacted, inline = [], 0, 0, 0
    for item in items:
        if item == "-":
            name, data = "<stdin>", sys.stdin.buffer.read()
        else:
            p = Path(item)
            if p.is_dir():
                raise Fail(USAGE, "%s is a directory - pass files (use find/xargs or '-' with a pipe)" % item)
            rule = sensitive_rule(item)
            if rule:
                raise Fail(USAGE, "refusing to send %s (%s) - secrets never go to the worker" % (item, rule))
            try:
                data = p.read_bytes()
            except OSError as e:
                raise Fail(USAGE, "cannot read %s: %s" % (item, e.strerror or e))
            name = item
        mime = MEDIA.get(Path(name).suffix.lower()) if name != "<stdin>" else None
        if mime:
            inline += len(data)
            if inline > args.max_bytes:
                raise Fail(USAGE, "media input exceeds %d MB (--max-bytes)" % (args.max_bytes // 2**20))
            parts.append({"inlineData": {"mimeType": mime, "data": base64.b64encode(data).decode()}})
            parts.append({"text": "(attached above: %s)" % name})
            continue
        if b"\0" in data[:8192]:
            raise Fail(USAGE, "%s looks binary - only text, PDF and common images are supported" % name)
        text = data.decode("utf-8", "replace")
        text, k = redact(text, regexes)
        redacted += k
        lines = text.splitlines()
        body = "\n".join(lines) if args.no_lineno else "\n".join("%d\t%s" % (i, l) for i, l in enumerate(lines, 1))
        chars += len(body)
        parts.append({"text": "=== FILE: %s (%d lines) ===\n%s\n=== END FILE ===" % (name, len(lines), body)})
    if chars > args.max_chars:
        raise Fail(USAGE, "input is %d chars (max %d): pre-filter with grep/tail or raise --max-chars" % (chars, args.max_chars))
    prompt, k = redact(prompt, regexes)
    redacted += k
    parts.append({"text": "TASK: " + prompt})
    return parts, chars + len(prompt), redacted


def build_body(parts, args, model):
    gen = {"maxOutputTokens": args.max_out}
    if args.temperature is not None:
        gen["temperature"] = args.temperature  # Gemini 3 advises leaving it at the default
    if args.think != "auto":
        # 2.5 takes a token budget, 3.x a level ('minimal' is rejected by the current Flash)
        if re.search(r"gemini-2\.5", model):
            gen["thinkingConfig"] = {"thinkingBudget": {"low": 1024, "medium": 4096, "high": 16384}[args.think]}
        else:
            gen["thinkingConfig"] = {"thinkingLevel": args.think}
    body = {"systemInstruction": {"parts": [{"text": SYSTEM + ((" " + args.system) if args.system else "")}]},
            "contents": [{"role": "user", "parts": parts}], "generationConfig": gen}
    if args.search:
        body["tools"] = [{"google_search": {}}]
    return body


# ---------------------------------------------------------------- transport
def http_call(url, key, body, timeout):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers={
        "Content-Type": "application/json", "x-goog-api-key": key,  # header, not URL: keys stay out of error text
        "User-Agent": "raven-gw/" + VERSION})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"error": {"message": raw[:300]}}
    except (OSError, http.client.HTTPException, ValueError) as e:
        return -1, {"error": {"message": "%s: %s" % (type(e).__name__, getattr(e, "reason", e))}}


def classify(status, payload):
    err = payload.get("error", {}) if isinstance(payload, dict) else {}
    msg, det = err.get("message") or "", json.dumps(err.get("details") or [])
    if status == 200:
        return "ok"
    if status == 429:
        return "rate"
    if status in (-1, 408, 500, 502, 503, 504):
        return "unavail"
    if status in (401, 403) or (status == 400 and ("API_KEY_INVALID" in det or "API key not valid" in msg or "API key expired" in msg)):
        return "badkey"
    return "reject"


def retry_delay(err):
    for d in err.get("details") or []:
        m = re.match(r"([\d.]+)s", str(d.get("retryDelay") or ""))
        if m:
            return float(m.group(1))
    m = re.search(r"retry in ([\d.]+)s", err.get("message") or "")
    return float(m.group(1)) if m else None


def generate(keys, model, body, args, verbose):
    """Try keys until one answers. -> (payload, slot, retries). Raises Fail with the right exit code."""
    st = load_state()
    blocked = st.setdefault("blocked", {})
    n = len(keys)
    cursor = int(st.get("cursor", 0) or 0) % n
    order = [(cursor + i) % n for i in range(n)]
    bad = st.setdefault("bad", {})
    now0 = time.time()
    dead = {i for i in range(n) if float(bad.get(kid(keys[i]), 0)) > now0}  # rejected moments ago: skip, exit 6 if all
    net_fail, retries, waited, rate_hits = 0, 0, 0.0, {}
    feature = "|search" if args.search else ""  # a search-only quota must not cool the key for plain calls
    bk = lambda i: kid(keys[i]) + feature
    last_hint = None
    last_err = "key(s) rejected earlier (invalid/forbidden) - fix the key file, then run gw.py --check" if dead else ""
    deadline = time.time() + args.deadline
    url = "%s/models/%s:generateContent" % (os.environ.get("GEMINI_API_BASE", DEFAULT_BASE).rstrip("/"), model)
    dropped_thinking = False
    scrub = lambda s: re.sub("|".join(re.escape(k) for k in keys), "<key>", s or "")
    while True:
        now = time.time()
        if now > deadline:
            raise Fail(UNAVAIL, "deadline of %ds exceeded%s" % (args.deadline, (": " + last_err) if last_err else ""))
        avail = [i for i in order if i not in dead and float(blocked.get(bk(i), 0)) <= now]
        if not avail:
            live = [i for i in order if i not in dead]
            if not live:
                raise Fail(REJECTED, "all %d key(s) rejected%s" % (n, (": " + last_err) if last_err else ""))
            wait = min(float(blocked.get(bk(i), 0)) for i in live) - now
            # Every key already 429'd twice in this call: waiting did not help, so this is a quota
            # the plan does not grant, not a rate limit. Stop instead of looping.
            persistent = all(rate_hits.get(i, 0) >= 2 for i in live)
            if not persistent and waited + wait <= args.max_wait and now + wait < deadline:
                time.sleep(wait + 0.25)
                waited += wait + 0.25
                continue
            hint = ""
            if args.search and (persistent or not last_hint):
                hint = " - Google Search grounding is probably not in this plan's quota; retry without --search or use web tools"
            elif persistent:
                hint = " - 429 persisted after waiting; the quota may be exhausted for today"
            raise Fail(RATE, "all %d key(s) rate-limited (HTTP 429); soonest retry in ~%ds%s" % (n, math.ceil(max(wait, 1)), hint))
        i = avail[0]
        status, payload = http_call(url, keys[i], body, args.timeout)
        kind = classify(status, payload)
        err = payload.get("error", {}) if isinstance(payload, dict) else {}
        last_err = scrub("HTTP %s %s" % (status, (err.get("message") or "")[:200]))
        if verbose:
            sys.stderr.write("[gw] slot %d/%d -> %s (%s)\n" % (i + 1, n, status, kind))
        if kind == "ok":
            blocked.pop(bk(i), None)
            bad.pop(kid(keys[i]), None)
            st["cursor"] = (i + 1) % n  # round-robin: spreads per-minute limits across keys
            save_state(st)
            return payload, i, retries
        if kind == "rate":
            rate_hits[i] = rate_hits.get(i, 0) + 1
            last_hint = retry_delay(err)
            delay = last_hint or 30.0 * 2 ** (rate_hits[i] - 1)  # no hint from Google: back off 30s, 60s, ...
            if "perday" in json.dumps(err.get("details") or []).lower().replace("_", "") or "per day" in (err.get("message") or "").lower():
                delay = max(delay, 900.0)  # a daily quota will not clear in a minute
            blocked[bk(i)] = now + max(2.0, min(delay, 3600.0))
            save_state(st)
        elif kind == "badkey":
            dead.add(i)
            bad[kid(keys[i])] = now + 600
            save_state(st)
        elif kind == "unavail":
            net_fail += 1
            retries += 1
            if net_fail > args.retries:
                raise Fail(UNAVAIL, "service unavailable after %d attempts: %s" % (net_fail, last_err))
            order.remove(i)  # try a different key next; the failed one goes to the back
            order.append(i)
            time.sleep(min(8.0, 1.5 * 2 ** (net_fail - 1)) * float(os.environ.get("GW_BACKOFF_SCALE", "1")) * (0.75 + random.random() / 2))
        else:  # request-level problem: another key will not help
            if status == 400 and "hinking" in (err.get("message") or "") and not dropped_thinking and "thinkingConfig" in body["generationConfig"]:
                dropped_thinking = True
                body["generationConfig"].pop("thinkingConfig")  # model family without that knob
                continue
            hint = " (try --list-models; the default alias is %s)" % DEFAULT_MODEL if status == 404 else ""
            raise Fail(REJECTED, last_err + hint)



def extract(payload):
    cands = payload.get("candidates") or []
    if not cands:
        raise Fail(REJECTED, "no answer (blocked: %s)" % ((payload.get("promptFeedback") or {}).get("blockReason") or "empty response"))
    c = cands[0]
    text = "".join(p.get("text", "") for p in ((c.get("content") or {}).get("parts") or []) if not p.get("thought")).strip()
    fin = c.get("finishReason")
    if not text:
        raise Fail(REJECTED, "empty answer (finishReason=%s)%s" % (fin, "; thinking used the whole output budget - raise --max-out" if fin == "MAX_TOKENS" else ""))
    return text, fin


def sources(payload, urls):
    g = ((payload.get("candidates") or [{}])[0].get("groundingMetadata") or {})
    out = []
    for ch in g.get("groundingChunks") or []:
        w = ch.get("web") or {}
        item = (w.get("title") or w.get("uri") or "") + (" <%s>" % w["uri"] if urls and w.get("uri") else "")
        if item and item not in out:
            out.append(item)
    return out[:6]


# ---------------------------------------------------------------- cli
def parse(argv):
    ap = argparse.ArgumentParser(
        prog="gw.py", formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Send a question + files to Gemini Flash; print only the answer.",
        epilog="Exit codes:" + __doc__.split("Exit codes:")[1])
    ap.add_argument("items", nargs="*", help='"PROMPT" followed by files; "-" reads stdin as a file')
    ap.add_argument("-f", "--file", action="append", default=[], help="extra file (repeatable)")
    ap.add_argument("-P", "--prompt-file", help="read the prompt from this file ('-' = stdin)")
    ap.add_argument("-s", "--system", help="extra system instruction, appended to the default")
    ap.add_argument("-m", "--model", help="default: $GEMINI_MODEL or %s" % DEFAULT_MODEL)
    ap.add_argument("--search", action="store_true", help="enable Google Search grounding; sources are appended")
    ap.add_argument("--urls", action="store_true", help="with --search: include source URLs, not just titles")
    ap.add_argument("--think", choices=["auto", "low", "medium", "high"], default="low", help="thinking depth (default low: cheap, fast)")
    ap.add_argument("--max-out", type=int, default=4096, help="output token cap incl. thinking (default 4096)")
    ap.add_argument("--temperature", type=float, default=None)
    ap.add_argument("--no-lineno", action="store_true", help="do not number lines of text files")
    ap.add_argument("--max-chars", type=int, default=3_500_000, help="text input cap (default ~1M tokens)")
    ap.add_argument("--max-bytes", type=int, default=18 * 2**20, help="inline media cap (request limit is 20 MB)")
    ap.add_argument("--timeout", type=float, default=120, help="seconds per HTTP request")
    ap.add_argument("--deadline", type=float, default=240, help="seconds for the whole call incl. retries")
    ap.add_argument("--retries", type=int, default=3, help="extra attempts on 5xx/network errors")
    ap.add_argument("--max-wait", type=float, default=20, help="wait up to N s for a cooling key before exiting 4")
    ap.add_argument("--env-file", help="key file (default ~/.config/raven-ledger/gemini.env)")
    ap.add_argument("--json", action="store_true", help="emit {text,finish,model,slot,usage,sources} as JSON")
    ap.add_argument("-v", "--verbose", action="store_true", help="diagnostics on stderr")
    ap.add_argument("--list-models", action="store_true", help="print usable Gemini models and exit")
    ap.add_argument("--check", action="store_true", help="ping every key and report its status")
    ap.add_argument("--dry-run", action="store_true", help="print exactly what would be sent (after redaction); no network, no keys needed")
    ap.add_argument("--version", action="version", version="gw " + VERSION)
    return ap.parse_intermixed_args(argv)  # options may follow the prompt/files


def check_keys(keys, model):
    base = os.environ.get("GEMINI_API_BASE", DEFAULT_BASE).rstrip("/")
    body = {"contents": [{"role": "user", "parts": [{"text": "Reply with: pong"}]}],
            "generationConfig": {"maxOutputTokens": 256, "thinkingConfig": {"thinkingLevel": "low"}}}
    worst, st = OK, load_state()
    for i, k in enumerate(keys, 1):
        status, payload = http_call("%s/models/%s:generateContent" % (base, model), k, body, 60)
        kind = classify(status, payload)
        if kind == "ok":  # a key that answers is no longer cooling or rejected
            (st.get("blocked") or {}).pop(kid(k), None)
            (st.get("bad") or {}).pop(kid(k), None)
        sys.stdout.write("slot %d/%d (%s): %s %s\n" % (i, len(keys), kid(k)[:6], status, kind))
        worst = max(worst, {"ok": OK, "rate": RATE, "unavail": UNAVAIL}.get(kind, REJECTED))
    save_state(st)
    return worst


def main(argv=None):
    try:
        args = parse(sys.argv[1:] if argv is None else argv)
        keys, fenv, path = load_config(args.env_file)
        model = args.model or os.environ.get("GEMINI_MODEL") or fenv.get("GEMINI_MODEL") or DEFAULT_MODEL
        marker = disabled_here()
        if marker:
            raise Fail(USAGE, "disabled for this project (%s exists) - use local tools" % marker)
        if not keys and not args.dry_run:
            raise Fail(CONFIG, "no API keys: set GEMINI_API_KEYS or put GEMINI_API_KEYS=k1,k2 in %s" % path)
        try:
            if os.path.isfile(path) and os.stat(path).st_mode & 0o077:
                sys.stderr.write("gw: warning: %s is readable by others - chmod 600\n" % path)
        except OSError:
            pass
        if args.check:
            return check_keys(keys, model)
        if args.list_models:
            base = os.environ.get("GEMINI_API_BASE", DEFAULT_BASE).rstrip("/")
            status, payload = http_call(base + "/models?pageSize=200", keys[0], None, args.timeout)
            if status != 200:
                raise Fail(REJECTED, "HTTP %s %s" % (status, (payload.get("error") or {}).get("message", "")[:160]))
            for m in payload.get("models", []):
                if "generateContent" in m.get("supportedGenerationMethods", []) and "gemini" in m["name"]:
                    sys.stdout.write(m["name"].split("/")[-1] + "\n")
            return OK

        items = list(args.items) + list(args.file)
        if args.prompt_file:
            if args.prompt_file == "-":
                prompt = sys.stdin.buffer.read().decode("utf-8", "replace")
            else:
                try:
                    prompt = Path(args.prompt_file).read_text(errors="replace")
                except OSError as e:
                    raise Fail(USAGE, "cannot read prompt file: %s" % (e.strerror or e))
        elif items:
            prompt, items = items[0], items[1:]
        else:
            raise Fail(USAGE, 'no prompt - usage: gw.py "question" [FILE ...]  (gw.py --help)')
        if not prompt.strip():
            raise Fail(USAGE, "empty prompt")
        if items.count("-") > 1:
            raise Fail(USAGE, "'-' (stdin) may appear once")

        parts, chars_in, redacted = build_parts(items, prompt, args)
        if redacted:
            sys.stderr.write("gw: redacted %d secret-like string(s) before sending\n" % redacted)
        if args.dry_run:
            for part in parts:
                sys.stdout.write((part["text"] if "text" in part else "(media: %s, %d bytes)" % (
                    part["inlineData"]["mimeType"], len(part["inlineData"]["data"]) * 3 // 4)) + "\n")
            sys.stderr.write("gw: dry run - %d chars in %d part(s), %d secret-like string(s) redacted, nothing sent\n"
                             % (chars_in, len(parts), redacted))
            return OK
        body = build_body(parts, args, model)
        t0 = time.time()
        payload, slot, retries = generate(keys, model, body, args, args.verbose)
        text, fin = extract(payload)
        ms = int((time.time() - t0) * 1000)
        usage = payload.get("usageMetadata") or {}
        src = sources(payload, args.urls) if args.search else []
        log_usage(ts=int(time.time()), status="ok", model=model, slot=slot + 1, prompt_tokens=usage.get("promptTokenCount", ""),
                  out_tokens=usage.get("candidatesTokenCount", ""), chars_in=chars_in, chars_out=len(text), ms=ms)
        if args.verbose:
            sys.stderr.write("[gw] model=%s slot=%d/%d in=%s out=%s thoughts=%s retries=%d %.1fs\n" % (
                model, slot + 1, len(keys), usage.get("promptTokenCount"), usage.get("candidatesTokenCount"),
                usage.get("thoughtsTokenCount"), retries, ms / 1000))
        if fin == "MAX_TOKENS":
            sys.stderr.write("gw: warning: answer truncated at --max-out\n")
        if args.json:
            sys.stdout.write(json.dumps({"text": text, "finish": fin, "model": model, "slot": slot + 1,
                                         "usage": usage, "sources": src}, ensure_ascii=False) + "\n")
        else:
            sys.stdout.write(text + "\n")
            if src:
                sys.stdout.write("\nSources:\n" + "\n".join("- " + s for s in src) + "\n")
        return OK
    except Fail as f:
        log_usage(ts=int(time.time()), status="exit%d" % f.code)
        sys.stderr.write("gw: exit %d - %s\n" % (f.code, f.msg))
        return f.code
    except KeyboardInterrupt:
        return 130
    except BrokenPipeError:
        return OK
    except SystemExit as e:  # argparse errors / --help / --version
        return e.code if isinstance(e.code, int) else USAGE
    except Exception as e:  # a bug must still exit with a distinct code and one line
        sys.stderr.write("gw: exit %d - internal error: %s: %s\n" % (INTERNAL, type(e).__name__, e))
        return INTERNAL


if __name__ == "__main__":
    sys.exit(main())
