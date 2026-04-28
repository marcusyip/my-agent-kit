#!/usr/bin/env bash
# run-matrix.sh — matrix runner for tdd-contract-review benchmark
#
# Loops every unit declared in expected_gaps.yaml, finds the latest run dir for
# each under sample-app/tdd-contract-review/*-<slug>/, then grades each via
# both grade-content.sh (Category A — content) and grade-shape.sh (Category B — shape).
#
# Usage:
#   ./run-matrix.sh                         # grade every unit that has a run dir
#   ./run-matrix.sh --strict                # also fail if a unit has no run dir
#   ./run-matrix.sh --unit <slug>           # grade one unit only
#   ./run-matrix.sh --prune-old N           # also rm older WORK_DIRs per slug,
#                                           # keeping the most recent N. Off by
#                                           # default. Touches only intermediate
#                                           # work dirs under WORK_DIRS_ROOT;
#                                           # never touches in-repo OUT_DIRs.
#
# Outputs:
#   - console pass/fail matrix (one row per unit × category)
#   - benchmark/last-eval.json (machine-readable summary; git-ignored)
#   - exit 0 iff every graded case passed
#
# Requires: jq, python3. Fails loud if missing.

# NOTE: intentionally NOT using `set -e`. This script runs grade-content.sh +
# grade-shape.sh across every unit and records each result — a single case
# failure must not abort the matrix. Per-command errors are checked explicitly
# via exit codes below.
set -uo pipefail

die() { echo "✗ $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
command -v python3 >/dev/null 2>&1 || die "python3 is required but not installed"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_FILE="$SCRIPT_DIR/expected_gaps.yaml"
# OUT_DIRS_ROOT — where the in-repo deliverables (report.md + findings.json)
# land when the skill runs against sample-app. Each unit gets a sibling
# folder here named {YYYYMMDD-HHMM}-{slug}/.
OUT_DIRS_ROOT="$SCRIPT_DIR/sample-app/tdd-contract-review"
# WORK_DIRS_ROOT — where the skill writes intermediates since v0.51 (outside
# the repo, persistent across reboots, kept out of PRs).
WORK_DIRS_ROOT="$HOME/.claude/tdd-contract-review/runs"
CONTENT_SCRIPT="$SCRIPT_DIR/grade-content.sh"
SHAPE_SCRIPT="$SCRIPT_DIR/grade-shape.sh"
PARSER="$SCRIPT_DIR/parse_expected.py"
SUMMARY_FILE="$SCRIPT_DIR/last-eval.json"

[[ -f "$EXPECTED_FILE" ]]   || die "expected_gaps.yaml not found at $EXPECTED_FILE"
[[ -x "$CONTENT_SCRIPT" ]]  || die "grade-content.sh not found or not executable at $CONTENT_SCRIPT"
[[ -x "$SHAPE_SCRIPT" ]]    || die "grade-shape.sh not found or not executable at $SHAPE_SCRIPT"
[[ -x "$PARSER" ]]          || die "parse_expected.py not found or not executable at $PARSER"

STRICT=0
ONLY_UNIT=""
PRUNE_KEEP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --unit)   ONLY_UNIT="${2:-}"; [[ -z "$ONLY_UNIT" ]] && die "--unit requires a slug"; shift 2 ;;
    --prune-old)
      PRUNE_KEEP="${2:-}"
      [[ "$PRUNE_KEEP" =~ ^[0-9]+$ ]] || die "--prune-old requires a non-negative integer (got: '${PRUNE_KEEP:-<empty>}')"
      shift 2
      ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --- extract unit slugs from expected_gaps.yaml (via shared parser) ---
ALL_UNITS=$("$SCRIPT_DIR/parse_expected.py" units "$EXPECTED_FILE")

[[ -n "$ALL_UNITS" ]] || die "no units declared in expected_gaps.yaml"

if [[ -n "$ONLY_UNIT" ]]; then
  if ! grep -qx "$ONLY_UNIT" <<< "$ALL_UNITS"; then
    die "unit '$ONLY_UNIT' not declared in expected_gaps.yaml"
  fi
  UNITS="$ONLY_UNIT"
else
  UNITS="$ALL_UNITS"
fi

