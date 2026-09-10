#!/usr/bin/env bash
# Decide "community" vs "internal" mode as deterministically as possible, so the skill
# doesn't have to ask the operator unless genuinely ambiguous.
#
# Signals (both tolerant of missing auth/404 — those are expected "no access" outcomes,
# not script errors):
#   1. npm signal: does @kaltura/kaltura-tools resolve against the operator's current npm
#      auth/registry? (`npm view @kaltura/kaltura-tools version`)
#   2. gh signal: does the operator have `gh` authenticated *and* visibility into the
#      kaltura org's repos? (`gh auth status` gates on `gh api orgs/kaltura/repos`)
#
# Output: prints exactly one of "community", "internal", or "ambiguous" on stdout.
#   - internal:  both signals succeed.
#   - community: both signals fail.
#   - ambiguous: signals disagree — tells the calling skill to ask the operator via
#                AskUserQuestion rather than guess.
#
# Keep this script's logic in sync with skills/playkit-js-plugin-builder/reference/ci-cd-modes.md.

set -euo pipefail

npm_signal=false
if npm view @kaltura/kaltura-tools version >/dev/null 2>&1; then
  npm_signal=true
fi

gh_signal=false
if gh auth status >/dev/null 2>&1; then
  # `gh api` on a private org path 404s (not just 401/403) for accounts with no visibility,
  # so check for a non-empty successful response rather than relying on exit code alone.
  org_repo_count="$(gh api orgs/kaltura/repos --jq length 2>/dev/null || true)"
  if [[ "${org_repo_count}" =~ ^[0-9]+$ ]] && [[ "${org_repo_count}" -gt 0 ]]; then
    gh_signal=true
  fi
fi

if [[ "${npm_signal}" == true && "${gh_signal}" == true ]]; then
  echo "internal"
elif [[ "${npm_signal}" == false && "${gh_signal}" == false ]]; then
  echo "community"
else
  echo "ambiguous"
fi

exit 0
