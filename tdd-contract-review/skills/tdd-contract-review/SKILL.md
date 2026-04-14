---
name: tdd-contract-review
description: Contract-based test quality review. Extracts contracts from source code, maps test coverage per field, identifies gaps, produces a scored report with prioritized actions, and auto-generates test stubs for high-priority gaps.
argument-hint: "[path, file, or 'quick' for abbreviated output -- defaults to PR scope or project root]"
allowed-tools: [Read, Write, Glob, Grep, Bash]
version: 0.17.0
---

# TDD Contract Review

Contract-based test quality review. Extract contracts from source code, map test coverage per field, identify gaps, produce a scored report with prioritized actions, and auto-generate test stubs for high-priority gaps.

## Core Philosophy

Tests protect against breaking changes by verifying contracts -- the agreements between components about data shape, behavior, and error handling. A contract field without tests means changes to that field can break things silently.

**Rules to enforce:**
- Verify contracts, NOT implementation details
- Mock minimally -- ideally only external API calls
- Use real database -- never mock DB
- Group tests by feature > field so gaps are immediately visible
- Every contract field needs edge case coverage

## Typed Field Prefixes

Every field in the Test Structure Tree and Contract Map MUST use one of these typed prefixes:
- `request field:` — user input validation (nil, invalid, boundary, etc.)
- `request header:` — HTTP headers (missing auth, expired token)
- `db field:` — pre-existing database state (suspended, insufficient balance, already exists)
- `outbound response field:` — external API response handling + outbound request param assertions + DB state after + upstream validation (mismatch, null, malformed)
- `prop:` — UI component props

**GATE — Do NOT use these old formats:**
- ~~`field: X (request param)`~~ → use `request field: X`
- ~~`field: X (DB data state)`~~ → use `db field: X`
- ~~`security: authentication`~~ → use `request header: Authorization`
- ~~`security: IDOR`~~ → scenario under `request field:` for the resource ID
- ~~`security: error response data`~~ → "no data leak" assertion on each error scenario
- ~~`business: rule`~~ → use `db field:` for the relevant database state
- ~~`external: API.call`~~ → use `outbound response field: API.field`
- ~~`response body`~~ → assertions within each field's happy path
- ~~`DB assertions`~~ → assertions within each field's happy path

Every field is reviewed 1 by 1. DB fields and outbound response fields get the same per-field treatment as request fields. No grouping, no shortcuts.

**Assertion rules per scenario type:**
- Error scenarios: assert status code + no DB write + no outbound API call + no data leak in error response
- Success scenarios: assert status code + response fields + DB state + outbound params sent
- Outbound response scenarios: assert DB state after change + validate upstream response fields (mismatch, null)

## Sessions Pattern (Test Structure)

Every field in section 2 MUST use a typed prefix. The structure:

```
Feature (top-level describe/context)
|
+-- Test foundation
|   +-- Default constants, subject/runTest helper, shared setup
|   +-- Each test overrides only the one field it tests
|
+-- 1) Happy path
|   +-- Asserts every response field + every DB field + outbound params sent
|
+-- 2) Scenarios per field
    +-- request field: amount
    |   +-- nil -> 422, no DB write, no outbound API call, no data leak
    |   +-- zero (boundary) -> success or 422
    +-- request header: Authorization
    |   +-- missing -> 401
    +-- db field: wallet.status
    |   +-- suspended -> 422, no DB write, no outbound API call, no data leak
    +-- db field: wallet.balance
    |   +-- amount > balance -> 422, no DB write, no outbound API call, no data leak
    |   +-- amount == balance -> 201, db balance == 0
    +-- db field: record.user_id
    |   +-- happy path asserts correct user_id stored in DB
    +-- outbound response field: ThirdPartyAPI.call.status_code
    |   +-- 200 -> parse body
    |   +-- 500 -> db unchanged, return 503
    +-- outbound response field: ThirdPartyAPI.call.success?
    |   +-- true -> 201, db record.status == completed, db balance deducted
    |   +-- false -> db record.status == failed
    +-- outbound response field: ThirdPartyAPI.call.amount
    |   +-- happy path asserts correct amount sent
    |   +-- response amount differs from sent -> reject/flag/reconcile
    +-- outbound response field: ThirdPartyAPI.call.transaction_id
        +-- present -> store for reconciliation
        +-- null/empty -> flag, cannot reconcile later
```

**Read `test-patterns.md` for:** code examples (RSpec, Go), frontend/UI pattern, contract boundary rules, anti-patterns to flag, test case quality audit (Step 5).

