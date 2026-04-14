---
name: tdd-contract-review
description: Contract-based test quality review. Extracts contracts from source code, maps test coverage per field, identifies gaps, produces a scored report with prioritized actions, and auto-generates test stubs for high-priority gaps.
argument-hint: "[path, file, or 'quick' for abbreviated output -- defaults to PR scope or project root]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.18.0
---

# TDD Contract Review

Contract-based test quality review using a multi-agent pipeline. Each agent has focused context for reliable output.

## Core Philosophy

Tests protect against breaking changes by verifying contracts -- the agreements between components about data shape, behavior, and error handling. A contract field without tests means changes to that field can break things silently.

**Rules to enforce:**
- Verify contracts, NOT implementation details
- Mock minimally -- ideally only external API calls
- Use real database -- never mock DB
- Group tests by feature > field so gaps are immediately visible
- Every contract field needs edge case coverage

## Typed Field Prefixes (enforced across all agents)

Every field in the Test Structure Tree and Contract Map MUST use one of these typed prefixes:
- `request field:` — user input validation (nil, invalid, boundary, etc.)
- `request header:` — HTTP headers (missing auth, expired token)
- `db field:` — pre-existing database state (suspended, insufficient balance, already exists)
- `outbound response field:` — external API response handling + outbound request param assertions + DB state after + upstream validation (mismatch, null, malformed)
- `prop:` — UI component props

**Do NOT use:** `field: X (request param)`, `security:`, `business:`, `external:`, `response body`, `DB assertions`. These are old formats. Use the typed prefixes above.

Every field is reviewed 1 by 1. DB fields and outbound response fields get the same per-field treatment as request fields.

**Assertion rules per scenario type:**
- Error scenarios: assert status code + no DB write + no outbound API call + no data leak in error response
- Success scenarios: assert status code + response fields + DB state + outbound params sent
- Outbound response scenarios: assert DB state after change + validate upstream response fields (mismatch, null)

## Review Workflow

### Step 1: Determine Scope

Resolve `$ARGUMENTS` to find test and source files.

**Parsing rules:** split `$ARGUMENTS` on whitespace. If the first token is `quick`, enable quick mode and use remaining tokens for scope. Otherwise all tokens are scope (file path or directory).

- **`quick` keyword**: Enable quick mode (abbreviated output). Use remaining arguments for scope, or default to PR-scoped/project.
- **Specific test file**: review that file, locate its source
- **Source file**: find corresponding test files
- **Directory**: find all test files in that tree
- **No argument + on a non-default branch**: PR-scoped mode. Use `git diff` against the base branch to find changed source files. Extract contracts from changed source files, check the ENTIRE test suite for coverage.
- **No argument + on default branch**: review the entire project test suite

Locate test files by convention:
- Same directory: `foo.test.ts`, `foo.spec.ts`, `foo_test.go`, `foo_spec.rb`
- Parallel directories: `__tests__/`, `test/`, `tests/`, `spec/`
- Go: `foo_test.go` in the same package

### Step 2: Discovery

1. **Find test files.** Glob for `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}`, `**/*_test.go`, `**/*_spec.rb`, `**/*.test.py`, `**/test_*.py`
2. **Detect test framework.** Read test files to identify framework from imports and syntax.
3. **Find source files.** Include controllers/handlers, jobs (`app/jobs/`, `app/workers/`), and message consumers (`app/consumers/`).
4. **Check project conventions.** Read CLAUDE.md, jest.config, .rspec, Makefile.
5. **Detect mixed frameworks.**
6. **Detect fintech domain.** Scan for money/amount/balance/currency fields, payment gateway integrations, decimal/money types, idempotency key params, ledger patterns. If detected, enable **fintech mode**.

### Step 3: Contract Extraction (Agent 1)

Read `contract-extraction.md` (in the same directory as this file). Then dispatch an Agent with description "Contract extraction" and a prompt containing:

1. The full content of `contract-extraction.md`
2. If fintech mode detected, also read and include `fintech-checklists.md` (extraction sections only: "Contract Extraction Details" through "Security & Access Control")
3. The list of source file paths found in Step 2
4. The instruction: "Read every source file listed. Extract all contracts following the guidance. Produce a Contract Extraction Summary. Then fill in the Checkpoint 1 table (mandatory, every row). If fintech mode, also fill in the Fintech Dimension Template (mandatory, every row). Use the three-state enum: Extracted / Not detected / Not applicable (with rationale). Output the complete extraction summary, Checkpoint 1 table, and fintech dimensions table."

The Checkpoint 1 table the agent must produce:

| # | Contract Type | Status | Fields Found | Source Files Read |
|---|---------------|--------|-------------|-------------------|
| 1 | API (inbound) | [status] | [count] | [files] |
| 2 | DB (models/schema) | [status] | [count] | [files] |
| 3 | Outbound API calls (request params + response fields) | [status] | [count] | [files] |
| 4 | Jobs/consumers | [status] | [count] | [files] |
| 5 | UI props | [status] | [count] | [files] |

**GATE:** Verify the agent's output contains a Checkpoint 1 table with all 5 rows filled. If any "Extracted" row shows 0 fields, ask the agent to re-read the source files. If total fields < 10, re-read. Do not proceed until verified.

Save the agent's full output as `$EXTRACTION`.

### Step 4-5: Test Audit (Agent 2)

Read `test-patterns.md` (in the same directory as this file). Then dispatch an Agent with description "Test structure audit" and a prompt containing:

1. The full content of `test-patterns.md`
2. The typed prefix rules from the "Typed Field Prefixes" section above (copy them into the prompt)
3. The assertion rules: "Error scenarios: assert status code + no DB write + no outbound API call + no data leak in error response. Success scenarios: assert status code + response fields + DB state + outbound params sent."
4. The list of test file paths found in Step 2
5. The `$EXTRACTION` output from Agent 1 (so the auditor knows which contracts to check coverage for)
6. The instruction: "Read every test file listed. Audit test structure (sessions pattern, one endpoint per file, test foundation). Audit test case quality (assertion completeness, readability, isolation, flaky patterns). Flag anti-patterns with file:line references. For each contract field from the extraction, note whether a test group exists and what scenarios are covered. Output: test structure audit findings, quality issues, anti-patterns list, and per-field coverage notes."

Save the agent's full output as `$AUDIT`.

### Step 6: Gap Analysis (Agent 3)

Read `fintech-checklists.md` (in the same directory as this file), specifically the "Gap Analysis Scenario Checklists" section. Then dispatch an Agent with description "Gap analysis" and a prompt containing:

1. The gap analysis rules (copy from below into the prompt):
   - For each field, check by prefix type:
     - `request field:` — null/nil, empty, zero, boundary, invalid type/format, very large, permission denied
     - `request header:` — missing, expired, malformed
     - `db field:` — record not exists, belongs to another user, suspended/inactive, insufficient balance, already exists (duplicate)
     - `outbound response field:` — success, error, timeout, mismatch (amount/currency differs from sent), null/missing, malformed response + assert outbound request params + DB state after change
   - Priority: HIGH = no tests at all, MEDIUM = missing scenarios, LOW = rare corner cases
2. The common field type scenarios (pagination, date/time, string format, file upload):
   - Pagination: zero, negative, very large limit, beyond last page, default values
   - Date/time: invalid format, future/past constraints, timezone, boundaries
   - String format: valid, invalid, edge, max length, empty vs null
   - File upload: too large, wrong MIME, empty, missing
3. If fintech mode, the full fintech gap analysis categories (1-8):
   - Money/amount, Idempotency, State machine, Balance/ledger, Concurrency, Outbound response validation, Security & access control, Absence flagging
   - Include the fintech checklists content
4. The `$EXTRACTION` output from Agent 1
5. The `$AUDIT` output from Agent 2
6. The instruction: "For every contract field from the extraction, determine gap status. Produce: (a) a Test Structure Tree using typed prefixes (request field:, request header:, db field:, outbound response field:) with ✓/✗ for every scenario — every field gets its own entry reviewed 1 by 1, (b) a Contract Map table with one row per field using typed prefix in Type column, (c) gap analysis by priority (HIGH/MEDIUM/LOW) with full descriptions, (d) for each HIGH gap generate a test stub following the project's existing patterns from the audit, (e) a Checkpoint 2 table. IMPORTANT: every error scenario MUST include 'no data leak' assertion. Do NOT use old formats (field:, security:, business:, external:, response body, DB assertions)."

The Checkpoint 2 table the agent must produce:

| # | Contract Type | Gaps Checked? | HIGH Gaps | MEDIUM Gaps | LOW Gaps |
|---|---------------|---------------|-----------|-------------|----------|
| 1 | API (inbound) | [Yes/No] | [count] | [count] | [count] |
| 2 | DB (models/schema) | [Yes/No] | [count] | [count] | [count] |
| 3 | Outbound API calls | [Yes/No] | [count] | [count] | [count] |
| 4 | Jobs/consumers | [Yes/No] | [count] | [count] | [count] |
| 5 | UI props | [Yes/No] | [count] | [count] | [count] |

**GATE:** Verify the agent's output contains a Checkpoint 2 table. Every contract type from Checkpoint 1 with Status "Extracted" must show "Yes" in Gaps Checked. If any shows "No", ask the agent to analyze gaps for that type.

Save the agent's full output as `$GAPS`.

### Step 7-8: Report Writing (Agent 4)

Read `report-template.md` (in the same directory as this file). Then dispatch an Agent with description "Report writing" and a prompt containing:

1. The full content of `report-template.md`
2. The `$EXTRACTION` output from Agent 1
3. The `$AUDIT` output from Agent 2
4. The `$GAPS` output from Agent 3
5. Whether quick mode is enabled
6. The instruction: "Using the report template, write one report file per test file and a summary file. Write reports to `tdd-contract-review/{datetime}-report/` using the Write tool. Get the current time by running `date +%Y%m%d-%H%M`. Each per-file report MUST include: Contract Extraction Summary, Fintech Dimensions Summary (if applicable), Test Structure Tree (using typed prefixes from the gap analysis), Contract Map, Gap Analysis with test stubs, Anti-Patterns table, Score breakdown. The summary is a strict rollup — no findings that don't appear in per-file reports. After writing, verify files exist by listing the directory. If quick mode, output only the quick summary template."

**GATE — Report Files Must Be Written:** Verify the agent wrote report files. List the report directory. If no files exist, the review is not complete — ask the agent to write them.

After the agent completes, print a short summary to the conversation showing files created and scores.

## Review Principles

1. **Read the source, not just tests.** Always read source files to extract contracts before checking test coverage.
2. **Be specific.** Every finding references `file:line`. Every gap names the exact field and missing edge case.
3. **Prioritize by breakage risk.** Core API field = HIGH. Internal utility edge case = LOW.
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7. Score of 9 means genuinely no gaps. Do not inflate.
6. **Do not run tests.** Static analysis only.