# --- per-unit: find latest OUT_DIR (in-repo deliverables) ---
# The OUT_DIR's basename IS the RUN_ID, which we use to compute the matching
# WORK_DIR under $WORK_DIRS_ROOT. If the WORK_DIR is missing (e.g. pruned, or
# the run predates v0.51's split layout), grade-shape.sh will fail loudly on
# the missing intermediates — that's intentional: don't grade a half-deleted
# run.
find_latest_out() {
  local slug="$1"
  [[ -d "$OUT_DIRS_ROOT" ]] || return 1
  ls -1d "$OUT_DIRS_ROOT"/*-"$slug" 2>/dev/null | sort | tail -n 1
}

work_dir_for_out() {
  local out="$1"
  local run_id
  run_id="$(basename "$out")"
  echo "$WORK_DIRS_ROOT/$run_id"
}

# --- matrix state ---
TOTAL_CASES=0
PASS_CASES=0
FAIL_CASES=0
SKIP_CASES=0

declare -a ROWS=()           # "slug|out|work|a_status|b_status|a_log|b_log"
declare -a JSON_ENTRIES=()

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

record() {
  local slug="$1" out="$2" work="$3" a_status="$4" b_status="$5" a_detail="$6" b_detail="$7"
  ROWS+=("$slug|$out|$work|$a_status|$b_status|$a_detail|$b_detail")

  local out_esc work_esc a_detail_esc b_detail_esc
  out_esc=$(printf '%s' "$out" | json_escape)
  work_esc=$(printf '%s' "$work" | json_escape)
  a_detail_esc=$(printf '%s' "$a_detail" | json_escape)
  b_detail_esc=$(printf '%s' "$b_detail" | json_escape)
  JSON_ENTRIES+=("$(cat <<EOF
{
  "unit": "$slug",
  "out_dir": $out_esc,
  "work_dir": $work_esc,
  "category_a": { "status": "$a_status", "detail": $a_detail_esc },
  "category_b": { "status": "$b_status", "detail": $b_detail_esc }
}
EOF
)")
}

echo "━━━ run-matrix: tdd-contract-review benchmark ━━━"
echo "Expected units: $(echo "$UNITS" | wc -l | tr -d ' ')"
echo "Out dirs root:  $OUT_DIRS_ROOT"
echo "Work dirs root: $WORK_DIRS_ROOT"
[[ $STRICT -eq 1 ]] && echo "Strict mode: ON (missing run dirs count as failures)"
echo ""

# --- optional WORK_DIRS_ROOT prune (intermediates only) ---
# Keeps the most recent N work dirs per unit-slug, rm -rf's older ones.
# Never touches OUT_DIRS_ROOT (in-repo deliverables) — those are committed
# artifacts and only the user should curate them.
if [[ -n "$PRUNE_KEEP" ]]; then
  if [[ ! -d "$WORK_DIRS_ROOT" ]]; then
    echo "Prune: no WORK_DIRS_ROOT yet ($WORK_DIRS_ROOT) — nothing to prune."
  else
    PRUNED_TOTAL=0
    while IFS= read -r slug; do
      [[ -z "$slug" ]] && continue
      # Portable: collect candidates (sorted oldest → newest) into a newline list.
      CANDIDATES_LIST=$(ls -1d "$WORK_DIRS_ROOT"/*-"$slug" 2>/dev/null | sort)
      [[ -z "$CANDIDATES_LIST" ]] && continue
      KEEP_COUNT=$(printf '%s\n' "$CANDIDATES_LIST" | wc -l | tr -d ' ')
      if (( KEEP_COUNT > PRUNE_KEEP )); then
        DROP_COUNT=$((KEEP_COUNT - PRUNE_KEEP))
        # head -n DROP_COUNT yields the oldest entries; rm each.
        while IFS= read -r victim; do
          [[ -z "$victim" ]] && continue
          rm -rf -- "$victim"
          PRUNED_TOTAL=$((PRUNED_TOTAL + 1))
        done < <(printf '%s\n' "$CANDIDATES_LIST" | head -n "$DROP_COUNT")
      fi
    done <<< "$ALL_UNITS"
    echo "Prune: kept latest $PRUNE_KEEP per slug, removed $PRUNED_TOTAL older work dir(s) under $WORK_DIRS_ROOT."
    echo ""
  fi
fi

while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  TOTAL_CASES=$((TOTAL_CASES + 2))   # A + B per unit

  OUT_DIR=$(find_latest_out "$slug" || true)

  if [[ -z "$OUT_DIR" || ! -d "$OUT_DIR" ]]; then
    if [[ $STRICT -eq 1 ]]; then
      FAIL_CASES=$((FAIL_CASES + 2))
      record "$slug" "<none>" "<none>" "FAIL" "FAIL" "no out dir (strict)" "no out dir (strict)"
    else
      SKIP_CASES=$((SKIP_CASES + 2))
      record "$slug" "<none>" "<none>" "SKIP" "SKIP" "no out dir" "no out dir"
    fi
    continue
  fi

  WORK_DIR=$(work_dir_for_out "$OUT_DIR")

  # Category A — grade-content.sh (only needs OUT_DIR; reads findings.json)
  A_LOG=$("$CONTENT_SCRIPT" "$slug" "$OUT_DIR" 2>&1) && A_EXIT=0 || A_EXIT=$?
  A_SUMMARY=$(grep -E '^━━━ Score:' <<< "$A_LOG" | tail -n 1 | sed 's/━//g; s/^ *//; s/ *$//')
  [[ -z "$A_SUMMARY" ]] && A_SUMMARY="grade-content.sh failed to produce a score"

  if [[ $A_EXIT -eq 0 ]]; then
    PASS_CASES=$((PASS_CASES + 1))
    A_STATUS="PASS"
  else
    FAIL_CASES=$((FAIL_CASES + 1))
    A_STATUS="FAIL"
  fi

  # Category B — grade-shape.sh (needs both: WORK_DIR for intermediates, OUT_DIR for deliverables)
  B_LOG=$("$SHAPE_SCRIPT" "$WORK_DIR" "$OUT_DIR" 2>&1) && B_EXIT=0 || B_EXIT=$?
  B_SUMMARY=$(grep -iE '^━━━ shape:' <<< "$B_LOG" | tail -n 1 | sed 's/━//g; s/^ *//; s/ *$//')
  [[ -z "$B_SUMMARY" ]] && B_SUMMARY="grade-shape.sh failed to produce a score"

  if [[ $B_EXIT -eq 0 ]]; then
    PASS_CASES=$((PASS_CASES + 1))
    B_STATUS="PASS"
  else
    FAIL_CASES=$((FAIL_CASES + 1))
    B_STATUS="FAIL"
  fi

  record "$slug" "$OUT_DIR" "$WORK_DIR" "$A_STATUS" "$B_STATUS" "$A_SUMMARY" "$B_SUMMARY"
done <<< "$UNITS"

# --- print matrix ---
printf "%-30s %-6s %-6s %s\n" "UNIT" "A" "B" "DETAIL"
printf "%-30s %-6s %-6s %s\n" "------------------------------" "------" "------" "------"
for row in "${ROWS[@]}"; do
  IFS='|' read -r slug out work a b a_detail b_detail <<< "$row"
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
