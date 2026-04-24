#!/usr/bin/env bash
# grade-shape.sh — grade Category B (shape) of ONE unit's run via structural invariants.
# Paired with grade-content.sh (Category A). Both are invoked per unit by run-matrix.sh.
#
# Usage:
#   ./grade-shape.sh <run-dir>
#
# Runs ~20 cheap bash/jq assertions against the files a run produces. Catches
# regressions that content grading (grade-content.sh) misses — dropped sections,
# renamed schema keys, missing sub-files, unreconciled counts.
#
# See test-plan.md (Category B) for the full assertion catalogue.
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (full list printed)
#   2 — wrong usage or missing dependency

set -uo pipefail

die() { echo "✗ $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not installed"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <run-dir>" >&2
  exit 2
fi

RUN_DIR="${1%/}"
[[ -d "$RUN_DIR" ]] || die "run directory not found: $RUN_DIR"

FINDINGS="$RUN_DIR/findings.json"
EXTRACTION="$RUN_DIR/01-extraction.md"
AUDIT="$RUN_DIR/02-audit.md"
INDEX="$RUN_DIR/03-index.md"
REPORT="$RUN_DIR/report.md"

PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()

check() {
  # check "<id>" "<description>" "<shell expression — pass on exit 0>"
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
  # skip "<id>" "<description>" "<reason>"
  local id="$1" desc="$2" reason="$3"
  printf "  \033[33m-\033[0m %-5s %s  (skipped: %s)\n" "$id" "$desc" "$reason"
  SKIPPED=$((SKIPPED + 1))
}

echo "━━━ grade-shape: $RUN_DIR ━━━"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# findings.json — schema
# ─────────────────────────────────────────────────────────────────────────────

echo "findings.json:"

if [[ ! -f "$FINDINGS" ]]; then
  check B1 "findings.json exists" "false"
  # The remaining findings checks can't run; skip them loudly so they're visible.
  for id in B2 B3 B4 B5 B6; do
    skip "$id" "(depends on B1)" "findings.json missing"
  done
else
  check B1 "findings.json is valid JSON" \
    "jq empty '$FINDINGS'"

  check B2 "top-level keys: unit (string), critical (bool), gaps (array)" \
    "jq -e '(.unit | type == \"string\") and (.critical | type == \"boolean\") and (.gaps | type == \"array\")' '$FINDINGS'"

  check B3 "every gap has id, priority, field, type, description" \
    "jq -e '.gaps | all(has(\"id\") and has(\"priority\") and has(\"field\") and has(\"type\") and has(\"description\"))' '$FINDINGS'"

  check B4 "every CRITICAL gap has a non-empty stub (HIGH/MEDIUM/LOW do not require one)" \
    "jq -e '[.gaps[] | select(.priority == \"CRITICAL\") | select((.stub // \"\") == \"\")] | length == 0' '$FINDINGS'"

  check B5 "no gap type uses the old 'Fintech:' prefix (schema rename guard)" \
    "jq -e '[.gaps[] | select(.type | startswith(\"Fintech:\"))] | length == 0' '$FINDINGS'"

  check B6 "no gap description mentions hygiene / anti-pattern (those belong in report.md)" \
    "jq -e '[.gaps[] | select((.description // \"\") | test(\"hygiene|anti[- ]?pattern\"; \"i\"))] | length == 0' '$FINDINGS'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 01-extraction.md — Checkpoint 1 shape
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "01-extraction.md:"

if [[ ! -f "$EXTRACTION" ]]; then
  check B7 "01-extraction.md exists" "false"
  for id in B8 B9; do
    skip "$id" "(depends on B7)" "01-extraction.md missing"
  done
else
  check B7 "contains ## Summary, ## Files Examined, ## Checkpoint 1" \
    "grep -qE '^## Summary[[:space:]]*$' '$EXTRACTION' && grep -qE '^## Files Examined[[:space:]]*$' '$EXTRACTION' && grep -qE '^## Checkpoint 1:' '$EXTRACTION'"

  # Checkpoint 1 table: 5 exact row labels with a 3-state status.
  check B8 "Checkpoint 1 table has 5 rows with exact labels + 3-state status" \
    "grep -qE '^\\| API inbound \\| (Extracted|Not detected|Not applicable) \\|' '$EXTRACTION' && \
     grep -qE '^\\| DB \\| (Extracted|Not detected|Not applicable) \\|' '$EXTRACTION' && \
     grep -qE '^\\| Outbound API \\| (Extracted|Not detected|Not applicable) \\|' '$EXTRACTION' && \
     grep -qE '^\\| Jobs \\| (Extracted|Not detected|Not applicable) \\|' '$EXTRACTION' && \
     grep -qE '^\\| UI Props \\| (Extracted|Not detected|Not applicable) \\|' '$EXTRACTION'"

  check B9 "Files Examined has ### Call trees and ### Root set subsections" \
    "grep -qE '^### Call trees[[:space:]]*$' '$EXTRACTION' && \
     grep -qE '^### Root set[[:space:]]*$' '$EXTRACTION'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 02-audit.md — audit sections + reconciliation
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "02-audit.md:"

if [[ ! -f "$AUDIT" ]]; then
  check B10 "02-audit.md exists" "false"
  for id in B11 B12; do
    skip "$id" "(depends on B10)" "02-audit.md missing"
  done
else
  check B10 "contains ## Summary, ## Test Inventory, ## Per-Field Coverage Matrix" \
    "grep -qE '^## Summary' '$AUDIT' && grep -qE '^## Test Inventory' '$AUDIT' && grep -qE '^## Per-Field Coverage Matrix' '$AUDIT'"

  # Reconciliation: grep count MUST equal Test Inventory count in Summary. Extract both numbers.
  # COUPLED to the audit-template wording "Test files (grep count): ..., N test" / "Test Inventory (agent count): N".
  # Source of truth for that wording: skills/tdd-contract-review/SKILL.md and skills/tdd-contract-review/test-patterns.md.
  # If the template is reworded, update both the regex below and the template in lockstep.
  check B11 "Test files (grep count) == Test Inventory (agent count) in Summary" \
    "grep_count=\$(grep -oE 'Test files \\(grep count\\):[^,]*, ([0-9]+) test' '$AUDIT' | grep -oE '[0-9]+ test' | head -1 | grep -oE '[0-9]+'); \
     inv_count=\$(grep -oE 'Test Inventory \\(agent count\\): ([0-9]+)' '$AUDIT' | head -1 | grep -oE '[0-9]+'); \
     [[ -n \"\$grep_count\" && -n \"\$inv_count\" && \"\$grep_count\" == \"\$inv_count\" ]]"

  check B12 "02-audit.md does NOT contain ## Gaps or ## Scorecard (belong to later steps)" \
    "! grep -qE '^## (Gaps|Scorecard)' '$AUDIT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Per-type sub-files — Step 6b output
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "per-type gap sub-files:"

# Determine which types are Extracted in Checkpoint 1, then require the matching sub-file.
extracted_types=""
if [[ -f "$EXTRACTION" ]]; then
  # Grep each row; if status is "Extracted", the sub-file must exist.
  while read -r row_label sub_file expected_prefix; do
    if grep -qE "^\\| $row_label \\| Extracted \\|" "$EXTRACTION"; then
      extracted_types+="$row_label|$sub_file|$expected_prefix"$'\n'
    fi
  done <<EOF
API inbound|03a-gaps-api.md|GAPI
DB|03b-gaps-db.md|GDB
Outbound API|03c-gaps-outbound.md|GOUT
EOF
fi

if [[ -z "$extracted_types" ]]; then
  skip B13 "sub-files exist for each Extracted type" "no Extracted rows detected in Checkpoint 1"
  skip B15 "sub-files contain Test Structure Tree + Contract Map" "no Extracted rows"
  skip B16 "gap IDs use right type prefix per sub-file" "no Extracted rows"
else
  missing_files=""
  while IFS='|' read -r label file _; do
    [[ -z "$label" ]] && continue
    [[ -f "$RUN_DIR/$file" ]] || missing_files+="$file "
  done <<< "$extracted_types"

  check B13 "sub-file exists for each Extracted type from Checkpoint 1" \
    "[[ -z '$missing_files' ]]"

  # B15: each sub-file has the right section headers.
  bad_sections=""
  while IFS='|' read -r label file _; do
    [[ -z "$label" ]] && continue
    target="$RUN_DIR/$file"
    if [[ -f "$target" ]]; then
      grep -qE "^## Test Structure Tree \\($label\\)" "$target" || bad_sections+="$file:tree "
      grep -qE "^## Contract Map \\($label\\)" "$target" || bad_sections+="$file:map "
    fi
  done <<< "$extracted_types"

  check B15 "per-type sub-files have ## Test Structure Tree (<TYPE>) and ## Contract Map (<TYPE>)" \
    "[[ -z '$bad_sections' ]]"

  # B16: Gap IDs in each sub-file use the expected prefix. Skip if the sub-file doesn't exist.
  # Matches the gap-analysis.md grammar: `- **id**: G<PREFIX>-<NNN>`.
  bad_prefix=""
  while IFS='|' read -r label file prefix; do
    [[ -z "$label" ]] && continue
    target="$RUN_DIR/$file"
    if [[ -f "$target" ]]; then
      # Look for any "- **id**: G<something>-" that is NOT the expected prefix.
      if grep -oE '^- \*\*id\*\*: G[A-Z]+-[0-9]+' "$target" | grep -v "G${prefix}-" >/dev/null 2>&1; then
        bad_prefix+="$file "
      fi
    fi
  done <<< "$extracted_types"

  check B16 "gap IDs use the right type prefix per sub-file (GAPI/GDB/GOUT)" \
    "[[ -z '$bad_prefix' ]]"
fi

# B14: critical-mode sub-files.
if [[ -f "$FINDINGS" ]]; then
  is_critical=$(jq -r '.critical // false' "$FINDINGS")
  if [[ "$is_critical" == "true" ]]; then
    check B14 "critical mode: 03d-gaps-money.md and 03e-gaps-security.md exist" \
      "[[ -f '$RUN_DIR/03d-gaps-money.md' && -f '$RUN_DIR/03e-gaps-security.md' ]]"
  else
    skip B14 "critical-mode sub-files present" "unit is not critical mode"
  fi
else
  skip B14 "critical-mode sub-files present" "findings.json missing, cannot tell critical mode"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 03-index.md — shell-generated index + Checkpoint 2
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "03-index.md:"

if [[ ! -f "$INDEX" ]]; then
  check B17 "03-index.md exists" "false"
  skip B18 "Checkpoint 2: every Extracted type shows Yes in Gaps Checked" "03-index.md missing"
else
  check B17 "contains ## Summary + ## Checkpoint 2: Gap Coverage" \
    "grep -qE '^## Summary[[:space:]]*$' '$INDEX' && \
     grep -qE '^## Checkpoint 2: Gap Coverage[[:space:]]*$' '$INDEX'"

  # B18: every Extracted type in Checkpoint 1 must show 'Yes' in the Checkpoint 2 table.
  if [[ -n "${extracted_types:-}" ]]; then
    bad_cp2=""
    while IFS='|' read -r label _ _; do
      [[ -z "$label" ]] && continue
      grep -qE "^\\| $label \\| Yes \\|" "$INDEX" || bad_cp2+="$label/ "
    done <<< "$extracted_types"

    check B18 "Checkpoint 2: every Extracted type from Checkpoint 1 shows Yes" \
      "[[ -z '$bad_cp2' ]]"
  else
    skip B18 "Checkpoint 2 row-for-row check" "no Extracted rows to verify"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# report.md
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "report.md:"

check B19 "report.md exists and is non-empty" \
  "[[ -s '$REPORT' ]]"

# B20: at least one gap per Extracted type in findings.json.
if [[ -f "$FINDINGS" && -n "${extracted_types:-}" ]]; then
  missing_coverage=""
  while IFS='|' read -r label _ _; do
    [[ -z "$label" ]] && continue
    # Case-insensitive substring on the type field.
    if ! jq -e --arg t "$label" \
         '.gaps | any(.type | ascii_downcase | contains($t | ascii_downcase))' \
         "$FINDINGS" >/dev/null 2>&1; then
      # Allow an explicit coverage note in report.md.
      if ! grep -qiE "$label.*(covered|no gaps|complete)" "$REPORT" 2>/dev/null; then
        missing_coverage+="$label "
      fi
    fi
  done <<< "$extracted_types"

  check B20 "at least one gap per Extracted type (or explicit coverage note in report.md)" \
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
