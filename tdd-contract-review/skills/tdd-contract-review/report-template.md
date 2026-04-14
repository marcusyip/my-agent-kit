# Report Template Reference

Detailed guidance for Step 8 of the TDD Contract Review workflow.

## Report File Conventions

**One report per test file, written to separate files.** Each test file gets its own report file with its own contract extraction, test structure tree, gap analysis, and score. A summary file is also written.

**Write reports to `tdd-contract-review/{datetime}-report/`** in the project root (create it if it doesn't exist). Use the current date and time for `{datetime}` in `YYYYMMDD-HHMM` format (e.g. `tdd-contract-review/20260412-1630-report/`). Get the current time by running `date +%Y%m%d-%H%M` via Bash. File naming convention:
- Per-file reports: kebab-case of the test file name, e.g. `tdd-contract-review/20260412-1630-report/post-transactions-spec.md`
- Summary: `tdd-contract-review/20260412-1630-report/summary.md`

Do all analysis (reading files, extracting contracts, auditing tests) first, then write all report files.

**If file writes are blocked**, fall back to printing all reports inline in a single response. Do not retry blocked writes.

If a test file contains multiple endpoints (anti-pattern), still produce one report for that file but flag the multi-endpoint issue prominently.

## Scoring

Score each report across 6 categories:

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
- **9-10 (STRONG):** Every contract field has a test group. Happy paths assert all response fields + DB state. All enum values covered. External API mocked with success/failure/timeout. No anti-patterns. Rare -- most mature codebases top out at 8.
- **7 (ADEQUATE):** Most contract fields tested. Happy paths exist but may miss some response fields. A few enum values or edge cases missing. Minor anti-patterns (e.g., some status-only assertions).
- **5 (NEEDS IMPROVEMENT):** Core fields tested but significant gaps: missing error path coverage, incomplete happy path assertions, untested endpoints, no external API scenarios.
- **2-3 (WEAK):** Minimal tests exist. Most contract fields untested. No test foundation pattern. Status-only assertions throughout. Major features have zero coverage.

## Full Report Template

```markdown
## TDD Contract Review: [test file path]

**Test file:** [e.g. spec/requests/api/v1/post_transactions_spec.rb]
**Endpoint:** [e.g. POST /api/v1/transactions]
**Source files:** [list of source files this test covers]
**Framework:** [detected framework and language]

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every API endpoint, job, and message consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `✓` = scenario is tested
- `✗` = scenario is missing (potential silent breakage)
- Each entry point (endpoint, job, consumer) gets its own section
- Fields use typed prefixes: `request field:` (user input), `request header:` (HTTP headers), `db field:` (database state), `outbound response field:` (response handling + outbound params + DB assertions)
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**One endpoint per file:** Each API endpoint, job, or consumer should have its own test file. This makes gaps immediately visible — if a file doesn't exist, the entire contract is untested.

**Contract boundary:** Tests should verify behavior at the contract boundary (API endpoint, job entry point), not internal implementation. Testing that a service method is called is implementation testing — testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have. A codebase with 100 tests that only check status codes scores lower than one with 20 tests that verify response fields, DB state, and error paths.

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

[Include the full contract extraction summary from Step 3. MUST include ALL contract types found: API (inbound) request/response fields, DB table fields and enum values, outbound API call params and response shapes, job/consumer payloads, UI props. If a contract type was extracted in Step 3, it MUST appear here. Do not omit DB or outbound contracts.]

### Fintech Dimensions Summary

When fintech mode is active, include this table in every per-file report. Copy the status from the Step 3 extraction template. For "Not detected" dimensions, show the gap count from the absence flagging in Step 6. For "Not applicable" dimensions, show "—" in both Fields and Gaps columns.

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | 4 fields | 2 HIGH, 1 MEDIUM |
| 2 | Idempotency | Extracted | 2 fields | 1 HIGH |
| 3 | Transaction State Machine | Not detected — flagged | — | Infrastructure gap |
| 4 | Balance & Ledger Integrity | Extracted | 3 fields | 1 HIGH, 2 MEDIUM |
| 5 | External Payment Integrations | Not applicable | — | — |
| 6 | Regulatory & Compliance | Not detected — flagged | — | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Not detected — flagged | — | Infrastructure gap |
| 8 | Security & Access Control | Extracted | 5 fields | 3 HIGH |

**Fintech mode:** Active — all 8 dimensions evaluated.

### Test Structure Tree

[See SKILL.md for the tree format rules and typed prefix gate]

### Contract Map

Every contract field from the extraction summary MUST appear in this table — each field gets its own row, reviewed 1 by 1. The Type column MUST use the same typed prefixes as the Test Structure Tree: `request field`, `request header`, `db field`, `outbound response field`, `prop`. Do not use `Security`, `Business rule`, or generic labels. **Cross-reference Checkpoint 1:** the number of rows per contract type in this table must be consistent with the Fields Found count from Checkpoint 1. If Checkpoint 1 shows 8 DB fields extracted but the Contract Map has fewer than 8 DB rows, fields were dropped — go back and add the missing rows.

| Type | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)
- [ ] `[typed prefix]: [field]` ([endpoint]) -- [gap description]

  Suggested test:
  [auto-generated test stub from Step 7]

**MEDIUM** (tested but missing scenarios)
- [ ] ...

**LOW** (rare corner cases)
- [ ] ...

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|

### Top 5 Priority Actions

1. [Most impactful test to add, with the contract it protects]
2. [Second]
3. [Third]
4. [Fourth]
5. [Fifth]
```

## Multi-File Summary

When the scope includes multiple test files, write one report file per test file, then write `summary.md` in the same report directory.

**The summary is strictly a rollup.** Every finding, gap, anti-pattern, and recommendation MUST appear in a per-file report first. The summary MUST NOT contain details, findings, or analysis not already in a per-file report. If a finding doesn't belong to a specific test file (e.g. missing infrastructure, cross-cutting concerns), include it in the most relevant per-file report.

```markdown
## TDD Contract Review — Summary

| Test File | Endpoint | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|

**Missing test files** (source exists but no test file):
- [endpoint] — no test file exists

**Overall: X files reviewed, X HIGH gaps, X MEDIUM gaps**

### Fintech Dimensions (aggregated)

When fintech mode is active, aggregate the dimension status across all per-file reports:

| # | Dimension | Status | Files With Gaps | Total Gaps |
|---|-----------|--------|----------------|------------|
```

## Quick Mode Template

When quick mode is enabled (user passed `quick` as first argument), output only:

```markdown
## TDD Contract Review -- Quick Summary

**Score: X.X / 10** ([VERDICT])
**Scope:** [scope description]

### HIGH Priority Gaps ([count])
- `[contract]` field `[field]` ([confidence]) -- [gap description]
- ...

### Summary
- MEDIUM gaps: [count]
- LOW gaps: [count]
- Anti-patterns: [count]

Run `/tdd-contract-review [same scope]` for full report with auto-generated test stubs.
```
