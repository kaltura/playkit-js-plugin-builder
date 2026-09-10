# Evals for `playkit-js-plugin-builder`

This is a self-owned eval harness, not the gated `claude plugin eval` CLI (still early access,
undocumented at the time this was written). It follows Anthropic's develop-tests guidance: specific
measurable criteria, automated grading, code-based checks first, LLM rubrics that reason before
giving a verdict, volume over hand grading
(`platform.claude.com/docs/en/test-and-evaluate/develop-tests`).

Two suites:

| Suite | What it tests | Cases | Grading |
|---|---|---|---|
| `intake/` | Does the skill pick the right `{name, branch, mode}` from one line, before any code is written? | 18 one-line prompts (`intake/cases.jsonl`) | Exact match |
| `e2e/` | Does a full build reach a working, correctly-branched plugin? | 4 full builds (`e2e/<case>/`) | Code graders + LLM rubric |

## Status: invocation is a TODO no-op

`run.sh` builds the exact `claude -p` command line for every case and prints it, but the two
functions that would actually run it (`invoke_claude_intake`, `invoke_claude_e2e`) are a deliberate
no-op: they write `{"skipped": "...a TODO no-op..."}` instead of a real response. Every case
reports `SKIP`, never a fabricated `PASS`.

This is on purpose, not an oversight: actually running these cases means recursively invoking
`claude -p` from inside a Claude Code session, against a real API budget. That's a real cost and a
real recursion risk, and it should be a deliberate, opted-in action, not something that happens
because someone ran `evals/run.sh` to check the harness plumbing. Wiring it up is a contained change
to those two functions once you're ready to spend the budget — the temp-dir handling, results
layout, and grading calls around them are already real and tested.

**Caught during development of this harness:** pointing the rubric grader at a placeholder
transcript still shells out to a real `claude` binary if one is on `PATH` — it has no way to know
the transcript is a stub. `grade.py`'s rubric grader now checks for the `{"skipped": ...}` shape
first and reports `SKIP` before ever calling out. If you write your own transcript file by hand,
keep that shape in mind, or you'll spend real money grading against nothing.

## How to run

```bash
pip install pyyaml   # grade.py's only non-stdlib dependency, for reading expect.yaml

# Everything (both suites, all 4 e2e cases). Exits 1 if any check failed.
evals/run.sh

# Just the intake set:
evals/run.sh --suite intake

# Just one e2e case:
evals/run.sh --suite e2e --case unisphere-consumer

# Keep the temp dirs after a run, to inspect what the grader saw:
evals/run.sh --keep-tmp

# Point at a specific model, or cap spend (once invocation is wired up):
evals/run.sh --model sonnet --max-budget-usd 5.00
```

Results land in `evals/results/<timestamp>/` (gitignored — never commit raw results). Each e2e
case gets its own `report.txt` and `transcript.json`; the intake suite gets one `intake/<id>.json`
per case plus the combined grader output on stdout.

You can also grade something you already have on disk, without going through `run.sh`:

```bash
python3 evals/grade.py e2e --case-dir evals/e2e/side-panel-ui --workdir /path/to/generated-plugin
python3 evals/grade.py intake --cases evals/intake/cases.jsonl --responses-dir /path/to/responses
```

## Pass thresholds

Source: `docs/plans/2026-09-09-plugin-skill-plan.md` §6.14.

| Suite | Threshold |
|---|---|
| Intake | 100% exact-match on `{name, branch, mode}`, repeated 3 times (18 cases × 3 runs, all exact) |
| E2E code graders | All checks in `expect.yaml` pass on 3 of 3 runs, per case |
| E2E rubric | All criteria in `rubric.md` come back `correct` on at least 2 of 3 runs, per case |
| Baseline delta | The same 4 e2e prompts run *without* `--plugin-dir` (no skill) score visibly worse on both graders. This shows the skill's value-add, not just that a capable model can build a plugin unassisted. |

**Skips are not passes.** A run that reports all-`SKIP` (like every run today, until invocation is
wired up) has met none of these thresholds. `run.sh` and `grade.py` never turn a skip into a pass;
treat a results directory full of skips as "harness didn't run yet", not "harness passed."

## Intake set: the Unisphere-first routing rule

