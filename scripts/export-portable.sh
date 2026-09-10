#!/usr/bin/env bash
# Flattens the Agent Skills package (skills/playkit-js-plugin-builder/) into a single portable
# markdown file for agents that read one prompt file and do not follow the Agent Skills
# reference-link convention. Claude Code, and any tool that implements agentskills.io, should use
# skills/playkit-js-plugin-builder/ directly. This file is a fallback, not the primary distribution
# form.
#
# Output: dist/PORTABLE_SKILL.md (gitignored). Publish it as a release asset, do not commit it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/playkit-js-plugin-builder"
SKILL_MD="$SKILL_DIR/SKILL.md"
REF_DIR="$SKILL_DIR/reference"
OUT_DIR="$REPO_ROOT/dist"
OUT_FILE="$OUT_DIR/PORTABLE_SKILL.md"

fail() {
  echo "export-portable.sh: $1" >&2
  exit 1
}

[[ -f "$SKILL_MD" ]] || fail "missing $SKILL_MD"
[[ -d "$REF_DIR" ]] || fail "missing $REF_DIR"

# --- 1. Extract the YAML frontmatter block (between the first two '---' lines) -------------------

frontmatter_end_line="$(awk '/^---$/{c++; if (c==2) {print NR; exit}}' "$SKILL_MD")"
[[ -n "${frontmatter_end_line:-}" ]] || fail "$SKILL_MD has no closing '---' for its YAML frontmatter"

name="$(awk '/^---$/{c++; next} c==1 && /^name:[[:space:]]*/{sub(/^name:[[:space:]]*/, ""); print; exit}' "$SKILL_MD")"
description="$(awk '/^---$/{c++; next} c==1 && /^description:[[:space:]]*/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$SKILL_MD")"
# Strip surrounding quotes, if any.
name="${name%\"}"; name="${name#\"}"
description="${description%\"}"; description="${description#\"}"

[[ -n "$name" ]] || fail "$SKILL_MD frontmatter has no 'name' key"
[[ -n "$description" ]] || fail "$SKILL_MD frontmatter has no 'description' key"

body="$(tail -n "+$((frontmatter_end_line + 1))" "$SKILL_MD")"

# --- 2. Extract reading order from the named-procedures table (in order of first appearance) ------

# Portable (bash 3.2-compatible): no mapfile, no associative arrays.
table_refs=()
while IFS= read -r line; do
  [[ -n "$line" ]] && table_refs+=("$line")
done <<< "$(grep -oE 'reference/[A-Za-z0-9_-]+\.md' "$SKILL_MD")"
[[ "${#table_refs[@]}" -gt 0 ]] || fail "no reference/*.md paths found in $SKILL_MD's named-procedures table"

contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# De-duplicate while preserving order (a reference file could be pointed at by more than one row).
ordered_refs=()
for ref in "${table_refs[@]}"; do
  contains "$ref" "${ordered_refs[@]:-}" || ordered_refs+=("$ref")
done

# --- 3. Fail loudly on any mismatch between the table and the reference/ directory ----------------

for ref in "${ordered_refs[@]}"; do
  [[ -f "$REPO_ROOT/skills/playkit-js-plugin-builder/$ref" ]] || \
    fail "SKILL.md's named-procedures table lists '$ref' but that file does not exist"
done

actual_refs=()
while IFS= read -r line; do
  [[ -n "$line" ]] && actual_refs+=("$line")
done <<< "$(cd "$REF_DIR" && find . -maxdepth 1 -name '*.md' -type f | sed 's#^\./#reference/#' | sort)"

for ref in "${actual_refs[@]}"; do
  contains "$ref" "${ordered_refs[@]:-}" || \
    fail "$ref exists in reference/ but is not listed in SKILL.md's named-procedures table"
done

# --- 4. Assemble the portable file ------------------------------------------------------------

mkdir -p "$OUT_DIR"

{
  echo "# ${name}"
  echo
  echo "${description}"
  echo
  echo "<!-- ===== source: SKILL.md ===== -->"
  echo
  echo "${body}"
  for ref in "${ordered_refs[@]}"; do
    echo
    echo "<!-- ===== source: ${ref} ===== -->"
    echo
    cat "$SKILL_DIR/$ref"
  done
} > "$OUT_FILE"

echo "export-portable.sh: wrote $OUT_FILE" >&2
