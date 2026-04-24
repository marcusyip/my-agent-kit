<!-- version: 0.48.0 -->
# Report Template Reference

Detailed guidance for Step 7-8 of the TDD Contract Review workflow.

## Output Instructions

The Step 7-8 agent writes TWO files to `$RUN_DIR`:

1. **`report.md`** — human-readable scored report. Use the full template below by default. If quick mode is on, use the Quick Mode Template instead.
2. **`findings.json`** — machine-readable gap list for grade-content.sh + Step 9 deterministic check.

### report.md requirements

- Include a **Hygiene section** that surfaces the anti-patterns from `$RUN_DIR/02-audit.md` directly. These are test-code hygiene issues, not contract gaps.
- Every actionable item in the report must be a `- [ ]` checkbox so the reader can work through the report as one checklist. This applies to Gap Analysis (already), Anti-Patterns Detected, and Top 5 Priority Actions. No duplicate consolidated checklist at the end.
- Full report follows the template in "report.md Template" below. Quick mode follows "Quick Mode Template".

### Input files (Step 7-8 reads these)

- `$RUN_DIR/01-extraction.md` — contract extraction + Checkpoint 1 coverage table
- `$RUN_DIR/02-audit.md` — hygiene / anti-patterns
- `$RUN_DIR/03-index.md` — shell-generated gap index (counts + links, NOT content)
- `$RUN_DIR/03a-gaps-api.md`, `$RUN_DIR/03b-gaps-db.md`, `$RUN_DIR/03c-gaps-outbound.md` — per-type gap sub-files (present only when the type was Extracted at Checkpoint 1)
- `$RUN_DIR/03d-gaps-money.md`, `$RUN_DIR/03e-gaps-security.md` — cross-cutting sub-files (critical mode only)

`03-index.md` is shell-generated and contains NO gap bodies — Step 7-8 reads the sub-files directly for gap content, stubs, and trees.

### Dedupe rule (Step 7-8 responsibility)

F1 money and F2 security overlap with per-type A/B/C by design — the same field can be flagged by multiple sub-files. When composing `report.md` and `findings.json`, dedupe by `(field + failure-mode key phrase)`:

- Keep the **highest priority** across duplicates.
- **Combine descriptions** (preserve the unique angle from each sub-file).
- Use the **richer stub** (more assertions, more setup, or critical-mode coverage beats a thinner one).
- Do NOT edit the per-type sub-files on disk — dedupe lives in the final synthesis only.

### findings.json requirements

- Include **EVERY** gap from every sub-file that exists in `$RUN_DIR` (03a..03e) — all four priorities: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`. Do NOT drop MEDIUM or LOW.
- Include contract gaps (from per-type sub-reports 03a/03b/03c) AND critical-mode gaps (03d Money, 03e Security).
- After dedupe (see rule above), each `(field + failure-mode)` appears exactly once.
- Do NOT include hygiene / anti-pattern entries — those stay in `report.md` only.
- `findings.json` is still written in quick mode; quick mode only affects `report.md` rendering.

One unit per run, so there is no multi-file summary. `summary.md` does not exist in this workflow.

## findings.json Schema

```json
{
  "unit": "POST /api/v1/transactions",
  "critical": true,
  "gaps": [
    {
      "id": "G001",
      "priority": "HIGH",
      "field": "request field: amount",
      "type": "API inbound",
      "description": "No test for negative amount (should return 422)",
      "stub": "it 'returns 422 for negative amount' do\n  post '/api/v1/transactions', params: { amount: -1 }\n  expect(response.status).to eq(422)\n  expect(Transaction.count).to eq(0)\nend"
    }
  ]
}
```

**Field rules:**
- `id`: sequential `G001`, `G002`, ... unique per run
- `priority`: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW`
- `field`: typed prefix + field name (e.g., `db field: wallets.status`, `outbound response field: Stripe.Charge.status`, or `unit-level` for systemic Money/Security dimensions)
- `type`: one of `API inbound` | `DB` | `Outbound API` | `Jobs` | `UI Props` | `Money:<dimension>` | `Security:<dimension>`
- `description`: what's missing, plain English
- `stub`: test stub code. **REQUIRED for CRITICAL and HIGH gaps.** Optional for MEDIUM/LOW. Use `\n` for newlines in JSON.

Step 9 validates this file; invalid JSON or CRITICAL/HIGH gaps without stubs = FAIL.

## Scoring

Score the unit across 6 categories:

| Category | Weight | Focus |
|---|---|---|
| Contract Coverage | 25% | Are all contract fields tested? |
| Test Grouping | 15% | Grouped by feature > field for visible gaps? |
| Scenario Depth | 20% | Per field: edge cases, corner cases, error paths covered? |
| Test Case Quality | 15% | Assertion completeness, readability, meaningful data? |
| Isolation & Flakiness | 15% | Real DB, no state leakage, no flaky patterns, only external APIs mocked? |
| Anti-Patterns | 10% | Implementation testing, over-mocking, assert-free tests? |

**Verdicts:** STRONG (8-10) / ADEQUATE (6-7.9) / NEEDS IMPROVEMENT (4-5.9) / WEAK (0-3.9)

**Scoring calibration anchors:**
- **9-10 (STRONG):** Every contract field has a test group. Happy paths assert all response fields + DB state. All enum values covered. External API mocked with success/failure/timeout. No anti-patterns. Rare — most mature codebases top out at 8.
- **7 (ADEQUATE):** Most contract fields tested. Happy paths exist but may miss some response fields. A few enum values or edge cases missing. Minor anti-patterns (e.g., some status-only assertions).
- **5 (NEEDS IMPROVEMENT):** Core fields tested but significant gaps: missing error path coverage, incomplete happy path assertions, untested endpoints, no external API scenarios.
- **2-3 (WEAK):** Minimal tests exist. Most contract fields untested. No test foundation pattern. Status-only assertions throughout. Major features have zero coverage.

