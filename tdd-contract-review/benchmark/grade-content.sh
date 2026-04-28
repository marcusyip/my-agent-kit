#!/usr/bin/env bash
# grade-content.sh — grade Category A (content) of ONE unit's run against expected_gaps.yaml.
# Paired with grade-shape.sh (Category B). Both are invoked per unit by run-matrix.sh.
#
# Usage:
#   ./grade-content.sh <unit-slug> <out-dir>
#
# Example:
#   ./grade-content.sh post-api-v1-transactions sample-app/tdd-contract-review/20260417-0826-post-api-v1-transactions/
#
# Since v0.51 the skill writes findings.json to the in-repo $OUT_DIR
# (tdd-contract-review/{RUN_ID}/) — that's the directory passed here.
# Intermediates live under $WORK_DIR (~/.claude/...) but this grader does
# not need them; only findings.json.
#
# Reads the unit's expected gaps from expected_gaps.yaml and checks findings.json
# in the out directory. Prints a per-gap FOUND/MISSING table and a final score.
#
# Requires: jq, python3 (for YAML parsing). Fails loud if either is missing.

set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
command -v python3 >/dev/null 2>&1 || die "python3 is required but not installed"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <unit-slug> <out-dir>"
  echo "Example: $0 post-api-v1-transactions sample-app/tdd-contract-review/20260417-0826-post-api-v1-transactions/"
  exit 2
fi

UNIT_SLUG="$1"
OUT_DIR="${2%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_FILE="$SCRIPT_DIR/expected_gaps.yaml"
PARSER="$SCRIPT_DIR/parse_expected.py"
FINDINGS_FILE="$OUT_DIR/findings.json"

[[ -f "$EXPECTED_FILE" ]] || die "expected_gaps.yaml not found at $EXPECTED_FILE"
[[ -x "$PARSER" ]] || die "parse_expected.py not found or not executable at $PARSER"
[[ -d "$OUT_DIR" ]] || die "out directory not found: $OUT_DIR"
[[ -f "$FINDINGS_FILE" ]] || die "findings.json not found at $FINDINGS_FILE (the skill didn't emit machine-readable output — check Step 7-8)"

# Validate findings.json is parseable
jq empty "$FINDINGS_FILE" 2>/dev/null || die "findings.json is not valid JSON: $FINDINGS_FILE"

# Dump findings into a flat text corpus (field + description, lowercased) for matching
CORPUS=$(jq -r '.gaps[] | "\(.priority)\t\(.field) \(.description)"' "$FINDINGS_FILE" | tr '[:upper:]' '[:lower:]')

# Extract expected gaps for this unit from YAML via the shared parser.
# TSV columns: id<TAB>priority<TAB>match1^match2^...<TAB>description.
# `^` is the inner separator (unlikely to appear in match patterns or descriptions).
EXPECTED=$("$SCRIPT_DIR/parse_expected.py" gaps "$EXPECTED_FILE" "$UNIT_SLUG")

[[ -n "$EXPECTED" ]] || die "no expected gaps found for unit '$UNIT_SLUG'"

FOUND=0
MISSING=0
TOTAL=0

echo "━━━ grade-content: $UNIT_SLUG ━━━"
echo "Out dir: $OUT_DIR"
echo ""
printf "%-6s %-8s %-8s %s\n" "ID" "PRIORITY" "STATUS" "DESCRIPTION"
printf "%-6s %-8s %-8s %s\n" "------" "--------" "--------" "-----------"

while IFS=$'\t' read -r gid pri matches_raw desc; do
  [[ -z "$gid" ]] && continue
  TOTAL=$((TOTAL + 1))
  status="MISSING"
  # Split matches on ^
  IFS='^' read -ra patterns <<< "$matches_raw"
  for pat in "${patterns[@]}"; do
    [[ -z "$pat" ]] && continue
    pat_lower=$(echo "$pat" | tr '[:upper:]' '[:lower:]')
    if echo "$CORPUS" | grep -q -- "$pat_lower"; then
      status="FOUND"
      break
    fi
  done
  if [[ "$status" == "FOUND" ]]; then
    FOUND=$((FOUND + 1))
    printf "%-6s %-8s \033[32m%-8s\033[0m %s\n" "$gid" "$pri" "$status" "$desc"
  else
    MISSING=$((MISSING + 1))
    printf "%-6s %-8s \033[31m%-8s\033[0m %s\n" "$gid" "$pri" "$status" "$desc"
  fi
done <<< "$EXPECTED"

echo ""
echo "━━━ Score: $FOUND/$TOTAL found ($MISSING missing) ━━━"

if [[ "$MISSING" -gt 0 ]]; then
  exit 1
fi
exit 0
