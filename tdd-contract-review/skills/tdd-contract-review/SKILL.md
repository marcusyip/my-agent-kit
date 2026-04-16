---
name: tdd-contract-review
description: Contract-based test quality review. Extracts contracts from source code, maps test coverage per field, identifies gaps, produces a scored report with prioritized actions, and auto-generates test stubs for high-priority gaps.
argument-hint: "[path, file, or 'quick' for abbreviated output -- defaults to PR scope or project root]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.23.0
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

Every field is either an **input** (you set it in the test) or an **assertion** (you verify it after the request), or both.

| Prefix | Role | How to set/verify |
|---|---|---|
| `request field:` | Input | Set in request params |
| `request header:` | Input | Set in request headers |
| `db field:` | Input AND assertion | Input: set in test setup (e.g. create wallet with status: 'suspended'). Assertion: verify DB state after request (e.g. transaction.user_id == user.id) |
| `outbound response field:` | Input | Set via mock return value (e.g. mock gateway to return success: false) |
| `outbound request field:` | Assertion | Verify correct params sent to external API mock (e.g. expect(Gateway).to have_received(:charge).with(amount: 100)) |
| `prop:` | Input | Set as component props |

**Input fields** get tree entries with scenarios (each scenario sets a different value and checks the outcome).
**Assertion fields** (`outbound request field:`) are verified within the happy path and outbound response scenarios — they don't get their own tree branch with scenarios.
**db field:** appears in both roles: as input (precondition scenarios) AND as assertion (postcondition verification in happy path).

**Do NOT use:** `field: X (request param)`, `security:`, `business:`, `external:`, `response body`, `DB assertions`. These are old formats.

Every field is reviewed 1 by 1. Same per-field treatment for all types.

**Assertion rules per scenario type:**
- Error scenarios: assert status code + no DB write + no outbound API call + no data leak in error response
- Success scenarios: assert status code + db fields (assertion) + outbound request fields (assertion)
- Outbound response scenarios: set mock return value (input) + assert db fields after change + assert outbound request fields sent correctly + validate upstream response fields (mismatch, null)

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
3. **Find source files — handlers/controllers.** Locate source files corresponding to each test file. Include controllers/handlers, jobs (`app/jobs/`, `app/workers/`), and message consumers (`app/consumers/`).
4. **Find DB schema files — trace from handlers.** This is critical. Do NOT rely on handler code alone for DB contracts. Find the actual schema source of truth:
   - **Migrations:** Glob for `db/migrate/*.rb`, `database/migrations/*.sql`, `migrations/*.sql`, `**/migrations/*.py`, `**/migrate/*.go`
   - **Model/entity definitions:** From handler imports, trace to model files. Glob for `app/models/*.rb`, `internal/model/*.go`, `src/models/*.ts`, `src/entities/*.ts`, `**/models.py`
   - **ORM schema files:** `prisma/schema.prisma`, `db/schema.rb`, `**/schema.sql`
   - **Generated query files:** SQLC (`**/queries.sql.go`, `**/query.sql.go`, `sqlc.yaml`), TypeORM entities, Drizzle schema
   - **Go struct tags:** Files with `db:` or `gorm:` tags in the handler's package or `internal/model/`
   All discovered DB schema files must be passed to Agent 1 alongside handler files.
5. **Find outbound API client files — trace from handlers.** Do NOT rely on handler code alone for outbound contracts. Find the actual HTTP client code:
   - From handler imports, trace to service/client files that make HTTP calls
   - Glob for `app/services/*.rb`, `internal/service/*.go`, `src/services/*.ts`, `**/client/*.go`, `**/gateway/*.rb`
   - Look for HTTP client imports: `HTTParty`, `Faraday`, `net/http`, `axios`, `fetch`, `requests`, `httpx`
   All discovered outbound client files must be passed to Agent 1 alongside handler files.
6. **Check project conventions.** Read CLAUDE.md, jest.config, .rspec, Makefile.
7. **Detect mixed frameworks.**
8. **Detect fintech domain.** Scan for money/amount/balance/currency fields, payment gateway integrations, decimal/money types, idempotency key params, ledger patterns. If detected, enable **fintech mode**.

**GATE — Source File Completeness:** Before proceeding to Step 3, verify you have three categories of source files:
- Handler/controller files (the entry points)
- DB schema files (migrations, models, entity definitions, generated queries)
- Outbound API client files (services, HTTP client wrappers)
If any category is empty, glob more broadly. Do NOT proceed with only handler files — the extraction will be incomplete.

### Step 3: Contract Extraction (Agent 1)

Determine the absolute path to this skill's directory (the directory containing this SKILL.md file). Dispatch an Agent with description "Contract extraction", model "sonnet", and a prompt containing:

1. The absolute path to the skill directory so the agent can read reference files
2. The list of source file paths found in Step 2, organized by category:
   - Handler/controller files
   - DB schema files (migrations, models, entity definitions, generated queries)
   - Outbound API client files (services, HTTP client wrappers)