## Review Workflow

### Step 1: Determine Scope

Resolve `$ARGUMENTS` to find test and source files.

**Parsing rules:** split `$ARGUMENTS` on whitespace. If the first token is `quick`, enable quick mode and use remaining tokens for scope. Otherwise all tokens are scope (file path or directory). Examples: `quick spec/models` → quick mode on `spec/models`; `src/auth/` → full mode on `src/auth/`; empty → PR-scoped or project.

- **`quick` keyword**: If the first argument is `quick`, enable quick mode (abbreviated output). Use remaining arguments for scope, or default to PR-scoped/project.
- **Specific test file** (e.g. `spec/models/user_spec.rb`): review that file, locate its source
- **Source file** (e.g. `src/services/auth.ts`): find corresponding test files
- **Directory** (e.g. `src/auth/`): find all test files in that tree
- **No argument + on a non-default branch**: PR-scoped mode. Use `git diff` against the base branch to find changed source files (filter to code files: `*.rb`, `*.go`, `*.ts`, `*.tsx`, `*.jsx`, `*.js`, `*.py`). Extract contracts from those changed source files, then check the ENTIRE test suite for coverage of those contracts. This catches the key case: source changed but no tests updated.
- **No argument + on default branch**: review the entire project test suite

**Edge cases:**
- If no test files are found for the scope: report score 0/10 and list all extracted contracts as untested gaps.
- If no source files can be located: ask the user to specify paths.
- If the scope exceeds ~50 test files: recommend narrowing to a directory or using PR-scoped mode.
- If a test file has no corresponding source file: skip it or note "source file not found for this test."
- If a test file exists but is empty (no test cases): flag as anti-pattern.

Locate test files by convention:
- Same directory: `foo.test.ts`, `foo.spec.ts`, `foo_test.go`, `foo_spec.rb`
- Parallel directories: `__tests__/`, `test/`, `tests/`, `spec/`
- Go: `foo_test.go` in the same package

### Step 2: Discovery

1. **Find test files.** Glob for:
   - `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}` (Jest/Vitest)
   - `**/*_test.go` (Go)
   - `**/*_spec.rb` (RSpec)
   - `**/*.test.py`, `**/test_*.py` (pytest)

2. **Detect test framework.** Read test files to identify framework from imports and syntax.

3. **Find source files.** Locate source files corresponding to each test file. Include not just controllers/handlers but also jobs (`app/jobs/`, `app/workers/`, `workers/`) and message consumers (`app/consumers/`, `consumers/`).

4. **Check project conventions.** Read config files (CLAUDE.md, jest.config, .rspec, Makefile) for testing rules.

5. **Detect mixed frameworks.** If multiple test frameworks are present, note all of them and analyze each separately.

6. **Detect fintech domain.** Scan source files for fintech indicators: money/amount/balance/currency fields, payment/transaction/ledger/wallet models, payment gateway integrations, decimal/money types (`BigDecimal`, `decimal.Decimal`, `Decimal`, `money` gem, `dinero.js`), idempotency key params, or ledger/double-entry patterns. If detected, enable **fintech mode** which adds domain-specific contract extraction and gap analysis (see Step 3 and Step 6 fintech sections).

### Step 3: Contract Extraction

Read source files to identify all contracts in scope. **Read `contract-extraction.md` (in the same directory as this file) for detailed per-framework extraction guidance and the full Contract Extraction Summary example.**

For each feature/module, extract these contract types:
- **API Contract (inbound):** request params, response fields, status codes
- **DB Data Contract:** fields, constraints, enum values (exhaustively list every enum value), relationships
- **Job & Message Consumer Contract:** payload fields, side effects, error handling, idempotency
- **API Calls Contract (outbound):** request params sent AND response fields received (upstream is untrusted — each response field needs validation scenarios)
- **UI Props Contract:** prop types, rendered states, interactions

**Confidence indicators:** HIGH (explicit in code), MEDIUM (inferred from usage), LOW (guessed from naming).

#### Fintech Contract Extraction (when fintech mode detected)

When fintech domain is detected in Step 2, extract these additional contract dimensions on top of the standard extraction above. **Read `fintech-checklists.md` (in the same directory as this file) for detailed per-field extraction guidance.** The 8 dimensions to extract:

