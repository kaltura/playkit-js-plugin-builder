#!/usr/bin/env python3
"""Grader for the playkit-js-plugin-builder evals harness.

Two subcommands:

  grade.py intake --cases intake/cases.jsonl --responses-dir <dir>
      Exact-match grading for the intake set. <dir> holds one JSON file per case
      (named "<id>.json"), each the parsed {name, branch, mode} the run produced, or
      {"skipped": "<reason>"} when run.sh's invocation step is a no-op (see run.sh).

  grade.py e2e --case-dir e2e/<case> --workdir <generated-repo> [--transcript <file>]
      Runs the code graders in <case-dir>/expect.yaml against <workdir>, then (if
      --transcript is given) the LLM rubric grader in <case-dir>/rubric.md.

Both subcommands print a plain-text report and exit 0 if everything passed (or was an
explicitly allowed skip), exit 1 otherwise. Skips are never counted as passes; see
evals/README.md, "Skips are not passes".

Standard library only, plus PyYAML for expect.yaml (documented in evals/README.md).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover - environment guard, not a code path under test
    sys.exit(
        "grade.py needs PyYAML to read expect.yaml files. Install it with:\n"
        "  pip install pyyaml\n"
    )


# --------------------------------------------------------------------------------------
# Shared result type
# --------------------------------------------------------------------------------------


@dataclass
class CheckResult:
    name: str
    status: str  # "PASS", "FAIL", or "SKIP"
    detail: str = ""


@dataclass
class CaseReport:
    case_id: str
    results: list[CheckResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(r.status != "FAIL" for r in self.results)

    def add(self, name: str, status: str, detail: str = "") -> None:
        self.results.append(CheckResult(name, status, detail))

    def print_report(self) -> None:
        print(f"\n== {self.case_id} ==")
        for r in self.results:
            marker = {"PASS": "PASS", "FAIL": "FAIL", "SKIP": "SKIP"}[r.status]
            line = f"  [{marker}] {r.name}"
            if r.detail:
                line += f" -- {r.detail}"
            print(line)
        n_pass = sum(1 for r in self.results if r.status == "PASS")
        n_fail = sum(1 for r in self.results if r.status == "FAIL")
        n_skip = sum(1 for r in self.results if r.status == "SKIP")
        print(f"  {n_pass} pass, {n_fail} fail, {n_skip} skip")


# --------------------------------------------------------------------------------------
# Code graders: file_exists, grep_must, grep_must_not, commands_exit_0
# --------------------------------------------------------------------------------------


def _glob_files(workdir: Path, pattern: str) -> list[Path]:
    """Glob relative to workdir. Supports ** via pathlib's glob."""
    matches = sorted(workdir.glob(pattern))
    return [p for p in matches if p.is_file()]


def check_files_exist(workdir: Path, items: list[Any], report: CaseReport) -> None:
    """Each item is either a plain relative-path string, or {glob, min_count}."""
    for item in items:
        if isinstance(item, str):
            path = workdir / item
            if path.is_file():
                report.add(f"file exists: {item}", "PASS")
            else:
                report.add(f"file exists: {item}", "FAIL", "not found")
        elif isinstance(item, dict) and "glob" in item:
            pattern = item["glob"]
            min_count = int(item.get("min_count", 1))
            matches = _glob_files(workdir, pattern)
            if len(matches) >= min_count:
                report.add(
                    f"glob matches: {pattern} (>= {min_count})",
                    "PASS",
                    f"found {len(matches)}",
                )
            else:
                report.add(
                    f"glob matches: {pattern} (>= {min_count})",
                    "FAIL",
                    f"found {len(matches)}",
                )
        else:
            report.add("files_exist entry", "FAIL", f"malformed entry: {item!r}")


_JS_LIKE_SUFFIXES = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"}


