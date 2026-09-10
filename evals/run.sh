#!/usr/bin/env bash
# Eval harness runner for the playkit-js-plugin-builder skill.
#
# Two suites:
#   intake  - ~15 one-line prompts (evals/intake/cases.jsonl), graded by exact match on
#             {name, branch, mode}.
#   e2e     - 4 full builds (evals/e2e/<case>/), graded by code checks (expect.yaml) and
#             an LLM rubric (rubric.md).
#
# Every case runs in its own temp dir so builds never collide or leak into this repo.
#
# IMPORTANT — invocation is a deliberate TODO no-op right now (see invoke_claude_intake and
# invoke_claude_e2e below). This script's job here is to get the harness's plumbing right —
# arg parsing, temp-dir handling, the exact `claude` command line, results layout, and calling
# grade.py — so wiring up the real recursive `claude -p` call later is a small, contained
# change in those two functions, not a rewrite. Until wired up, every case reports SKIP, never
# a false PASS. See evals/README.md.
#
# Usage:
#   evals/run.sh [--suite intake|e2e|all] [--case NAME] [--model NAME]
#                [--max-budget-usd AMOUNT] [--keep-tmp] [--results-dir DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUITE="all"
ONLY_CASE=""
KEEP_TMP=false
MODEL="${EVALS_MODEL:-}"
MAX_BUDGET_USD="${EVALS_MAX_BUDGET_USD:-2.00}"
RESULTS_DIR="${SCRIPT_DIR}/results/$(date +%Y%m%d-%H%M%S)"

# Structured-output contract for the intake suite (research: `claude --help` confirms
# --json-schema takes an inline JSON Schema string, not a file path).
INTAKE_JSON_SCHEMA='{"type":"object","properties":{"name":{"type":"string"},"branch":{"type":"string","enum":["unisphere-consumer","event-bridge","component-ui","side-panel-ui"]},"mode":{"type":"string","enum":["community","internal"]}},"required":["name","branch","mode"],"additionalProperties":false}'

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      SUITE="$2"; shift 2 ;;
    --case)
      ONLY_CASE="$2"; shift 2 ;;
    --model)
      MODEL="$2"; shift 2 ;;
    --max-budget-usd)
      MAX_BUDGET_USD="$2"; shift 2 ;;
    --keep-tmp)
      KEEP_TMP=true; shift ;;
    --results-dir)
      RESULTS_DIR="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ "${SUITE}" != "intake" && "${SUITE}" != "e2e" && "${SUITE}" != "all" ]]; then
  echo "error: --suite must be intake, e2e, or all (got: ${SUITE})" >&2
  exit 1
fi

if [[ -n "${ONLY_CASE}" && "${SUITE}" == "intake" ]]; then
  echo "error: --case only applies to --suite e2e (or all)" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

mkdir -p "${RESULTS_DIR}"
echo "Results dir: ${RESULTS_DIR}"

# --------------------------------------------------------------------------------------------
# Invocation (TODO: wire up for real; see the file header)
# --------------------------------------------------------------------------------------------

# invoke_claude_intake PROMPT OUT_JSON
# Builds and (for now) only logs the real command line for one intake case, then writes an
# explicit {"skipped": ...} response so grade.py records SKIP instead of fabricating a verdict.
invoke_claude_intake() {
  local prompt="$1" out_json="$2"
  local -a cmd=(claude -p "${prompt}" --plugin-dir "${REPO_ROOT}"
                --output-format json --json-schema "${INTAKE_JSON_SCHEMA}"
                --max-budget-usd "${MAX_BUDGET_USD}")
  [[ -n "${MODEL}" ]] && cmd+=(--model "${MODEL}")
  { printf 'would run:'; printf ' %q' "${cmd[@]}"; printf '\n'; } >&2

  # TODO: replace this block with the real call. It should run `"${cmd[@]}"` from inside the
  # case's temp dir, take the top-level "result" field of its --output-format json envelope
  # (itself the --json-schema-validated {name, branch, mode} object), and write that object to
  # $out_json. Left as a no-op so this harness is safe to run without burning API budget or
  # recursing into a live Claude Code session from inside one.
  printf '{"skipped": "invoke_claude_intake is a TODO no-op; see evals/run.sh"}' > "${out_json}"
}