## report.md Template

```markdown
## TDD Contract Review: [unit identifier]

**Unit:** [e.g. POST /api/v1/transactions]
**Source file:** [resolved path]
**Test file(s):** [list]
**Framework:** [detected framework and language]
**Critical mode:** [yes / no]

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every endpoint, job, and consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `✓` = scenario is tested
- `✗` = scenario is missing (potential silent breakage)
- Fields use typed prefixes: `request field:` (user input), `request header:` (HTTP headers), `db field:` (database state), `outbound response field:` (response handling + outbound params + DB assertions)
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**Contract boundary:** Tests should verify behavior at the contract boundary (endpoint entry, job entry, consumer entry), not internal implementation. Testing that a service method is called is implementation testing. Testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have.

### Overall Score: X.X / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | X/10 | 25% | X.XX |
| Test Grouping | X/10 | 15% | X.XX |
| Scenario Depth | X/10 | 20% | X.XX |
| Test Case Quality | X/10 | 15% | X.XX |
| Isolation & Flakiness | X/10 | 15% | X.XX |
| Anti-Patterns | X/10 | 10% | X.XX |
| **Overall** | | | **X.XX** |

### Verdict: [STRONG | ADEQUATE | NEEDS IMPROVEMENT | WEAK]

### Contract Extraction Summary

[Copy from 01-extraction.md. MUST include ALL contract types found: API inbound request/response fields, DB table fields and enum values, outbound API call params and response shapes, job payloads, UI props. If a contract type was extracted, it MUST appear here.]

### Money-Correctness Dimensions Summary

[If critical mode is active, include this table. Otherwise omit this section entirely.]

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | 4 fields | 2 HIGH, 1 MEDIUM |
| 2 | Idempotency | Extracted | 2 fields | 1 HIGH |
| 3 | Transaction State Machine | Not detected — flagged | — | Infrastructure gap |
| 4 | Balance & Ledger Integrity | Extracted | 3 fields | 1 HIGH, 2 MEDIUM |
| 5 | Position & Inventory | Not applicable | — | — |
| 6 | External Payment Integrations | Extracted | 3 fields | 1 MEDIUM |
| 7 | Refunds & Reversals | Not applicable | — | — |
| 8 | Fees & Tax | Not detected — flagged | — | Infrastructure gap |
| 9 | Holds & Authorizations | Not applicable | — | — |
| 10 | Time, Settlement & Cutoffs | Not detected — flagged | — | Infrastructure gap |
| 11 | FX & Currency Conversion | Not applicable | — | — |
| 12 | Concurrency & Data Integrity | Not detected — flagged | — | Infrastructure gap |
| 13 | Transaction Limits | Extracted | 1 field | 1 MEDIUM |

### API-Security Dimensions Summary

[If critical mode is active, include this table. Otherwise omit this section entirely.]

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Security & Access Control | Extracted | 5 fields | 3 HIGH |
| 2 | Audit Trail & Immutable Records | Not detected — flagged | — | Infrastructure gap |
| 3 | Regulatory & Compliance (KYC/AML/PCI) | Not detected — flagged | — | Infrastructure gap |
| 4 | Webhook & Callback Trust | Not applicable | — | — |

### Test Structure Tree

[See staff-engineer.md for the tree format rules and typed prefix gate]

### Contract Map

Every contract field from the extraction summary MUST appear in this table — each field gets its own row, reviewed 1 by 1. The Type column MUST use typed prefixes: `request field`, `request header`, `db field`, `outbound response field`, `prop`. **Cross-reference Checkpoint 1:** row count per type must match the Fields Found count from Checkpoint 1.

| Type | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|

### Gap Analysis by Priority

**CRITICAL** (data loss, security breach, or money off — MUST have stubs in findings.json)
- [ ] `[typed prefix]: [field]` — [gap description]

  Suggested test:
  ```
  [auto-generated test stub]
  ```

**HIGH** (core contract fields with no tests — MUST have stubs in findings.json)
- [ ] ...

**MEDIUM** (tested but missing scenarios)
- [ ] ...

**LOW** (rare corner cases)
- [ ] ...

### Anti-Patterns Detected

Each anti-pattern is a `- [ ]` checkbox so the reader works the report as one checklist. Hygiene fixes land before filling contract gaps — structural issues block clean coverage.

- [ ] **AP1 — [anti-pattern name]** (Severity: [CRITICAL/HIGH/MEDIUM/LOW]) — Location: `[path:line]`. Fix: [one-line fix].
- [ ] **AP2 — ...**
- ...

### Top 5 Priority Actions

Highest-leverage work first. Check items off as you land them.

- [ ] **1.** [Most impactful test to add, with the contract it protects]
- [ ] **2.** [Second]
- [ ] **3.** [Third]
- [ ] **4.** [Fourth]
- [ ] **5.** [Fifth]
```

## Quick Mode Template

When quick mode is enabled (user passed `quick` as an argument), `report.md` is abbreviated to:

```markdown
## TDD Contract Review — Quick Summary

**Unit:** [unit identifier]
**Score: X.X / 10** ([VERDICT])
**Critical mode:** [yes/no]

### HIGH Priority Gaps ([count])
- `[typed prefix]: [field]` — [gap description]
- ...

### Summary
- MEDIUM gaps: [count]
- LOW gaps: [count]
- Anti-patterns: [count]

Run `/tdd-contract-review [unit]` without `quick` for the full report with auto-generated test stubs.
```

`findings.json` is STILL written in quick mode — it's the machine-readable output, not a rendering choice.