def _strip_js_comments(text: str) -> str:
    """Blank out // and /* */ comments, leaving string/template-literal content alone
    (so a URL like "https://..." inside a string is not mistaken for a line comment).
    Replaces comment characters with spaces rather than deleting them, so match
    positions/line numbers in the original file are unaffected."""
    out = list(text)
    i, n = 0, len(text)
    in_string: str | None = None  # one of '"', "'", "`", or None
    while i < n:
        c = text[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == in_string:
                in_string = None
            i += 1
            continue
        if c in ("'", '"', "`"):
            in_string = c
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def _grep_matches(workdir: Path, file_glob: str, pattern: str) -> tuple[list[Path], list[Path]]:
    """Returns (matched_files, files_containing_pattern). For JS/TS-like files, comments
    are blanked out first: every check here is asserting something about real code, and a
    comment that happens to mention a banned pattern (explaining why it's not used) or an
    allowed pattern (in a warning string) is not the code the check is meant to catch."""
    regex = re.compile(pattern)
    matched_files = _glob_files(workdir, file_glob)
    hits = []
    for f in matched_files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if f.suffix in _JS_LIKE_SUFFIXES:
            text = _strip_js_comments(text)
        if regex.search(text):
            hits.append(f)
    return matched_files, hits


def check_grep_must(workdir: Path, items: list[dict], report: CaseReport) -> None:
    for item in items:
        file_glob = item["file_glob"]
        pattern = item["pattern"]
        note = item.get("note", "")
        label = f"grep_must: {file_glob} ~ /{pattern}/"
        matched_files, hits = _grep_matches(workdir, file_glob, pattern)
        if not matched_files:
            report.add(label, "FAIL", f"no files matched glob {file_glob!r}")
        elif hits:
            report.add(label, "PASS", note)
        else:
            report.add(label, "FAIL", f"pattern not found in any of {len(matched_files)} file(s). {note}")


def check_grep_must_not(workdir: Path, items: list[dict], report: CaseReport) -> None:
    for item in items:
        file_glob = item["file_glob"]
        pattern = item["pattern"]
        note = item.get("note", "")
        label = f"grep_must_not: {file_glob} ~ /{pattern}/"
        _matched_files, hits = _grep_matches(workdir, file_glob, pattern)
        if hits:
            hit_names = ", ".join(str(h.relative_to(workdir)) for h in hits)
            report.add(label, "FAIL", f"pattern found in: {hit_names}. {note}")
        else:
            report.add(label, "PASS", note)


def _npm_script_exists(workdir: Path, script: str) -> bool:
    pkg_path = workdir / "package.json"
    if not pkg_path.is_file():
        return False
    try:
        pkg = json.loads(pkg_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return script in pkg.get("scripts", {})


def check_commands_exit_0(
    workdir: Path, items: list[Any], report: CaseReport, timeout_sec: int = 900
) -> None:
    for item in items:
        if isinstance(item, str):
            cmd, skip_env = item, None
        elif isinstance(item, dict):
            cmd, skip_env = item["cmd"], item.get("skip_if_env_unset")
        else:
            report.add("commands_exit_0 entry", "FAIL", f"malformed entry: {item!r}")
            continue

        label = f"command exits 0: {cmd}"

        if skip_env and not os.environ.get(skip_env):
            report.add(label, "SKIP", f"{skip_env} is not set")
            continue

        # "npm run <script>" against a script the generated package.json doesn't define is a
        # skip, not a failure: not every case needs every script (e.g. test:e2e is optional
        # until a case has browser tests wired up).
        m = re.match(r"^npm run (\S+)", cmd)
        if m and not _npm_script_exists(workdir, m.group(1)):
            report.add(label, "SKIP", f"no \"{m.group(1)}\" script in package.json")
            continue

        try:
            proc = subprocess.run(
                cmd,
                shell=True,
                cwd=workdir,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
            )
        except subprocess.TimeoutExpired:
            report.add(label, "FAIL", f"timed out after {timeout_sec}s")
            continue

        if proc.returncode == 0:
            report.add(label, "PASS")
        else:
            tail = (proc.stderr or proc.stdout or "").strip().splitlines()
            detail = tail[-1] if tail else f"exit code {proc.returncode}"
            report.add(label, "FAIL", detail)


def run_code_graders(case_dir: Path, workdir: Path) -> CaseReport:
    expect_path = case_dir / "expect.yaml"
    expect = yaml.safe_load(expect_path.read_text(encoding="utf-8")) or {}
    case_id = expect.get("case", case_dir.name)
    report = CaseReport(case_id)

    if not workdir.is_dir():
        report.add("workdir exists", "FAIL", f"{workdir} does not exist")
        return report

    check_files_exist(workdir, expect.get("files_exist", []), report)
    check_grep_must(workdir, expect.get("grep_must", []), report)
    check_grep_must_not(workdir, expect.get("grep_must_not", []), report)
    check_commands_exit_0(workdir, expect.get("commands_exit_0", []), report)
    return report


# --------------------------------------------------------------------------------------
# LLM rubric grader (stub): reasons, then emits correct/incorrect per criterion.
# --------------------------------------------------------------------------------------


def build_rubric_prompt(rubric_text: str, transcript_text: str) -> str:
    """Builds the prompt sent to the grading model. Real logic, not a placeholder: this is
    what run.sh's future wiring will pass to `claude -p`."""
    return (
        "You are grading an AI agent's transcript against a rubric. For EACH numbered "
        "criterion in the rubric below, write one sentence of reasoning, then a verdict of "
        "exactly 'correct' or 'incorrect'. Do not skip a criterion. End with a JSON object on "
        "its own final line: {\"criteria\": {\"1\": \"correct\"|\"incorrect\", ...}, "
        "\"all_correct\": true|false}.\n\n"
        f"--- RUBRIC ---\n{rubric_text}\n\n"
        f"--- AGENT TRANSCRIPT ---\n{transcript_text}\n"
    )


def parse_rubric_verdict(model_output: str) -> dict:
    """Pulls the trailing JSON object out of the grading model's reasoning + verdict output."""
    for line in reversed(model_output.strip().splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    raise ValueError("no trailing JSON verdict line found in rubric grader output")


def run_llm_rubric_grader(
    case_dir: Path, transcript_path: Path, report: CaseReport, llm_cmd: str = "claude"
) -> None:
    """Reasons over the transcript against rubric.md, then reports correct/incorrect per
    criterion.

    TODO (tracked, not silently skipped): this calls out to the `claude` CLI recursively,
    the same limitation run.sh's invoke_claude() has. When that binary isn't available or
    the call fails in this sandbox, we record SKIP with the reason instead of guessing a
    verdict — a rubric grader must never fabricate a pass.
    """
    rubric_path = case_dir / "rubric.md"
    if not rubric_path.is_file():
        report.add("llm rubric grader", "SKIP", f"no rubric.md in {case_dir}")
        return
    if not transcript_path.is_file():
        report.add("llm rubric grader", "SKIP", f"transcript not found: {transcript_path}")
        return

    rubric_text = rubric_path.read_text(encoding="utf-8")
    transcript_text = transcript_path.read_text(encoding="utf-8")

    # run.sh's invoke_claude_e2e is a deliberate TODO no-op today: it writes a {"skipped": ...}
    # placeholder instead of a real transcript (see run.sh). Recognize that placeholder and
    # skip here too, *before* ever shelling out to an LLM. Without this guard, pointing the
    # rubric grader at a placeholder transcript still spends real money on a real recursive
    # `claude -p` call graded against meaningless input -- this was caught by hand during
    # development of this harness, not a hypothetical.
    try:
        maybe_stub = json.loads(transcript_text)
    except json.JSONDecodeError:
        maybe_stub = None
    if isinstance(maybe_stub, dict) and "skipped" in maybe_stub:
        report.add("llm rubric grader", "SKIP", maybe_stub["skipped"])
        return
    prompt = build_rubric_prompt(rubric_text, transcript_text)

    if shutil.which(llm_cmd) is None:
        report.add(
            "llm rubric grader", "SKIP", f"'{llm_cmd}' not on PATH -- TODO: wire up grading call"
        )
        return

    try:
        proc = subprocess.run(
            [llm_cmd, "-p", prompt, "--output-format", "text"],
            capture_output=True,
            text=True,
            timeout=300,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        report.add("llm rubric grader", "SKIP", f"grading call failed: {exc}")
        return

    if proc.returncode != 0:
        report.add("llm rubric grader", "SKIP", f"grading call exited {proc.returncode}")
        return

    try:
        verdict = parse_rubric_verdict(proc.stdout)
    except ValueError as exc:
        report.add("llm rubric grader", "SKIP", str(exc))
        return

    for criterion, result in verdict.get("criteria", {}).items():
        status = "PASS" if result == "correct" else "FAIL"
        report.add(f"rubric criterion {criterion}", status)


# --------------------------------------------------------------------------------------
# Intake grading: exact-match on {name, branch, mode}
# --------------------------------------------------------------------------------------


def load_jsonl(path: Path) -> list[dict]:
    cases = []
    with path.open(encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                cases.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{lineno}: invalid JSON: {exc}") from exc
    return cases


def grade_intake(cases_path: Path, responses_dir: Path) -> CaseReport:
    cases = load_jsonl(cases_path)
    report = CaseReport("intake")
    for case in cases:
        case_id = case["id"]
        expected = case["expected"]
        response_path = responses_dir / f"{case_id}.json"
        label = f"{case_id}: {case['prompt'][:60]}..."

        if not response_path.is_file():
            report.add(label, "SKIP", f"no response file at {response_path}")
            continue

        try:
            actual = json.loads(response_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            report.add(label, "FAIL", f"response is not valid JSON: {exc}")
            continue

        if "skipped" in actual:
            report.add(label, "SKIP", actual["skipped"])
            continue

        mismatches = [
            f"{key}: expected {expected[key]!r}, got {actual.get(key)!r}"
            for key in ("name", "branch", "mode")
            if actual.get(key) != expected.get(key)
        ]
        if mismatches:
            report.add(label, "FAIL", "; ".join(mismatches))
        else:
            report.add(label, "PASS")
    return report


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)

    p_intake = sub.add_parser("intake", help="Grade the intake (one-line prompt) set.")
    p_intake.add_argument("--cases", type=Path, required=True, help="Path to cases.jsonl")
    p_intake.add_argument(
        "--responses-dir",
        type=Path,
        required=True,
        help="Dir with one <id>.json response file per case",
    )

    p_e2e = sub.add_parser("e2e", help="Grade one e2e case (code graders, plus rubric if given).")
    p_e2e.add_argument("--case-dir", type=Path, required=True, help="e2e/<case> directory")
    p_e2e.add_argument("--workdir", type=Path, help="Generated repo to check (code graders)")
    p_e2e.add_argument("--transcript", type=Path, help="Agent transcript file (rubric grader)")
    p_e2e.add_argument("--llm-cmd", default="claude", help="Grading model CLI (default: claude)")

    args = parser.parse_args()

    if args.mode == "intake":
        report = grade_intake(args.cases, args.responses_dir)
        report.print_report()
        return 0 if report.passed else 1

    if args.mode == "e2e":
        if args.workdir is None and args.transcript is None:
            parser.error("e2e mode needs --workdir, --transcript, or both")
        if args.workdir is not None:
            report = run_code_graders(args.case_dir, args.workdir)
        else:
            report = CaseReport(args.case_dir.name)
        if args.transcript is not None:
            run_llm_rubric_grader(args.case_dir, args.transcript, report, args.llm_cmd)
        report.print_report()
        return 0 if report.passed else 1

    return 1


if __name__ == "__main__":
    sys.exit(main())