# invoke_claude_e2e PROMPT_FILE WORKDIR OUT_JSON
# Same TODO contract as invoke_claude_intake, for one e2e case. The real call runs with
# WORKDIR as the cwd so the skill scaffolds the plugin there, and should save its full
# --output-format json transcript to $out_json for the rubric grader to read.
invoke_claude_e2e() {
  local prompt_file="$1" workdir="$2" out_json="$3"
  local prompt
  prompt="$(cat "${prompt_file}")"
  local -a cmd=(claude -p "${prompt}" --plugin-dir "${REPO_ROOT}" --output-format json
                --max-budget-usd "${MAX_BUDGET_USD}")
  [[ -n "${MODEL}" ]] && cmd+=(--model "${MODEL}")
  { printf 'would run (cwd=%s):' "${workdir}"; printf ' %q' "${cmd[@]}"; printf '\n'; } >&2

  # TODO: replace this block with the real call (cwd="${workdir}"). Save the full
  # --output-format json output to $out_json; grade.py's rubric grader reads it as the
  # transcript.
  printf '{"skipped": "invoke_claude_e2e is a TODO no-op; see evals/run.sh"}' > "${out_json}"
}

# --------------------------------------------------------------------------------------------
# Intake suite
# --------------------------------------------------------------------------------------------

run_intake() {
  local cases_file="${SCRIPT_DIR}/intake/cases.jsonl"
  local responses_dir="${RESULTS_DIR}/intake"
  mkdir -p "${responses_dir}"

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local id prompt tmp
    id="$(jq -r '.id' <<<"${line}")"
    prompt="$(jq -r '.prompt' <<<"${line}")"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/plugin-eval-intake-${id}.XXXXXX")"
    (
      cd "${tmp}"
      invoke_claude_intake "${prompt}" "${responses_dir}/${id}.json"
    )
    if [[ "${KEEP_TMP}" != true ]]; then
      rm -rf "${tmp}"
    fi
  done < "${cases_file}"

  python3 "${SCRIPT_DIR}/grade.py" intake --cases "${cases_file}" --responses-dir "${responses_dir}"
}

# --------------------------------------------------------------------------------------------
# E2E suite
# --------------------------------------------------------------------------------------------

# run_e2e_case NAME
run_e2e_case() {
  local case_name="$1"
  local case_dir="${SCRIPT_DIR}/e2e/${case_name}"
  local prompt_file="${case_dir}/prompt.md"

  if [[ ! -f "${prompt_file}" ]]; then
    echo "error: no such e2e case: ${case_name} (missing ${prompt_file})" >&2
    return 1
  fi

  local workdir out_dir transcript status
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/plugin-eval-e2e-${case_name}.XXXXXX")"
  out_dir="${RESULTS_DIR}/e2e/${case_name}"
  mkdir -p "${out_dir}"
  transcript="${out_dir}/transcript.json"

  invoke_claude_e2e "${prompt_file}" "${workdir}" "${transcript}"

  status=0
  python3 "${SCRIPT_DIR}/grade.py" e2e --case-dir "${case_dir}" --workdir "${workdir}" \
    --transcript "${transcript}" | tee "${out_dir}/report.txt" || status=$?

  if [[ "${KEEP_TMP}" == true ]]; then
    echo "kept workdir: ${workdir}" >&2
  else
    rm -rf "${workdir}"
  fi
  return "${status}"
}

run_e2e() {
  local overall=0
  if [[ -n "${ONLY_CASE}" ]]; then
    run_e2e_case "${ONLY_CASE}" || overall=1
  else
    local d name
    for d in "${SCRIPT_DIR}"/e2e/*/; do
      name="$(basename "${d}")"
      run_e2e_case "${name}" || overall=1
    done
  fi
  return "${overall}"
}

# --------------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------------

overall_status=0

if [[ "${SUITE}" == "intake" || "${SUITE}" == "all" ]]; then
  run_intake || overall_status=1
fi

if [[ "${SUITE}" == "e2e" || "${SUITE}" == "all" ]]; then
  run_e2e || overall_status=1
fi

echo "Results written to ${RESULTS_DIR}"
exit "${overall_status}"