Per `docs/plans/2026-09-09-plugin-skill-research.md` §16.9 and
`skills/playkit-js-plugin-builder/reference/decision-tree.md` node 0, the skill must check whether a
Unisphere runtime already covers the request *before* falling through to the three classic
branches. `intake/cases.jsonl` tests this directly:

- **4 cases (`u1`-`u4`)** describe a capability that matches a known runtime (AI video summary,
  Genie chat) without using the word "Unisphere" — these must route to `unisphere-consumer`.
- **4 near-miss cases (`n1`-`n4`)** use similar words ("summary panel", "chat panel", "chapters") but
  explicitly say the data or feature is the operator's own, not Kaltura's AI runtime — these must
  route to `side-panel-ui`, not `unisphere-consumer`. A skill that pattern-matches on keywords alone
  fails these; a skill that checks the actual signal (does this really match a known runtime?)
  passes.
- The remaining 10 cases spread across `event-bridge` (4), `component-ui` (3), and `side-panel-ui`
  (3, non-Unisphere) to exercise the rest of the decision tree.

Every prompt names the plugin explicitly ("Build a plugin called X that...") so `name` has one
correct answer and grading can be a strict string match, not a judgment call.

## E2E cases

| Case | Prompt | Branch it must resolve to |
|---|---|---|
| `side-panel-ui` | Chapters list from cue points | `side-panel-ui` (services registry, not `addComponent`) |
| `event-bridge` | Analytics events to an external endpoint | `event-bridge` (`eventManager.listen`, no UI) |
| `ad-adjacent` | Pause-triggered overlay banner | component UI (`addComponent`, small fixed area) |
| `unisphere-consumer` | "Add the AI video summary side panel" | `unisphere-consumer` (`@playkit-js/unisphere-service`, `unisphere.widget.video-summary`) — must **not** rebuild the feature |

Each case's `expect.yaml` encodes the phase exit checks from plan §4 (phases 1-3 mainly: files
exist, lifecycle greps, `npm ci/build/lint/test` exit 0). `rubric.md` covers what code checks can't:
whether the agent named the right branch and signal *before* writing code, stated its defaults back,
and asked at most one open question.

## `expect.yaml` schema

```yaml
case: <case-id>                 # for the report header
description: <string>

files_exist:                    # each entry is either:
  - path/relative/to/workdir    #   a plain path (must exist), or
  - glob: "some/**/*.ts"        #   a glob with a minimum match count
    min_count: 2

grep_must:                      # every entry: at least one file matching file_glob must
  - file_glob: "src/**/*.ts"    # contain pattern. A glob matching zero files is a FAIL.
    pattern: "regex"
    note: "why this matters"    # optional, shown in the report

grep_must_not:                  # every entry: no file matching file_glob may contain
  - file_glob: "src/**/*.ts"    # pattern. A glob matching zero files trivially passes.
    pattern: "regex"

commands_exit_0:                 # each entry is either a plain command string, or:
  - "npm ci"
  - cmd: "npm run test:e2e"
    skip_if_env_unset: "SOME_VAR"   # SKIP (not FAIL) if that env var isn't set
                                     # "npm run <script>" also auto-SKIPs if package.json
                                     # has no such script.
```

## `grade.py` graders

- `file_exists` — plain paths or glob + minimum count.
- `grep_must` / `grep_must_not` — regex search across every file a glob matches.
- `commands_exit_0` — runs a shell command in the workdir, checks exit code 0, with
  `skip_if_env_unset` and automatic missing-npm-script skipping.
- `llm rubric grader` (stub, real prompt-building and JSON-parsing logic, but the call to a
  grading model needs an LLM CLI on `PATH`) — reads `rubric.md`, reads the transcript, asks the
  grading model to reason per criterion then emit a trailing `{"criteria": {...}, "all_correct":
  bool}` JSON line, and reports each criterion as its own pass/fail line. Skips (doesn't guess)
  when the transcript is missing, is a `{"skipped": ...}` stub, or the grading call fails.

Every grader is real Python you can call directly (see `python3 evals/grade.py --help`); nothing
here is placeholder logic, only the *invocation* of the skill/model in `run.sh` and the *invocation*
of the grading model in `grade.py`'s rubric grader are marked TODO.
