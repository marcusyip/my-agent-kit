#!/usr/bin/env bash
# eval.sh — grade a tdd-contract-review run against expected_gaps.yaml
#
# Usage:
#   ./eval.sh <unit-slug> <run-dir>
#
# Example:
#   ./eval.sh post-api-v1-transactions sample-app/tdd-contract-review/20260417-0826-post-api-v1-transactions/
#
# Reads the unit's expected gaps from expected_gaps.yaml and checks findings.json
# in the run directory. Prints a per-gap FOUND/MISSING table and a final score.
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
  echo "Usage: $0 <unit-slug> <run-dir>"
  echo "Example: $0 post-api-v1-transactions sample-app/tdd-contract-review/20260417-0826-post-api-v1-transactions/"
  exit 2
fi

UNIT_SLUG="$1"
RUN_DIR="${2%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_FILE="$SCRIPT_DIR/expected_gaps.yaml"
FINDINGS_FILE="$RUN_DIR/findings.json"

[[ -f "$EXPECTED_FILE" ]] || die "expected_gaps.yaml not found at $EXPECTED_FILE"
[[ -d "$RUN_DIR" ]] || die "run directory not found: $RUN_DIR"
[[ -f "$FINDINGS_FILE" ]] || die "findings.json not found at $FINDINGS_FILE (the skill didn't emit machine-readable output — check Step 7-8)"

# Validate findings.json is parseable
jq empty "$FINDINGS_FILE" 2>/dev/null || die "findings.json is not valid JSON: $FINDINGS_FILE"

# Dump findings into a flat text corpus (field + description, lowercased) for matching
CORPUS=$(jq -r '.gaps[] | "\(.priority)\t\(.field) \(.description)"' "$FINDINGS_FILE" | tr '[:upper:]' '[:lower:]')

# Extract expected gaps for this unit from YAML. Emit TSV: id<TAB>priority<TAB>match1^match2^...<TAB>description
# Using ^ as inner separator since it's unlikely to appear in match patterns or descriptions.
EXPECTED=$(python3 - "$EXPECTED_FILE" "$UNIT_SLUG" <<'PY'
import sys, re
path, slug = sys.argv[1], sys.argv[2]
with open(path) as f:
    txt = f.read()

m = re.search(r'^units:\s*$', txt, re.MULTILINE)
if not m:
    sys.exit("no 'units:' section in yaml")
body = txt[m.end():]

slug_pat = re.compile(rf'^  {re.escape(slug)}:\s*$', re.MULTILINE)
sm = slug_pat.search(body)
if not sm:
    sys.exit(f"unit '{slug}' not found in expected_gaps.yaml")

rest = body[sm.end():]
next_key = re.search(r'^  [a-zA-Z0-9_\-]+:\s*$', rest, re.MULTILINE)
block = rest[: next_key.start()] if next_key else rest

for gm in re.finditer(r'-\s+id:\s*([^\s#]+)\s*\n((?:\s{8,}.*\n?)+)', block):
    gid = gm.group(1).strip()
    inner = gm.group(2)
    pri = re.search(r'priority:\s*([A-Z]+)', inner)
    matches = []
    ml = re.search(r'match:\s*\[([^\]]*)\]', inner)
    if ml:
        matches = [s.strip().strip('"').strip("'") for s in ml.group(1).split(',') if s.strip()]
    desc = re.search(r'description:\s*(.*)', inner)
    # TSV: id \t priority \t match^match \t description
    print(f"{gid}\t{pri.group(1) if pri else 'LOW'}\t{'^'.join(matches)}\t{desc.group(1).strip() if desc else ''}")
PY
)

[[ -n "$EXPECTED" ]] || die "no expected gaps found for unit '$UNIT_SLUG'"

FOUND=0
MISSING=0
TOTAL=0

echo "━━━ eval.sh: $UNIT_SLUG ━━━"
echo "Run dir: $RUN_DIR"
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
