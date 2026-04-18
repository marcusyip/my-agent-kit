#!/usr/bin/env bash
# run-eval.sh — matrix runner for tdd-contract-review benchmark
#
# Loops every unit declared in expected_gaps.yaml, finds the latest run dir for
# each under sample-app/tdd-contract-review/*-<slug>/, then grades each via
# both eval.sh (Category A — content) and structural_check.sh (Category B — shape).
#
# Usage:
#   ./run-eval.sh                           # grade every unit that has a run dir
#   ./run-eval.sh --strict                  # also fail if a unit has no run dir
#   ./run-eval.sh --unit <slug>             # grade one unit only
#
# Outputs:
#   - console pass/fail matrix (one row per unit × category)
#   - benchmark/last-eval.json (machine-readable summary; git-ignored)
#   - exit 0 iff every graded case passed
#
# Requires: jq, python3. Fails loud if missing.

set -uo pipefail

die() { echo "✗ $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
command -v python3 >/dev/null 2>&1 || die "python3 is required but not installed"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_FILE="$SCRIPT_DIR/expected_gaps.yaml"
RUNS_DIR="$SCRIPT_DIR/sample-app/tdd-contract-review"
EVAL_SCRIPT="$SCRIPT_DIR/eval.sh"
STRUCT_SCRIPT="$SCRIPT_DIR/structural_check.sh"
SUMMARY_FILE="$SCRIPT_DIR/last-eval.json"

[[ -f "$EXPECTED_FILE" ]] || die "expected_gaps.yaml not found at $EXPECTED_FILE"
[[ -x "$EVAL_SCRIPT" ]]   || die "eval.sh not found or not executable at $EVAL_SCRIPT"
[[ -x "$STRUCT_SCRIPT" ]] || die "structural_check.sh not found or not executable at $STRUCT_SCRIPT"

STRICT=0
ONLY_UNIT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --unit)   ONLY_UNIT="${2:-}"; [[ -z "$ONLY_UNIT" ]] && die "--unit requires a slug"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --- extract unit slugs from expected_gaps.yaml ---
ALL_UNITS=$(python3 - "$EXPECTED_FILE" <<'PY'
import sys, re
with open(sys.argv[1]) as f:
    txt = f.read()
m = re.search(r'^units:\s*$', txt, re.MULTILINE)
if not m:
    sys.exit("no 'units:' section in yaml")
body = txt[m.end():]
for sm in re.finditer(r'^  ([a-zA-Z0-9_\-]+):\s*$', body, re.MULTILINE):
    print(sm.group(1))
PY
)

[[ -n "$ALL_UNITS" ]] || die "no units declared in expected_gaps.yaml"

if [[ -n "$ONLY_UNIT" ]]; then
  if ! grep -qx "$ONLY_UNIT" <<< "$ALL_UNITS"; then
    die "unit '$ONLY_UNIT' not declared in expected_gaps.yaml"
  fi
  UNITS="$ONLY_UNIT"
else
  UNITS="$ALL_UNITS"
fi