1. **Money & Precision** — field types (must be exact, not float), currency pairing, decimal scale, rounding
2. **Idempotency** — idempotency key fields, unique constraints, which mutating endpoints have them
3. **Transaction State Machine** — all enum values, valid/invalid transitions, terminal states, side effects per transition
4. **Balance & Ledger Integrity** — balance update method, locking strategy, double-entry patterns, check-then-act timing
5. **External Payment Integrations + Response Validation** — gateway calls, webhook contracts, retry/reconciliation, settlement flow, upstream response field validation
6. **Regulatory & Compliance** — KYC/AML fields, transaction limits, audit trail fields, PII fields
7. **Concurrency & Data Integrity** — TOCTOU paths, locking strategy per resource, multi-resource deadlock prevention, job deduplication, DB transaction isolation
8. **Security & Access Control** — auth requirements per endpoint, authorization/ownership rules, IDOR-vulnerable endpoints, rate limits, sensitive data in responses, payment credential handling

**Fintech Dimension Template (mandatory when fintech mode detected):**

Include this table in the Contract Extraction Summary. Fill in every row — no row may be omitted:

| # | Dimension | Status | Fields Found | Notes |
|---|-----------|--------|-------------|-------|
| 1 | Money & Precision | Extracted / Not detected | [list fields or "—"] | |
| 2 | Idempotency | Extracted / Not detected | [list fields or "—"] | |
| 3 | Transaction State Machine | Extracted / Not detected | [list fields or "—"] | |
| 4 | Balance & Ledger Integrity | Extracted / Not detected | [list fields or "—"] | |
| 5 | External Payment Integrations + Response Validation | Extracted / Not detected / Not applicable | [list fields or "—"] | [if N/A: rationale] |
| 6 | Regulatory & Compliance | Extracted / Not detected | [list fields or "—"] | |
| 7 | Concurrency & Data Integrity | Extracted / Not detected | [list fields or "—"] | |
| 8 | Security & Access Control | Extracted / Not detected | [list fields or "—"] | |

Status rules:
- **Extracted**: Fields found in source code. List them in the Fields Found column.
- **Not detected**: No fields found but the dimension is relevant to financial code. Write: "No fields detected — will be flagged in gap analysis."
- **Not applicable**: Only valid for dimensions where the prerequisite feature doesn't exist in source. Must include rationale in the Notes column.

#### Checkpoint 1 — Contract Type Verification (mandatory)

After extracting all contracts, fill in this table. Every row is mandatory. Do not skip any row.

| # | Contract Type | Status | Fields Found | Source Files Read |
|---|---------------|--------|-------------|-------------------|
| 1 | API (inbound) | [status] | [count] | [files] |
| 2 | DB (models/schema) | [status] | [count] | [files] |
| 3 | Outbound API calls (request params + response fields) | [status] | [count] | [files] |
| 4 | Jobs/consumers | [status] | [count] | [files] |
| 5 | UI props | [status] | [count] | [files] |

Status rules (three-state enum, same as fintech dimensions):
- **Extracted**: Fields found in source code. List count and source files read.
- **Not detected**: Source files were read but no contracts of this type were found. The dimension is still relevant. Write: "No fields detected — will be flagged in gap analysis if applicable."
- **Not applicable**: The codebase genuinely does not have this contract type (e.g., no background jobs, no UI). Must include rationale naming which files were checked (e.g., "Not applicable — searched app/jobs/, app/workers/, no job files found").

**GATE:** For each row with Status = "Extracted", Fields Found must be > 0. If any "Extracted" row shows 0, re-read the listed source files. A typical single-endpoint Rails controller produces 15-30 fields across all contract types. If total fields across all types is fewer than 10, re-read source files. Do not proceed to Step 4 until every row is filled and verified.

### Step 4: Test Structure Audit

Check whether tests follow the sessions pattern and group by field to make gaps visible. **Read `test-patterns.md` for detailed guidance, code examples, contract boundary rules, and anti-patterns to flag.**

### Step 5: Test Case Quality Audit

Evaluate how well each individual test case is written. **Read `test-patterns.md` for assertion completeness, readability, isolation, and flaky pattern checklists.**

### Step 6: Gap Analysis

The primary output. For every contract field discovered in Step 3, check:

1. **Does a test exist for this field?** Search test files for the field name
2. **Is there a test group for this field?** Dedicated describe/context/t.Run
3. **What scenarios are covered?** For each field, check by prefix type:
   - `request field:` — null/nil, empty, zero, boundary, invalid type/format, very large, permission denied
   - `request header:` — missing, expired, malformed
   - `db field:` — record not exists, belongs to another user, suspended/inactive, insufficient balance, already exists (duplicate)
   - `outbound response field:` — success, error, timeout, mismatch (amount/currency differs from sent), null/missing, malformed response + assert outbound request params + DB state after change