3. Whether fintech mode was detected in Step 2
4. The instruction:
   "You are a contract extractor. Follow these steps exactly:
   (a) Read the file `contract-extraction.md` at [skill directory path]/contract-extraction.md using the Read tool. This contains per-framework extraction guidance and the output format example.
   (b) If fintech mode is detected, also read `fintech-checklists.md` at [skill directory path]/fintech-checklists.md for fintech-specific extraction dimensions.
   (c) Read every source file listed below.
   (d) Extract all contracts using the guidance from contract-extraction.md.
   (e) Produce a Contract Extraction Summary using typed prefixes per field — every field must be labeled with its prefix (request field:, request header:, db field:, outbound response field:). Use the format from the example in contract-extraction.md exactly. This format flows directly into the Test Structure Tree and Contract Map without restructuring.
   (f) Fill in the Checkpoint 1 table (mandatory, every row).
   (g) If fintech mode, fill in the Fintech Dimension Template (mandatory, every row).
   (h) Use the three-state enum: Extracted / Not detected / Not applicable (with rationale).
   (i) Output the complete extraction summary, Checkpoint 1 table, and fintech dimensions table."

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

Dispatch an Agent with description "Test structure audit", model "sonnet", and a prompt containing:

1. The absolute path to the skill directory
2. The list of test file paths found in Step 2
3. The `$EXTRACTION` output from Agent 1 (so the auditor knows which contracts to check coverage for)
4. The instruction:
   "You are a test auditor. Follow these steps exactly:
   (a) Read the file `test-patterns.md` at [skill directory path]/test-patterns.md using the Read tool. This contains the sessions pattern, test foundation examples, contract boundary rules, anti-patterns to flag, and test case quality checklists.
   (b) Read every test file listed below.
   (c) Audit test structure: sessions pattern, one endpoint per file, test foundation (defaults, subject/runTest).
   (d) Audit test case quality: assertion completeness, readability, isolation, flaky patterns.
   (e) Flag anti-patterns with file:line references.
   (f) For each contract field from the extraction, note whether a test group exists and what scenarios are covered.
   (g) Typed prefix rules: use request field:, request header:, db field:, outbound response field:, prop:. Never use bare field:, security:, business:, external:.
   (h) Assertion rules: Error scenarios must assert status code + no DB write + no outbound API call + no data leak. Success scenarios must assert status code + response fields + DB state + outbound params sent.
   (i) Output: test structure audit findings, quality issues, anti-patterns list, and per-field coverage notes."

Save the agent's full output as `$AUDIT`.

### Step 6: Gap Analysis (Agent 3)

Dispatch an Agent with description "Gap analysis", model "opus", and a prompt containing:

1. The absolute path to the skill directory
2. Whether fintech mode was detected
3. The `$EXTRACTION` output from Agent 1
4. The `$AUDIT` output from Agent 2
5. The instruction:
   "You are a gap analyzer. Follow these steps exactly:
   (a) If fintech mode is detected, read `fintech-checklists.md` at [skill directory path]/fintech-checklists.md using the Read tool, specifically the 'Gap Analysis Scenario Checklists' section.
   (b) For every contract field from the extraction, determine gap status by checking the audit output.
   (c) Check scenarios by prefix type:
       - request field: null/nil, empty, zero, boundary, invalid type/format, very large, permission denied
       - request header: missing, expired, malformed
       - db field: record not exists, belongs to another user, suspended/inactive, insufficient balance, already exists (duplicate)
       - outbound response field: success, error, timeout, mismatch (amount/currency differs from sent), null/missing, malformed response + assert outbound request params + DB state after change
   (d) Also check common field type scenarios: pagination (zero, negative, very large limit, beyond last page), date/time (invalid format, future/past, timezone), string format (valid, invalid, max length, empty vs null), file upload (too large, wrong MIME).
   (e) If fintech mode, apply all 8 fintech gap categories from the checklists file: Money/amount, Idempotency, State machine, Balance/ledger, Concurrency, Outbound response validation, Security & access control, Absence flagging.
   (f) Produce the Test Structure Tree. MANDATORY FORMAT — follow this structure exactly:
       POST /api/v1/endpoint
       ├── request field: fieldname
       │   ├── ✓ scenario (covered)
       │   └── ✗ scenario (missing)
       ├── request header: Authorization — NO TESTS
       │   └── ✗ missing → 401
       ├── db field: model.fieldname — NO TESTS
       │   └── ✗ scenario
       └── outbound response field: Service.method.fieldname — NO TESTS
           └── ✗ scenario
       Each endpoint is a root node. Each field is a branch with typed prefix. Scenarios nested under fields. Fields with no tests get '— NO TESTS'. Error scenarios include 'no data leak'.
   (g) Produce a Contract Map table with one row per field, typed prefix in Type column.
   (h) Produce gap analysis by priority (HIGH/MEDIUM/LOW) with full descriptions.
   (i) For each HIGH gap, generate a test stub following the project's existing patterns from the audit.
   (j) Produce a Checkpoint 2 table.
   (k) Priority: HIGH = no tests at all, MEDIUM = missing scenarios, LOW = rare corner cases.
   (l) IMPORTANT: every error scenario MUST include 'no data leak' assertion. Do NOT use old formats (field:, security:, business:, external:, response body, DB assertions)."

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