# --- per-unit: find latest run dir ---
find_latest_run() {
  local slug="$1"
  [[ -d "$RUNS_DIR" ]] || return 1
  ls -1d "$RUNS_DIR"/*-"$slug" 2>/dev/null | sort | tail -n 1
}

# --- matrix state ---
TOTAL_CASES=0
PASS_CASES=0
FAIL_CASES=0
SKIP_CASES=0

declare -a ROWS=()           # "slug|run|a_status|b_status|a_log|b_log"
declare -a JSON_ENTRIES=()

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

record() {
  local slug="$1" run="$2" a_status="$3" b_status="$4" a_detail="$5" b_detail="$6"
  ROWS+=("$slug|$run|$a_status|$b_status|$a_detail|$b_detail")

  local run_json run_esc a_detail_esc b_detail_esc
  run_esc=$(printf '%s' "$run" | json_escape)
  a_detail_esc=$(printf '%s' "$a_detail" | json_escape)
  b_detail_esc=$(printf '%s' "$b_detail" | json_escape)
  JSON_ENTRIES+=("$(cat <<EOF
{
  "unit": "$slug",
  "run_dir": $run_esc,
  "category_a": { "status": "$a_status", "detail": $a_detail_esc },
  "category_b": { "status": "$b_status", "detail": $b_detail_esc }
}
EOF
)")
}

echo "━━━ run-eval.sh: tdd-contract-review matrix ━━━"
echo "Expected units: $(echo "$UNITS" | wc -l | tr -d ' ')"
echo "Runs dir: $RUNS_DIR"
[[ $STRICT -eq 1 ]] && echo "Strict mode: ON (missing run dirs count as failures)"
echo ""

while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  TOTAL_CASES=$((TOTAL_CASES + 2))   # A + B per unit

  RUN_DIR=$(find_latest_run "$slug" || true)

  if [[ -z "$RUN_DIR" || ! -d "$RUN_DIR" ]]; then
    if [[ $STRICT -eq 1 ]]; then
      FAIL_CASES=$((FAIL_CASES + 2))
      record "$slug" "<none>" "FAIL" "FAIL" "no run dir (strict)" "no run dir (strict)"
    else
      SKIP_CASES=$((SKIP_CASES + 2))
      record "$slug" "<none>" "SKIP" "SKIP" "no run dir" "no run dir"
    fi
    continue
  fi

  # Category A — eval.sh (content)
  A_LOG=$("$EVAL_SCRIPT" "$slug" "$RUN_DIR" 2>&1) && A_EXIT=0 || A_EXIT=$?
  A_SUMMARY=$(grep -E '^━━━ Score:' <<< "$A_LOG" | tail -n 1 | sed 's/━//g; s/^ *//; s/ *$//')
  [[ -z "$A_SUMMARY" ]] && A_SUMMARY="eval.sh failed to produce a score"

  if [[ $A_EXIT -eq 0 ]]; then
    PASS_CASES=$((PASS_CASES + 1))
    A_STATUS="PASS"
  else
    FAIL_CASES=$((FAIL_CASES + 1))
    A_STATUS="FAIL"
  fi

  # Category B — structural_check.sh (shape)
  B_LOG=$("$STRUCT_SCRIPT" "$RUN_DIR" 2>&1) && B_EXIT=0 || B_EXIT=$?
  B_SUMMARY=$(grep -iE '^━━━ structural:' <<< "$B_LOG" | tail -n 1 | sed 's/━//g; s/^ *//; s/ *$//')
  [[ -z "$B_SUMMARY" ]] && B_SUMMARY="structural_check.sh failed to produce a score"

  if [[ $B_EXIT -eq 0 ]]; then
    PASS_CASES=$((PASS_CASES + 1))
    B_STATUS="PASS"
  else
    FAIL_CASES=$((FAIL_CASES + 1))
    B_STATUS="FAIL"
  fi

  record "$slug" "$RUN_DIR" "$A_STATUS" "$B_STATUS" "$A_SUMMARY" "$B_SUMMARY"
done <<< "$UNITS"

# --- print matrix ---
printf "%-30s %-6s %-6s %s\n" "UNIT" "A" "B" "DETAIL"
printf "%-30s %-6s %-6s %s\n" "------------------------------" "------" "------" "------"
for row in "${ROWS[@]}"; do
  IFS='|' read -r slug run a b a_detail b_detail <<< "$row"
  color_a="$a"; color_b="$b"
  case "$a" in
    PASS) color_a=$'\033[32mPASS\033[0m' ;;
    FAIL) color_a=$'\033[31mFAIL\033[0m' ;;
    SKIP) color_a=$'\033[33mSKIP\033[0m' ;;
  esac
  case "$b" in
    PASS) color_b=$'\033[32mPASS\033[0m' ;;
    FAIL) color_b=$'\033[31mFAIL\033[0m' ;;
    SKIP) color_b=$'\033[33mSKIP\033[0m' ;;
  esac
  printf "%-30s %b  %b  A: %s\n" "$slug" "$color_a" "$color_b" "$a_detail"
  printf "%-30s %-6s %-6s B: %s\n" "" "" "" "$b_detail"
done

echo ""
echo "━━━ Matrix: $PASS_CASES/$TOTAL_CASES passed ($FAIL_CASES failed, $SKIP_CASES skipped) ━━━"

# --- write JSON summary ---
{
  echo "{"
  echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"strict\": $([[ $STRICT -eq 1 ]] && echo true || echo false),"
  echo "  \"unit_filter\": $(printf '%s' "${ONLY_UNIT:-}" | json_escape),"
  echo "  \"total_cases\": $TOTAL_CASES,"
  echo "  \"pass_cases\": $PASS_CASES,"
  echo "  \"fail_cases\": $FAIL_CASES,"
  echo "  \"skip_cases\": $SKIP_CASES,"
  echo "  \"results\": ["
  first=1
  for entry in "${JSON_ENTRIES[@]}"; do
    if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
    printf "%s" "$entry"
  done
  echo ""
  echo "  ]"
  echo "}"
} > "$SUMMARY_FILE"

echo "Summary written to: $SUMMARY_FILE"

if [[ $FAIL_CASES -gt 0 ]]; then
  exit 1
fi
exit 0
