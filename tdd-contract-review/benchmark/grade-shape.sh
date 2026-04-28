#!/usr/bin/env bash
# grade-shape.sh — grade Category B (shape) of ONE unit's run via structural
# invariants on the JSON artifacts. Paired with grade-content.sh (Category A).
#
# Usage:
#   ./grade-shape.sh <work-dir> <out-dir>
#
# Since v0.51 the skill writes intermediates to $WORK_DIR
# (~/.claude/tdd-contract-review/runs/{RUN_ID}/) and only the two committable
# deliverables (report.md, findings.json) to $OUT_DIR
# (tdd-contract-review/{RUN_ID}/). This grader reads from both:
#   - WORK_DIR  → 01-extraction.json, 02-audit.json, 03*-gaps-*.json,
#                 03-index.md, report.json
#   - OUT_DIR   → findings.json, report.md
#
# JSON-first: the source of truth for every numbered artifact is its `.json`
# file (schema-validated at write time by the renderer). This grader reads
# those JSONs with jq so the checks are decoupled from MD wording drift.
# `03-index.md` is still shell-generated MD and is checked directly;
# `report.md` is checked only for render-smoke (non-empty).
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (full list printed)
#   2 — wrong usage or missing dependency

set -uo pipefail

die() { echo "✗ $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not installed"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <work-dir> <out-dir>" >&2
  echo "  work-dir: ~/.claude/tdd-contract-review/runs/{RUN_ID}/ (intermediates)" >&2
  echo "  out-dir:  tdd-contract-review/{RUN_ID}/                (deliverables)" >&2
  exit 2
fi

WORK_DIR="${1%/}"
OUT_DIR="${2%/}"
[[ -d "$WORK_DIR" ]] || die "work directory not found: $WORK_DIR"
[[ -d "$OUT_DIR" ]]  || die "out directory not found: $OUT_DIR"

# Deliverables (committable, in-repo)
FINDINGS="$OUT_DIR/findings.json"
REPORT_MD="$OUT_DIR/report.md"
# Intermediates (~/.claude, not committed)
EXTRACTION_JSON="$WORK_DIR/01-extraction.json"
AUDIT_JSON="$WORK_DIR/02-audit.json"
REPORT_JSON="$WORK_DIR/report.json"
INDEX="$WORK_DIR/03-index.md"

PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()

check() {
  local id="$1" desc="$2" expr="$3"
  if eval "$expr" >/dev/null 2>&1; then
    printf "  \033[32m✓\033[0m %-5s %s\n" "$id" "$desc"
    PASSED=$((PASSED + 1))
  else
    printf "  \033[31m✗\033[0m %-5s %s\n" "$id" "$desc"
    FAILED=$((FAILED + 1))
    FAILURES+=("$id")
  fi
}

skip() {
  local id="$1" desc="$2" reason="$3"
  printf "  \033[33m-\033[0m %-5s %s  (skipped: %s)\n" "$id" "$desc" "$reason"
  SKIPPED=$((SKIPPED + 1))
}

echo "━━━ grade-shape: $OUT_DIR (intermediates: $WORK_DIR) ━━━"
echo ""

# Shared: known gap type enum (must match _defs.schema.json#/$defs/gapTypeCategory).
GAP_TYPE_ENUM='["API inbound","DB","Outbound API","Jobs","UI Props","Fintech:Money","Fintech:Idempotency","Fintech:StateMachine","Fintech:BalanceLedger","Fintech:ExternalIntegration","Fintech:Compliance","Fintech:Concurrency","Fintech:Security"]'

# ─────────────────────────────────────────────────────────────────────────────
# findings.json — merged gap list (authoritative machine-readable output)
# ─────────────────────────────────────────────────────────────────────────────

echo "findings.json:"

if [[ ! -f "$FINDINGS" ]]; then
  check B1 "findings.json exists" "false"
  for id in B2 B3 B4 B5 B6; do
    skip "$id" "(depends on B1)" "findings.json missing"
  done
else
  check B1 "findings.json is valid JSON" \
    "jq empty '$FINDINGS'"

  check B2 "top-level keys: unit (string), gaps (array); optional fintech/critical are booleans" \
    "jq -e '(.unit | type == \"string\") and (.gaps | type == \"array\") and ((.fintech == null) or (.fintech | type == \"boolean\")) and ((.critical == null) or (.critical | type == \"boolean\"))' '$FINDINGS'"

  check B3 "every gap has required fields (id, priority, field, type, description) + id matches ^G(API|DB|OUT|MON|SEC|FIN)-\\d{3}$" \
    "jq -e '.gaps | all(has(\"id\") and has(\"priority\") and has(\"field\") and has(\"type\") and has(\"description\") and (.id | test(\"^G(API|DB|OUT|MON|SEC|FIN)-[0-9]{3}$\")))' '$FINDINGS'"

  check B4 "every CRITICAL gap has a non-empty stub (HIGH/MEDIUM/LOW do not require one)" \
    "jq -e '[.gaps[] | select(.priority == \"CRITICAL\") | select((.stub // \"\") == \"\")] | length == 0' '$FINDINGS'"

  check B5 "every gap type is in the _defs enum (gapTypeCategory)" \
    "jq --argjson enum '$GAP_TYPE_ENUM' -e '[.gaps[] | select((.type as \$t | \$enum | index(\$t)) == null)] | length == 0' '$FINDINGS'"

  check B6 "no gap description mentions hygiene / anti-pattern (those belong in audit.json)" \
    "jq -e '[.gaps[] | select((.description // \"\") | test(\"hygiene|anti[- ]?pattern\"; \"i\"))] | length == 0' '$FINDINGS'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 01-extraction.json — Checkpoint 1 shape (against schema invariants)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "01-extraction.json:"

if [[ ! -f "$EXTRACTION_JSON" ]]; then
  check B7 "01-extraction.json exists" "false"
  for id in B8 B9; do
    skip "$id" "(depends on B7)" "01-extraction.json missing"
  done
else
  check B7 "01-extraction.json has required top-level keys (unit, framework, files_examined, coverage_table, contracts)" \
    "jq -e 'has(\"unit\") and has(\"framework\") and has(\"files_examined\") and has(\"coverage_table\") and has(\"contracts\")' '$EXTRACTION_JSON'"

  check B8 "coverage_table has 5 rows with exact contract_type labels + 3-state status" \
    "jq -e '
       (.coverage_table | length == 5)
       and ([.coverage_table[].contract_type] | sort == [\"API inbound\",\"DB\",\"Jobs\",\"Outbound API\",\"UI Props\"])
       and ([.coverage_table[] | select((.status | IN(\"Extracted\",\"Not detected\",\"Not applicable\")) | not)] | length == 0)
     ' '$EXTRACTION_JSON'"

  check B9 "files_examined.source is a non-empty array (mandatory); other groups (db_schema/outbound_clients/other) are arrays if present" \
    "jq -e '
       (.files_examined.source | type == \"array\") and (.files_examined.source | length > 0)
       and ((.files_examined.db_schema // []) | type == \"array\")
       and ((.files_examined.outbound_clients // []) | type == \"array\")
       and ((.files_examined.other // []) | type == \"array\")
     ' '$EXTRACTION_JSON'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 02-audit.json — audit sections + reconciliation
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "02-audit.json:"

if [[ ! -f "$AUDIT_JSON" ]]; then
  check B10 "02-audit.json exists" "false"
  for id in B11 B12; do
    skip "$id" "(depends on B10)" "02-audit.json missing"
  done
else
  check B10 "02-audit.json has required top-level keys (unit, files_reviewed, test_inventory, anti_patterns, per_field_coverage)" \
    "jq -e 'has(\"unit\") and has(\"files_reviewed\") and has(\"test_inventory\") and has(\"anti_patterns\") and has(\"per_field_coverage\")' '$AUDIT_JSON'"

  check B11 "test_inventory.grep_count == test_inventory.agent_count (reconciliation)" \
    "jq -e '.test_inventory.grep_count == .test_inventory.agent_count' '$AUDIT_JSON'"

  check B12 "audit.json has no gaps[] or scorecard keys (those belong to findings/report)" \
    "jq -e '(.gaps == null) and (.scorecard == null)' '$AUDIT_JSON'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Per-type sub-files — Step 6b output (JSON is source of truth)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "per-type gap sub-files:"

# Which types are Extracted at Checkpoint 1? Read from extraction.json.
extracted_types=""
if [[ -f "$EXTRACTION_JSON" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && extracted_types+="$line"$'\n'
  done < <(jq -r '
    .coverage_table[]
    | select(.status == "Extracted")
    | .contract_type as $t
    | (if $t == "API inbound" then "API inbound|03a-gaps-api|GAPI"
       elif $t == "DB" then "DB|03b-gaps-db|GDB"
       elif $t == "Outbound API" then "Outbound API|03c-gaps-outbound|GOUT"
       else empty end)
  ' "$EXTRACTION_JSON" 2>/dev/null)
fi

if [[ -z "$extracted_types" ]]; then
  skip B13 "per-type sub-file .json exists for each Extracted type" "no Extracted rows detected"
  skip B15 "per-type sub-file matches gaps-per-type.schema shape" "no Extracted rows"
  skip B16 "gap IDs use the right type prefix per sub-file" "no Extracted rows"
else
  missing_json=""
  bad_shape=""
  bad_prefix=""
  while IFS='|' read -r label base prefix; do
    [[ -z "$label" ]] && continue
    sub="$WORK_DIR/${base}.json"

    if [[ ! -f "$sub" ]]; then
      missing_json+="${base}.json "
      continue
    fi

    # Shape: has scope + gap_prefix + test_tree + contract_map + gaps, gap_prefix matches.
    if ! jq -e --arg p "$prefix" '
           has("scope") and has("gap_prefix") and has("test_tree") and has("contract_map")
           and (.gaps | type == "array")
           and (.gap_prefix == $p)
         ' "$sub" >/dev/null 2>&1; then
      bad_shape+="${base}.json "
    fi

    # Every gap id in this sub-file must use the expected prefix. `prefix` is
    # already the full literal (GAPI / GDB / GOUT), so concatenate as-is.
    if jq -e --arg p "$prefix" '
           [.gaps[] | select(.id | test("^" + $p + "-[0-9]{3}$") | not)] | length > 0
         ' "$sub" >/dev/null 2>&1; then
      bad_prefix+="${base}.json "
    fi
  done <<< "$extracted_types"

  check B13 "per-type sub-file .json exists for each Extracted type from Checkpoint 1" \
    "[[ -z '$missing_json' ]]"

  check B15 "per-type .json has scope + gap_prefix + test_tree + contract_map + gaps[]" \
    "[[ -z '$bad_shape' ]]"

  check B16 "gap IDs use the right type prefix per sub-file (GAPI/GDB/GOUT)" \
    "[[ -z '$bad_prefix' ]]"
fi

# B14: critical-mode sub-files exist as JSON when fintech/critical mode is on.
if [[ -f "$FINDINGS" ]]; then
  is_critical=$(jq -r '(.critical // .fintech // false)' "$FINDINGS")
  if [[ "$is_critical" == "true" ]]; then
    check B14 "critical mode: 03d-gaps-money.json and 03e-gaps-security.json exist" \
      "[[ -f '$WORK_DIR/03d-gaps-money.json' && -f '$WORK_DIR/03e-gaps-security.json' ]]"
  else
    skip B14 "critical-mode sub-files present" "unit is not critical mode"
  fi
else
  skip B14 "critical-mode sub-files present" "findings.json missing, cannot tell critical mode"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 03-index.md — shell-generated index (still MD, not a rendered JSON artifact)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "03-index.md:"

if [[ ! -f "$INDEX" ]]; then
  check B17 "03-index.md exists" "false"
  skip B18 "Checkpoint 3: every Extracted type shows Yes in Gaps Checked" "03-index.md missing"
else
  check B17 "contains ## Summary + ## Checkpoint 3: Gap Coverage" \
    "grep -qE '^## Summary[[:space:]]*$' '$INDEX' && \
     grep -qE '^## Checkpoint 3: Gap Coverage[[:space:]]*$' '$INDEX'"

  if [[ -n "${extracted_types:-}" ]]; then
    bad_cp3=""
    while IFS='|' read -r label _ _; do
      [[ -z "$label" ]] && continue
      grep -qE "^\\| $label \\| Yes \\|" "$INDEX" || bad_cp3+="$label/ "
    done <<< "$extracted_types"

    check B18 "Checkpoint 3: every Extracted type from Checkpoint 1 shows Yes" \
      "[[ -z '$bad_cp3' ]]"
  else
    skip B18 "Checkpoint 3 row-for-row check" "no Extracted rows to verify"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# report.json + report.md (source of truth + render smoke)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "report.{json,md}:"

if [[ ! -f "$REPORT_JSON" ]]; then
  check B19 "report.json exists and has 6 categories + verdict + overall_score" "false"
  skip B21 "report.md exists and is non-empty (render smoke)" "report.json missing"
else
  check B19 "report.json has 6 categories + overall_score + verdict in enum" \
    "jq -e '
       (.categories | type == \"array\") and (.categories | length == 6)
       and (.overall_score | type == \"number\")
       and (.overall_score >= 0 and .overall_score <= 10)
       and (.verdict | IN(\"WEAK\",\"OK\",\"STRONG\"))
     ' '$REPORT_JSON'"

  check B21 "report.md exists and is non-empty" \
    "[[ -s '$REPORT_MD' ]]"
fi

# B20: at least one gap per Extracted type in findings.json.
if [[ -f "$FINDINGS" && -n "${extracted_types:-}" ]]; then
  missing_coverage=""
  while IFS='|' read -r label _ _; do
    [[ -z "$label" ]] && continue
    # Exact match on the type field; Fintech:* lives in separate sub-files, not A/B/C.
    if ! jq -e --arg t "$label" '.gaps | any(.type == $t)' "$FINDINGS" >/dev/null 2>&1; then
      missing_coverage+="$label "
    fi
  done <<< "$extracted_types"

  check B20 "at least one gap per Extracted type in findings.json" \
    "[[ -z '$missing_coverage' ]]"
else
  skip B20 "per-type gap coverage" "findings.json or Extracted types unavailable"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "━━━ shape: $PASSED passed, $FAILED failed, $SKIPPED skipped ━━━"
if [[ "$FAILED" -gt 0 ]]; then
  echo "FAILED: ${FAILURES[*]}"
  exit 1
fi
exit 0