Dispatch an Agent with description "Report writing", model "sonnet", and a prompt containing:

1. The absolute path to the skill directory
2. The `$EXTRACTION` output from Agent 1
3. The `$AUDIT` output from Agent 2
4. The `$GAPS` output from Agent 3
5. Whether quick mode is enabled
6. The instruction:
   "You are a report writer. Follow these steps exactly:
   (a) Read the file `report-template.md` at [skill directory path]/report-template.md using the Read tool. This contains the full report template, scoring rubric, calibration anchors, multi-file summary format, and quick mode template.
   (b) Get the current time by running `date +%Y%m%d-%H%M` via Bash.
   (c) Write one report file per test file and a summary file to `tdd-contract-review/{datetime}-report/` using the Write tool.
   (d) Each per-file report MUST include: Contract Extraction Summary, Fintech Dimensions Summary (if applicable), Test Structure Tree (using typed prefixes from the gap analysis), Contract Map, Gap Analysis with test stubs, Anti-Patterns table, Score breakdown.
   (e) The summary is a strict rollup — no findings that don't appear in per-file reports.
   (f) After writing, verify files exist by listing the directory.
   (g) If quick mode, output only the quick summary template."

**GATE — Report Files Must Be Written:** Verify the agent wrote report files. List the report directory. If no files exist, the review is not complete — ask the agent to write them.

### Step 9: Report Review (Agent 5)

After Agent 4 writes report files, dispatch an Agent with description "Report quality review", model "opus", and a prompt containing:

1. The absolute path to the report directory (from Agent 4)
2. The `$EXTRACTION` output from Agent 1 (for cross-referencing)
3. The instruction:
   "You are a report quality reviewer. Read every report file in the report directory. Check each report against this quality checklist:

   **Extraction completeness:**
   - [ ] Checkpoint 1 table present with all 5 rows filled
   - [ ] DB contract fields extracted per-field (db field: model.fieldname), not just table names
   - [ ] Outbound API shows actual HTTP endpoint URL or SDK interface, not internal service wrapper
   - [ ] Outbound request fields (assertions) and outbound response fields (inputs) both present
   - [ ] Every contract type from Checkpoint 1 with Status 'Extracted' has fields listed

   **Test Structure Tree (every field must have its own branch):**
   - [ ] Every request param field has its own branch (request field: amount, request field: currency, etc.)
   - [ ] Every DB table field has its own branch (db field: transaction.user_id, db field: transaction.amount, db field: transaction.status, etc.) — not grouped under a table name
   - [ ] Every response body field is covered as an assertion in the happy path (verify each field value returned)
   - [ ] Every outbound request field has its own assertion entry (outbound request field: charge.amount, etc.)
   - [ ] Every outbound response field has its own branch with scenarios (outbound response field: charge.success?, etc.)
   - [ ] Each field branch has edge case scenarios: nil, invalid, boundary, empty for inputs; mismatch, null for outbound responses
   - [ ] Uses typed prefixes: request field:, request header:, db field:, outbound response field:
   - [ ] Does NOT use old formats: field:, security:, business:, external:, response body, DB assertions
   - [ ] Error scenarios include 'no data leak' assertion
   - [ ] Cross-reference: count of fields in the tree should match count of fields in the Contract Extraction Summary

   **Contract Map:**
   - [ ] One row per field with typed prefix in Type column
   - [ ] Row count per type consistent with Checkpoint 1 field counts

   **Gap Analysis:**
   - [ ] Checkpoint 2 table present
   - [ ] Every contract type from Checkpoint 1 with Status 'Extracted' shows 'Yes' in Gaps Checked
   - [ ] HIGH gaps have auto-generated test stubs

   For each failed check, output:
   - Which check failed
   - Which report file
   - Which agent should fix it: Agent 1 (extraction), Agent 2 (audit), Agent 3 (gap analysis), or Agent 4 (report writing)
   - What specifically is wrong

   If all checks pass, output: 'QUALITY: PASS — all checks passed.'
   If any checks fail, output: 'QUALITY: FAIL' followed by the list of failures."

Save the agent's output as `$REVIEW`.

**If QUALITY: PASS** — proceed to print summary.

**If QUALITY: FAIL** — re-dispatch the responsible agent(s) to fix, max 1 round:
- Parse the failures to identify which agent(s) need to re-run
- Re-dispatch only the responsible agent with the specific fix needed
- Re-run downstream agents that depend on the fixed output (e.g., if Agent 1 is fixed, re-run Agents 3 and 4)
- After the fix round, proceed to print summary. Do NOT re-run Agent 5. If issues persist after one fix round, note them as concerns in the summary.

After the review completes (pass or fix round done), print a short summary to the conversation showing files created, scores, and review result.

## Review Principles

1. **Read the source, not just tests.** Always read source files to extract contracts before checking test coverage.
2. **Be specific.** Every finding references `file:line`. Every gap names the exact field and missing edge case.
3. **Prioritize by breakage risk.** Core API field = HIGH. Internal utility edge case = LOW.
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7. Score of 9 means genuinely no gaps. Do not inflate.
6. **Do not run tests.** Static analysis only.