Assign priority to each gap:
- **HIGH**: Core contract field with no tests at all
- **MEDIUM**: Field tested but missing important scenarios (edge cases, error paths)
- **LOW**: Rare corner case or defensive scenario

#### Common Field Type Scenarios (always applied)

When checking scenario coverage per field, use these type-specific checklists in addition to the generic edge cases above. Match the field's type to the relevant checklist.

**Pagination fields** (`page`, `limit`, `offset`, `cursor`, `per_page`):
- Zero value: `page=0` or `limit=0` — rejected or treated as default?
- Negative value: `page=-1` — must be rejected
- Very large limit: `limit=999999` — capped or rejected? Must not return unbounded results
- Beyond last page: page number past total pages — empty result set, not error
- Invalid cursor: malformed or expired cursor token — rejected with clear error
- Default values: omitted params use documented defaults

**Date/time fields** (`created_at`, `start_date`, `expires_at`, `scheduled_for`):
- Invalid format: non-ISO-8601 string — rejected with format guidance
- Future date: when only past dates are valid (e.g. `date_of_birth`) — rejected
- Past date: when only future dates are valid (e.g. `scheduled_for`) — rejected
- Timezone handling: dates with and without timezone offset — consistent behavior
- Boundary dates: start of day, end of day, month/year boundaries

**String fields with format constraints** (`email`, `url`, `phone`, `uuid`):
- Valid format: at least one representative value per format
- Invalid format: structurally wrong (missing `@` in email, no protocol in URL)
- Max length: at schema limit — succeeds; one over — rejected
- Empty string vs. null: often behave differently — test both

**File upload fields** (`avatar`, `document`, `attachment`):
- File too large: exceeds size limit — rejected with clear error
- Wrong MIME type: `.exe` when only images allowed — rejected
- Empty file: zero-byte upload — rejected or accepted?

#### Fintech Gap Analysis (when fintech mode detected)

When fintech domain is detected, check every extracted fintech contract field against the scenario checklists in `fintech-checklists.md` (section "Gap Analysis Scenario Checklists"). These are HIGH priority by default because financial bugs cause real money loss.

For each category below, produce gap entries in the report. The top scenarios (must-check) are listed inline; read the reference file for the full checklist per category.

**1. Money/amount fields:**
- Precision overflow: amount with more decimals than schema allows → round, truncate, or reject?
- Zero amount: allowed or rejected? (transfers reject, queries allow)
- Boundary at max: exactly at configured limit → 201; one above → 422
- Balance validation: amount > available balance → rejected; amount == balance → success with zero remaining
- Position validation: sell/reduce qty > held position → rejected; qty == position → closes position

**Cross-dimension rule for amount fields:** When an amount field's endpoint has a balance check or position check in its code path, add "exceeds balance → 422" and/or "exceeds position → 422" as scenarios under a `db field: wallet.balance` or `db field: position.quantity` entry in the Test Structure Tree. Balance and position constraints are database state conditions, not input validation — they belong under `db field:`, not under `request field: amount`.

**2. Idempotency:**
- Duplicate POST with same idempotency key → must return original response, not create second record
- Missing key on mutating financial endpoint → flag as design gap if no key exists

**3. State machine:**
- Every valid transition tested with correct side effects
- At least one invalid transition tested (e.g. `completed → pending` → rejected)
- Terminal states: no further transitions allowed

**4. Balance/ledger:**
- Insufficient balance → rejected
- Exact balance value asserted after operation (not just "changed")

**5. Concurrency** (check even if no tests exist — flag the absence):
- TOCTOU: if code reads balance then writes in separate steps without a lock, flag as HIGH gap
- Double-submit: two rapid identical POSTs must not create duplicate financial records
- If the code uses `with_lock`, `FOR UPDATE`, or optimistic locking: flag that no test verifies the lock actually prevents concurrent corruption

**6. Outbound response validation** (upstream is untrusted — treat response fields like user input):
- Amount mismatch: gateway charged a different amount than requested → must detect and reject/flag/reconcile, not silently accept
- Currency mismatch: gateway responded with a different currency → must detect and reject/flag
- Missing transaction_id: gateway returned null/empty external reference → flag, cannot reconcile later
- Each outbound response field should have scenarios for: correct value (happy path assertion), wrong value (mismatch), and null/missing

**7. Security & access control:**
- Authentication: at least one `request header: Authorization` entry per endpoint with missing/expired token → 401
- IDOR: at least one test per `request field:` that accepts a resource ID — access other user's resource → 403/404 (scenario under the resource ID field)
- Sensitive data in error responses: for each error scenario, assert the response body does not leak balances, account numbers, internal user IDs, SQL errors, or stack traces

