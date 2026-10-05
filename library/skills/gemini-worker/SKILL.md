---
name: gemini-worker
description: "Delegate bulk, low-judgment reading to Gemini Flash through a CLI so only the answer enters your context: logs, test or build output over ~200 lines, long docs, PDFs, images, long-text summaries. Use before reading such material yourself. Never for edits, exact counts, or secrets."
keywords: "logfile, error logs, server logs, ci logs, build logs, stack trace, traceback, huge dump, giant dump, transcript, thousands of lines, delegate reading, gemini"
inherits: ../../GLOBAL_PREFERENCES.md
always_on: false
activation: "any repo, when you are about to read bulk output or a long document for facts; needs Gemini keys (~/.config/raven-ledger/gemini.env or $GEMINI_API_KEYS) - without them the CLI exits 3 and you fall back to local tools"
context_cost: low
---

# Gemini worker — Orchestrator-Worker offload

You stay the orchestrator: you decide, plan and write code. The worker only **reads and extracts**.
Every token a tool result puts into context is re-read on every later call of the session, so a
50K-token log costs you far more than its own size. The worker hands back ~200–500 tokens.

`gw` below means `python3 <this skill's directory>/scripts/gw.py` — in a vendored project that is
`.claude/library/skills/gemini-worker/scripts/gw.py`; the session-start note gives the absolute path
when the library is not vendored. Each Bash call is a fresh shell, so spell the path out every time.
Only the answer reaches stdout.

```bash
gw "QUESTION" build.log docs/spec.pdf        # files are line-numbered for you
npm test 2>&1 | gw "which tests fail and why? cite lines" -    # '-' = stdin; the raw output never enters context
gw -P question.txt big.log                   # long prompt from a file
```

Ask like a delegator: **all questions in one call** (unpaid keys allow only a few requests a
minute), say what to return and in what shape ("root cause + line numbers + exact quote under 12
words; ignore benign noise"), and always ask for line numbers so you can verify.

## Delegate when

- A command's output you would otherwise read is **over ~200 lines or ~6 KB** (logs, test runs,
  build/CI output, `git log -p`, dependency trees). Pipe it; do not print it first.
- A file or document is **over ~400 lines** (or any PDF/image) and you need facts from it, not text
  to edit.
- You must summarize or compare long text (over ~1,500 words): transcripts, threads, specs, changelogs.
- A grep narrowed the haystack to a set of files and you now need to triage what each says.
- You need current web information: `--search` grounds the answer in Google Search and appends
  source titles — **but it needs search quota that unpaid keys often lack** (it returned 429 on every
  model tried). Check with one cheap call; if it exits 4 with a "grounding" hint, use WebSearch/WebFetch.

## Do not delegate

- Anything you will edit or must quote exactly — locate with `grep -n`, then read only that range.
- Exact counts, complete lists, checksums — `grep -c`, `wc`, `awk`. Models miscount.
- Env keys and secret values (tokens, passwords, API keys, private keys, `.env` contents) — the one
  limit on what may be sent. Everything else, including logs, client and personal data, may go. The
  CLI refuses env/key files and redacts known secret shapes in files, stdin and the question, but you
  are the first gate: never paste a secret into the question or pipe a file you know holds one. PDFs
  and images are sent as-is and cannot be scanned. `gw --dry-run …` prints exactly what would be sent
  while nothing leaves the machine.
- Material under ~100 lines, or anything one `grep -n … | head` answers: the call costs more than it saves.
- Judgment — design decisions, security verdicts, review conclusions. The worker extracts; you decide.

## Trust, then verify

The answer is a lead, not ground truth. Before acting on a claim, check the cited line
(`sed -n '120,125p' file`) or grep the quote — one cheap call. Never edit from the worker's paraphrase.

## When it fails

Stdout stays empty and stderr carries one line, `gw: exit N - …`. Do not loop.

| exit | meaning | do |
|---|---|---|
| 0 | answer on stdout | use it |
| 2 | bad call: missing file, binary file, too large, secret-bearing file | fix the call; a secret-file refusal is final |
| 3 | no keys configured | tell the user once where to put them; continue locally |
| 4 | every key rate-limited (429) | wait the printed time once only if you have other work; else fall back |
| 5 | service unavailable (5xx, network) | retry once after ~30 s, then fall back |
| 6 | keys rejected, model gone, request blocked | config problem — tell the user once, do not retry, fall back |

**Fallback — judge the priority.** Blocking step and a bounded local read answers it
(`grep -n -i -E 'error|fail|exception' f | head -40`, `tail -n 80`, `sed -n 'a,bp'`) → do that now.
Needs a large read: narrow with grep/awk first; if it is still over ~2K tokens and optional, ask the
user whether to wait or skip. Never paste the raw material into context "to be safe" — that is the
cost this skill exists to avoid.

## Setup and checks

- Keys live outside every repo: `~/.config/raven-ledger/gemini.env` (`chmod 600`) holding
  `GEMINI_API_KEYS=k1,k2,k3`, or the same variable in the environment. Never commit or print them.
- Rotation is automatic: a key that returns 429 is skipped for its cooldown by **every** later call,
  including parallel subagents (shared state in `~/.cache/raven-ledger/`). 5xx/network errors back
  off and retry; invalid keys are skipped. Keep to ≤3 concurrent worker calls.
- `gw --check` pings every key · `gw --list-models` · `--dry-run` previews the outgoing request · `-v` shows slot/tokens/retries · `--json` for
  scripts · `GEMINI_MODEL` overrides the default alias `gemini-flash-latest` (a pinned version breaks
  the day Google retires it) · `--think low|medium|high` (default low).
- Offline self-test (no network, no keys): `python3 <this skill's directory>/scripts/test_gw.py`.
- Switch the worker off for one project: `touch .claude/no-worker` — the CLI then refuses to send
  anything and the session-start note stays silent.
- Wired projects get a scoped allow rule (`Bash(python3 …/gw.py:*)`) in their local settings, so a call
  does not stop at a permission prompt; `RAVEN_WORKER_ALLOW=0 sync/install-project.sh` skips it.
- Usage log (counts only, never content): `~/.cache/raven-ledger/gemini-worker.log`.

## What it measured (synthetic ground truth, run before this skill shipped)

| task | in your context if you read it | via the worker | result |
|---|---|---|---|
| 3,000-line incident log, cause buried among decoy errors | ≈51K tokens | ≈170 | 4/4 planted facts, both runs |
| 1,300-line test run, 7 failures / 4 causes | ≈7.9K | ≈340–390 | 7/7 failing ids, 0 false, causes right |
| questions over two real shell scripts | ≈6.6K | ≈300 | 4/4 facts, every citation exact |

A grep-first approach on the log returned 7.2K tokens of ERROR/WARN lines and **missed** the cause,
which was an INFO line. Latency is 9–55 s per call on shared unpaid capacity — worth it for bulk
material, not for a 20-line file.