**8. Absence flagging** — flag missing infrastructure when the prerequisite source patterns exist. Only fire each flag when its condition is met. Include these in the gap analysis under a "Missing infrastructure" section, separate from per-field gaps.

**HIGH priority:**
- No idempotency key on mutating endpoints → flag when mutating financial endpoints exist
- No concurrency protection on financial write paths → flag when balance updates, transfers, or other financial write paths exist

**MEDIUM priority:**
- No rate limiting on financial mutation endpoints
- No audit trail table/fields for financial mutations
- No explicit state machine or transition guards
- No balance validation or ledger consistency patterns
- No webhook signature verification or payment gateway error handling
- No KYC/AML fields, transaction limits, or compliance validations

#### Checkpoint 2 — Gap Analysis Verification (mandatory)

After completing gap analysis (including fintech if applicable), fill in this table. Every contract type from Checkpoint 1 with Status "Extracted" or "Not detected" must have a corresponding row here.

| # | Contract Type | Gaps Checked? | HIGH Gaps | MEDIUM Gaps | LOW Gaps |
|---|---------------|---------------|-----------|-------------|----------|
| 1 | API (inbound) | [Yes/No] | [count] | [count] | [count] |
| 2 | DB (models/schema) | [Yes/No] | [count] | [count] | [count] |
| 3 | Outbound API calls | [Yes/No] | [count] | [count] | [count] |
| 4 | Jobs/consumers | [Yes/No] | [count] | [count] | [count] |
| 5 | UI props | [Yes/No] | [count] | [count] | [count] |

**GATE:** Every contract type from Checkpoint 1 with Status "Extracted" must show "Yes" in Gaps Checked. If any shows "No", go back and analyze gaps for that contract type before proceeding. Types marked "Not applicable" in Checkpoint 1 may be omitted from this table.

### Step 7: Auto-Generate Test Stubs

For each HIGH-priority gap from Step 6, generate test code that follows the project's existing test patterns.

**How to learn patterns:**
1. Read 2-3 existing test files in the project to identify: framework, helper methods, assertion style, factory/fixture usage, file organization
2. Match the existing test foundation pattern (defaults, subject/runTest, let blocks)

**Generation rules:**
- Generated tests MUST verify contract fields, never implementation details
- Follow the sessions pattern: defaults at top, single subject/runTest, each test overrides one field
- Group generated tests by the contract field they cover
- Include a note at the top: "Generated tests follow your project's patterns. Review before committing."

**Cold start (no existing tests):**
If no test files exist for the scope, generate test stubs using framework-specific defaults from the examples in `test-patterns.md`. Note in the output: "No existing tests found. Generated stubs use default patterns."

**Output format:**
For each HIGH gap, output the generated test as a fenced code block inline in the report, immediately after the gap entry. Use the full gap description as the heading — never use shorthand labels like "Stub H1", "Stub H4", etc. The reader should understand what each stub tests without cross-referencing the gap list.

### Step 8: Score and Report

**Read `report-template.md` (in the same directory as this file) for the full report template, scoring rubric, calibration anchors, multi-file summary format, and quick mode template.**

**GATE — Report Files Must Be Written:** You MUST write per-file report files using the Write tool before printing any summary to the conversation. The report files are the primary output — the conversation summary is secondary. After writing, verify the files exist by listing the report directory. If no files exist after this step, you have not completed the review — go back and write them. Each per-file report MUST include: Contract Extraction Summary (all contract types: API, DB, outbound, jobs), Test Structure Tree, Contract Map (every extracted field gets a row), Gap Analysis with auto-generated stubs, Anti-Patterns table, Score breakdown.

After writing and verifying report files, print a short summary to the conversation showing the files created and scores.

## Review Principles

1. **Read the source, not just tests.** Identify missing contracts by understanding the source code. Always read source files to extract contracts before checking test coverage.
2. **Be specific.** Every finding references `file:line`. Every gap names the exact field and missing edge case. Never say "needs more tests."
3. **Prioritize by breakage risk.** A missing test for a core API field is HIGH. A missing edge case for an internal utility is LOW.
4. **Respect the mock boundary.** The only acceptable mocks are external API calls. Flag everything else.
5. **Be calibrated.** Most real codebases score 4-7. A score of 9 means genuinely no gaps found. Do not inflate.
6. **Do not run tests.** Static analysis of test quality only, not execution.
