---
name: tdd-contract-review
description: Contract-based test quality review. Reviews ONE unit per run (one HTTP endpoint, one background job, or one queue consumer). Extracts contracts, audits tests, identifies gaps, produces a scored report with test stubs, and emits machine-readable findings.json for CI grading.
argument-hint: "<unit: 'POST /path' | 'JobClass' | file.rb> [quick] [critical|no-critical]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.29.0
---

# TDD Contract Review

Contract-based test quality review. **Reviews ONE unit per run.** A unit is one HTTP endpoint, one background job, or one queue consumer. The orchestrator dispatches a Staff Engineer agent at each step with focused context and writes intermediate reports to disk. The user reviews each intermediate and confirms before the next step runs.

## Output Layout

Every run writes to a flat, unit-scoped directory:

```
tdd-contract-review/{YYYYMMDD-HHMM}-{unit-slug}/
├── 01-extraction.md      ← contract extracted from source
├── 02-audit.md           ← test structure + quality findings
├── 03a-gaps-api.md       ← per-type gap sub-report (API inbound)
├── 03b-gaps-db.md        ← per-type gap sub-report (DB)
├── 03c-gaps-outbound.md  ← per-type gap sub-report (Outbound API)
├── 03f-gaps-money.md     ← cross-cutting money-correctness sub-report (critical mode only)
├── 03g-gaps-security.md  ← cross-cutting API-security sub-report (critical mode only)
├── 03-gaps.md            ← merged unified gap report
├── report.md             ← final scored report
└── findings.json         ← machine-readable gap list for eval.sh / CI
```

Per-type sub-files are kept on disk for traceability. The merged `03-gaps.md` is what Step 7-8 consumes. Sub-reports for contract types marked `Not applicable` or `Not detected` are skipped entirely.

The `unit-slug` is lowercase kebab-case of the unit identifier:
- `POST /api/v1/transactions` → `post-api-v1-transactions`
- `ProcessPaymentJob` → `process-payment-job`
- `WithdrawalConsumer` → `withdrawal-consumer`

## Review Workflow

### Step 1: Parse Arguments

Split `$ARGUMENTS` on whitespace. The **first token is the unit identifier** and is REQUIRED. Remaining tokens are flags in any order.

- **Unit identifier** (required): one of
  - HTTP verb + path: `POST /api/v1/transactions`
  - Class name: `ProcessPaymentJob`, `WithdrawalConsumer`
  - File path: `app/controllers/api/v1/transactions_controller.rb`
- **`quick`** (optional): abbreviated report output
- **`critical`** (optional): force critical mode ON — enables BOTH money-correctness and API-security checklists
- **`no-critical`** (optional): force critical mode OFF (skip both checklists)

If no unit identifier is provided, print: `ERROR: unit identifier required. Usage: /tdd-contract-review "POST /api/v1/transactions"` and stop.

### Step 2: Discovery + Unit Guard

1. **Find test files.** Glob for `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}`, `**/*_test.go`, `**/*_spec.rb`, `**/*.test.py`, `**/test_*.py`
2. **Detect test framework.**
3. **Resolve the unit to a single source file.**
   - If unit is `VERB /path`: grep for route definitions, find the handler.
   - If unit is a class name: glob + grep for `class ClassName`.
   - If unit is a file path: use it directly.
4. **Find DB schema files** traced from the unit's source (migrations, models, ORM schemas).
5. **Find outbound API client files** traced from the unit's source.
6. **Check project conventions.** Read CLAUDE.md, config files.
7. **Detect critical mode** unless overridden by `critical`/`no-critical` arg. Money/balance/currency fields, payment gateways, or decimal types → critical mode ON (loads both money-correctness and API-security checklists).

**GATE (one-unit):** Exactly one source file must resolve from the unit identifier.
- **0 matches**: print `ERROR: unit '<arg>' not found. Searched: <scope>` and stop.
- **>1 matches**: print `ERROR: unit '<arg>' ambiguous. Candidates:` followed by a numbered list, then stop.
- **1 match**: proceed.

**Compute unit-slug** from the identifier. Compute run directory: `tdd-contract-review/$(date +%Y%m%d-%H%M)-{unit-slug}/`. Create the directory. Store path as `$RUN_DIR`.

### Step 3: Contract Extraction

Determine the skill directory and plugin root. Dispatch the Staff Engineer agent with the full `01-extraction.md` shape spelled out in the prompt so the gate below parses reliably:

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Contract extraction
Prompt:
  "TASK: Extract contracts for ONE unit and write to disk.
   Skill directory: [path]
   Run directory: $RUN_DIR
   Unit: [unit identifier]
   Source file: [resolved path]
   DB schema files: [list]
   Outbound client files: [list]
   Critical mode: [yes/no]

   Read `contract-extraction.md` at [skill dir]/contract-extraction.md for extraction guidance.
   If critical mode: also read BOTH `money-correctness-checklists.md` and `api-security-checklists.md` at [skill dir].

   OUTPUT FILE SHAPE — $RUN_DIR/01-extraction.md MUST open with two mandatory sections in this order:

   1) ## Files Examined

   Bullet list of every file you read, grouped into four categories. Always include all four headings; write '- (none)' under any empty category. Never omit a category.

   ```
   ## Files Examined

   **Source:**
   - `path/to/handler.rb` — primary unit handler
   - `path/to/service.rb` — downstream helper invoked by handler

   **DB schema:**
   - `db/migrate/*.rb` or `db/schema.rb`
   - `app/models/*.rb`

   **Outbound clients:**
   - `ExternalSDK.method` — referenced at `file:line`, SDK boundary

   **Other:**
   - (list anything else you opened during extraction; '- (none)' if nothing)
   ```

   2) ## Checkpoint 1: Contract Type Coverage

   STRICT table — the orchestrator greps for literal row labels. Do NOT rename, reorder, or embellish labels.

   - Row labels MUST be exactly these 5 strings, in this order: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`.
   - Do NOT write `API contract (inbound)`, `DB contract`, `Job/message consumer contract`, `UI props contract` or any variant. Put context in the Notes column only.
   - Column header MUST be: `| Contract Type | Status | Fields | Notes |`
   - Status MUST be one of exactly: `Extracted` | `Not detected` | `Not applicable`.

   ```
   ## Checkpoint 1: Contract Type Coverage

   | Contract Type | Status | Fields | Notes |
   |---|---|---|---|
   | API inbound | Extracted | 8 | request params + headers counted |
   | DB | Extracted | 12 | from migrations/schema.rb, not handler code |
   | Outbound API | Extracted | 6 | actual HTTP URL or SDK interface |
   | Jobs | Not applicable | — | no async job triggered by this unit |
   | UI Props | Not applicable | — | server-side API, no UI component |
   ```

   Status semantics:
   - `Extracted`: this unit interacts with this contract type and fields are listed below.
   - `Not detected`: this unit could plausibly use this type but no evidence in source. Investigate before marking.
   - `Not applicable`: this contract type cannot apply to this unit (e.g., a consumer has no inbound API).

   After those two sections: produce the Contract Extraction Summary (typed field prefixes per field) and critical-mode dimensions (if critical mode: separate Money-correctness dimensions + API-security dimensions tables).

   WRITE the full output to $RUN_DIR/01-extraction.md. Do NOT return the content in your response body; return only 'WROTE: $RUN_DIR/01-extraction.md' when done.

   FAILURE: if you cannot identify a contract type (e.g., no DB schema found), keep the Checkpoint 1 row with status 'Not detected' or 'Not applicable' (never leave blank) and note the reason in the Notes column."
```

**GATE (Checkpoint 1 shape):** Grep `$RUN_DIR/01-extraction.md` for exactly 5 Checkpoint 1 rows: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`. Each row must have a three-state status: `Extracted` | `Not detected` | `Not applicable`. If any row is missing, print which one and stop with a specific error (do not silently re-dispatch).

**PAUSE for user confirmation:** Print:
```
━━━ Review checkpoint 1 of 3 ━━━
Wrote: $RUN_DIR/01-extraction.md
Please review the extraction. Reply "continue" to proceed to the audit step, or anything else to stop.
```
Wait for user input. Only proceed if the user confirms. If the user stops, preserve all files and exit.

### Step 4-5: Test Audit

Dispatch the Staff Engineer agent:

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Test structure audit
Prompt:
  "TASK: Audit test files against the contract extraction.
   Skill directory: [path]
   Run directory: $RUN_DIR
   Test files for this unit: [list]

   Read $RUN_DIR/01-extraction.md for the contract (produced by Step 3).
   Read `test-patterns.md` at [skill dir]/test-patterns.md for sessions pattern, anti-patterns, quality checklists.

   Produce: test structure findings, quality issues, anti-patterns (with file:line), per-field coverage notes.

   WRITE the full output to $RUN_DIR/02-audit.md. Return only 'WROTE: $RUN_DIR/02-audit.md' when done."
```

**PAUSE for user confirmation:** Print:
```
━━━ Review checkpoint 2 of 3 ━━━
Wrote: $RUN_DIR/02-audit.md
Please review the audit. Reply "continue" to proceed to gap analysis, or anything else to stop.
```
Wait. Proceed on confirmation only.

### Step 6: Gap Analysis (parallel per-type + merge)

Gap analysis runs as **parallel per-type sub-dispatches** followed by a single **merge agent**. Each per-type agent has narrow context (one contract type), so it enumerates scenarios per field exhaustively instead of collapsing assertion fields into a grouped block.

#### Step 6a — Determine which types to dispatch

Read `$RUN_DIR/01-extraction.md`. For each Checkpoint 1 row, look at the Status column:
- `Extracted` → dispatch a per-type agent for this type
- `Not detected` or `Not applicable` → skip this type (no sub-file produced)

If critical mode is yes, ALSO dispatch BOTH cross-cutting agents (regardless of which contract types are Extracted):
- **F1 (money-correctness)** — reads `money-correctness-checklists.md`
- **F2 (api-security)** — reads `api-security-checklists.md`

#### Step 6b — Parallel per-type dispatch

Dispatch all per-type agents in a single orchestrator message (parallel tool calls). Each agent writes its own sub-file and returns only `WROTE: <path>`.

**Scenario checklist — embedded in every per-type prompt.** Every field in the Test Structure Tree must enumerate every applicable scenario from the matrix below. Do NOT collapse assertion fields into a "HAPPY PATH assertions" group — each assertion field gets its own branch.

```
INPUT FIELDS (request field / request header / db field input / outbound response field / prop):
  - nullability: null / empty string / missing / whitespace-only
  - type violation: wrong type (string where int expected, etc.)
  - boundary values: min, max, just-under-min, just-over-max
  - format constraints: encoding (UTF-8 vs latin1), case sensitivity, leading/trailing whitespace
  - enum values: each enum value as its own scenario (NOT grouped)
  - injection strings (for strings that reach DB/SQL/shell/external): SQL injection, XSS, command injection, NULL byte
  - concurrency: race condition / TOCTOU (only if field mutates shared state)
  - precision: decimal precision boundary (for decimal types)
  - length: over-max, exactly-max boundary (for string types)
  - cross-field interactions: combinations with other fields (e.g., currency mismatch, amount vs balance)

ASSERTION FIELDS (response field / db field assertion / outbound request field):
  - presence in response/DB/outbound payload
  - value correctness: matches input or expected derived state
  - type correctness: integer stays integer, string stays string
  - format: ISO8601 for timestamps, decimal-as-string for money, etc.
  - NOT NULL enforcement (for DB fields with NOT NULL constraint)
  - DEFAULT behavior (for DB fields with DEFAULT clause)
  - FK integrity (for FK columns)
  - nullability in response (field present vs omitted when null)
```

**Prompt template — per-type agent (used for A/B/C):**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — <CONTRACT_TYPE>
Prompt:
  "TASK: Exhaustive per-field gap analysis for CONTRACT TYPE: <CONTRACT_TYPE>
   Skill directory: [skill dir]
   Run directory: $RUN_DIR
   Critical mode: [yes/no]

   Read $RUN_DIR/01-extraction.md — focus ONLY on the <CONTRACT_TYPE> section. Ignore other contract types.
   Read $RUN_DIR/02-audit.md — identify existing test coverage for <CONTRACT_TYPE> fields.
   Read [skill dir]/test-patterns.md for scenario conventions.
   If critical mode: read [skill dir]/money-correctness-checklists.md and [skill dir]/api-security-checklists.md for per-field checks relevant to this contract type (precision, enum values, sensitive-data leak, injection, etc.).

   SCENARIO CHECKLIST — every field in the tree MUST enumerate every applicable scenario from this matrix:
   <INSERT INPUT/ASSERTION CHECKLIST FROM ABOVE>

   Rules:
   - Every input field gets its own tree branch with enumerated scenarios.
   - Every assertion field gets its OWN branch (NO grouped 'HAPPY PATH assertions' block).
   - Every enum value is its own scenario (e.g., status enum with 4 values = 4 scenarios).
   - Status per scenario: ✓ covered (cite test file:line) | ✗ missing | PARTIAL (weak assertion, explain).

   OUTPUT FILE SHAPE — $RUN_DIR/<OUTPUT_FILE>:

   Section headers MUST be exactly these literal H2 strings, in this order. Do NOT number them (no `## 1. Test Structure Tree`). Do NOT add prefixes or suffixes beyond the `(<CONTRACT_TYPE>)` qualifier shown.

   1) ## Test Structure Tree (<CONTRACT_TYPE>)
      Root: <unit identifier>. Branches per field with scenarios enumerated from the checklist.

   2) ## Contract Map (<CONTRACT_TYPE>)
      | Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
      One row per field. Scenarios Required = comma-separated list of scenario names derived from the checklist for this field's type + constraints.

   3) ## Gap List
      For each gap:
      - id: G<TYPE_PREFIX>-<NNN> (e.g., GAPI-001, GDB-001, GOUT-001)
      - priority: CRITICAL | HIGH | MEDIUM | LOW
      - field: typed prefix + field name
      - type: <CONTRACT_TYPE>
      - description: what is missing
      - stub: REQUIRED for CRITICAL and HIGH

   4) ## Test Stubs
      Pseudocode in detected test framework's style, one stub per HIGH/CRITICAL gap.

   WRITE the full output to $RUN_DIR/<OUTPUT_FILE>. Return only 'WROTE: $RUN_DIR/<OUTPUT_FILE>' when done."
```

**Substitute per agent:**

| Agent | `<CONTRACT_TYPE>` | `<OUTPUT_FILE>` | `<TYPE_PREFIX>` |
|---|---|---|---|
| A | API inbound | 03a-gaps-api.md | API |
| B | DB | 03b-gaps-db.md | DB |
| C | Outbound API | 03c-gaps-outbound.md | OUT |

**Prompt template — F1 money-correctness cross-cutting agent:**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — money-correctness cross-cutting
Prompt:
  "TASK: Cross-cutting money-correctness gap analysis for this unit.
   Skill directory: [skill dir]
   Run directory: $RUN_DIR

   Read $RUN_DIR/01-extraction.md (full file) and $RUN_DIR/02-audit.md (full file).
   Read [skill dir]/money-correctness-checklists.md for the dimensions and scenario checklists.

   Focus on SYSTEMIC cross-contract-type money-correctness gaps: money precision anti-patterns,
   idempotency, transaction state machine integrity (transitions + terminal states),
   balance/ledger integrity, position/inventory integrity, concurrency (TOCTOU, lock placement,
   atomic balance updates), multi-step DB transaction atomicity, compensating actions on failures,
   external payment integration correctness (retry, reconciliation), refunds/reversals lifecycle,
   fees/tax calculation, holds/authorizations lifecycle, time/settlement/cutoffs, FX/conversion,
   transaction limit enforcement. Do NOT duplicate per-field gaps that the per-type agents will
   find — focus on unit-level integrity that spans multiple contract types.

   OUTPUT FILE SHAPE — $RUN_DIR/03f-gaps-money.md:

   1) ## Cross-cutting Money-Correctness Gaps
      For each dimension present in the checklist, assess and list gaps. For dimensions without gaps, write 'No gaps detected'.

   2) ## Gap List
      For each gap:
      - id: GMONEY-<NNN>
      - priority: CRITICAL | HIGH | MEDIUM | LOW
      - field: use `unit-level` for systemic dimensions (Idempotency, StateMachine integrity, Concurrency, multi-step atomicity, Reconciliation, Settlement). Only use a specific field when the gap is genuinely scoped to one field (e.g., Money/Precision on a specific amount field, FX rate on a specific quote field). Do NOT attach a systemic concern to a loosely-related field.
      - type: Money:<dimension> (e.g., Money:Precision, Money:Idempotency, Money:StateMachine, Money:BalanceLedger, Money:PositionInventory, Money:Concurrency, Money:ExternalIntegration, Money:Refunds, Money:FeesTax, Money:Holds, Money:Settlement, Money:FX, Money:Limits)
      - description: what integrity property is missing
      - stub: REQUIRED for CRITICAL and HIGH

   3) ## Test Stubs
      Pseudocode per HIGH/CRITICAL gap.

   WRITE to $RUN_DIR/03f-gaps-money.md. Return only 'WROTE: $RUN_DIR/03f-gaps-money.md' when done."
```

**Prompt template — F2 API-security cross-cutting agent:**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — API-security cross-cutting
Prompt:
  "TASK: Cross-cutting API-security gap analysis for this unit.
   Skill directory: [skill dir]
   Run directory: $RUN_DIR

   Read $RUN_DIR/01-extraction.md (full file) and $RUN_DIR/02-audit.md (full file).
   Read [skill dir]/api-security-checklists.md for the dimensions and scenario checklists.

   Focus on SYSTEMIC cross-contract-type security gaps: authentication coverage, authorization
   (IDOR on any resource-ID-accepting endpoint), privilege escalation, resource enumeration,
   rate limiting (per-user, not just per-IP), sensitive-data leaks in error/list responses,
   injection surfaces on string fields reaching DB/logs/HTML, audit trail absence and
   immutability, KYC/AML/sanctions gating, PCI scope, high-value operation MFA/approval,
   API key scoping, webhook trust (signature verification, replay protection, timestamp
   tolerance, tampered payload rejection). Do NOT duplicate per-field gaps that the per-type
   agents will find — focus on unit-level security integrity spanning contract types.

   OUTPUT FILE SHAPE — $RUN_DIR/03g-gaps-security.md:

   1) ## Cross-cutting API-Security Gaps
      For each dimension present in the checklist, assess and list gaps. For dimensions without gaps, write 'No gaps detected'.

   2) ## Gap List
      For each gap:
      - id: GSEC-<NNN>
      - priority: CRITICAL | HIGH | MEDIUM | LOW
      - field: use `unit-level` for systemic dimensions (Auth, AuthZ/IDOR, RateLimit, AuditLog, KYC, Webhook). Only use a specific field when the gap is genuinely scoped to one field (e.g., injection on `request field: description`). Do NOT attach a systemic concern to a loosely-related field (e.g., rate limiting is NOT `request header: Authorization`).
      - type: Security:<dimension> (e.g., Security:Auth, Security:AuthZ, Security:RateLimit, Security:AuditTrail, Security:KYC, Security:Webhook, Security:DataLeak, Security:Injection, Security:PCI, Security:MFA)
      - description: what integrity property is missing
      - stub: REQUIRED for CRITICAL and HIGH

   3) ## Test Stubs
      Pseudocode per HIGH/CRITICAL gap.

   WRITE to $RUN_DIR/03g-gaps-security.md. Return only 'WROTE: $RUN_DIR/03g-gaps-security.md' when done."
```

**GATE (sub-files shape):** After all per-type agents return, verify each expected sub-file exists and contains both `## Test Structure Tree` and `## Contract Map` (or `## Cross-cutting Money-Correctness Gaps` for F1, `## Cross-cutting API-Security Gaps` for F2). If any required sub-file is missing or malformed, print which one and stop.

#### Step 6c — Merge

Dispatch the merge agent:

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap merge
Prompt:
  "TASK: Merge per-type gap reports into unified $RUN_DIR/03-gaps.md.
   Run directory: $RUN_DIR

   Read every sub-file that exists: $RUN_DIR/03a-gaps-api.md, $RUN_DIR/03b-gaps-db.md,
   $RUN_DIR/03c-gaps-outbound.md, $RUN_DIR/03f-gaps-money.md, $RUN_DIR/03g-gaps-security.md.
   Also read $RUN_DIR/02-audit.md for the anti-patterns section.
   Skip any sub-file that does not exist.

   Produce $RUN_DIR/03-gaps.md with these sections in order:

   1) ## Test Structure Tree (unified)
      One root (the unit identifier). Under it, concatenate per-type branches grouped by contract type:
      - ### API inbound  (from 03a)
      - ### DB           (from 03b)
      - ### Outbound API (from 03c)
      Preserve every field branch and every scenario verbatim from the sub-files.

   2) ## Contract Map (unified)
      Single table with all rows from all sub-reports. Column header:
      | Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |

   3) ## Gap Analysis by Priority
      Merge gap lists from all sub-reports. DEDUPE by (field + description key phrase).
      When duplicates appear (e.g., F1 money agent + outbound agent both flag amount-mismatch,
      or F2 security agent + API agent both flag missing auth), keep the highest priority,
      combine descriptions, keep the richer stub.
      Group by CRITICAL / HIGH / MEDIUM / LOW in that order.

   4) ## Hygiene (from audit)
      Copy the anti-patterns section from $RUN_DIR/02-audit.md verbatim (with file:line references).
      These are test-code hygiene issues, NOT contract gaps. They inform the report but are excluded from findings.json.

   5) ## Test Stubs for CRITICAL / HIGH Gaps
      Collected from sub-reports, deduped by gap id. Use the richer stub when duplicates exist.

   6) ## Checkpoint 2: Gap Coverage
      STRICT table — orchestrator greps for literal row labels. Column header MUST be:
      | Contract Type | Gaps Checked | Count | Notes |
      Row labels MUST be exactly: API inbound, DB, Outbound API, Jobs, UI Props (same 5 as Checkpoint 1).
      Gaps Checked MUST be one of: Yes | N/A.
      For each type that had a sub-file: Yes, with Count = number of gaps from that sub-report.
      For types marked Not applicable or Not detected in Checkpoint 1: N/A with explanation in Notes.

   WRITE $RUN_DIR/03-gaps.md. Return only 'WROTE: $RUN_DIR/03-gaps.md' when done."
```

**GATE (Checkpoint 2 shape):** Grep `$RUN_DIR/03-gaps.md` for the 5 Checkpoint 2 rows (`API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`). Every type that was `Extracted` in Checkpoint 1 must show `Yes` in Gaps Checked. If any `Extracted` type shows `N/A` or is missing, print which one and stop.

**PAUSE for user confirmation:** Print:
```
━━━ Review checkpoint 3 of 3 ━━━
Wrote: $RUN_DIR/03-gaps.md (merged from: <list of sub-files>)
Please review the gaps. Reply "continue" to generate the final report, or anything else to stop.
```
Wait. Proceed on confirmation only.

### Step 7-8: Report + findings.json

Dispatch the Staff Engineer agent:

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Report writing
Prompt:
  "TASK: Write the final report and findings.json.
   Skill directory: [path]
   Run directory: $RUN_DIR
   Unit: [unit identifier]
   Quick mode: [yes/no]

   Read $RUN_DIR/01-extraction.md, $RUN_DIR/02-audit.md, $RUN_DIR/03-gaps.md.
   Read `report-template.md` at [skill dir]/report-template.md for template, scoring rubric, and format.

   Write TWO files:
   1. $RUN_DIR/report.md — full scored report (or summary only if quick mode). Include a Hygiene section surfacing the anti-patterns from $RUN_DIR/03-gaps.md's Hygiene section.
   2. $RUN_DIR/findings.json — machine-readable gap list. IMPORTANT: include ONLY contract gaps and critical-mode gaps (money + security) from the Gap Analysis by Priority section of 03-gaps.md. DO NOT include hygiene/anti-pattern entries — those stay in report.md only. Schema:
      {
        \"unit\": \"<unit identifier>\",
        \"critical\": <bool>,
        \"gaps\": [
          {
            \"id\": \"G001\",
            \"priority\": \"HIGH|MEDIUM|LOW\",
            \"field\": \"<typed prefix + field name>\",
            \"type\": \"API inbound|DB|Outbound API|Jobs|UI Props|Money:<dimension>|Security:<dimension>\",
            \"description\": \"<what is missing>\",
            \"stub\": \"<test stub code, required for HIGH>\"
          }
        ]
      }

   Return only 'WROTE: report.md, findings.json' when done."
```

### Step 9: Deterministic Check

No agent dispatch. Run shell checks on `$RUN_DIR/findings.json`:

1. **Valid JSON:** `jq empty $RUN_DIR/findings.json` (or fallback python3 json parse)
2. **HIGH gaps have stubs:** `jq -e '.gaps | map(select(.priority == "HIGH" and (.stub == null or .stub == ""))) | length == 0' $RUN_DIR/findings.json`
3. **All Extracted types represented:** for each Checkpoint 1 type with status `Extracted` in `01-extraction.md`, `jq` must find at least one gap OR the report must explicitly note coverage is complete. (Skip this check if the type is `Not detected` or `Not applicable`.)

Print:
- **PASS:** `✓ Step 9 checks passed. Report: $RUN_DIR/report.md`
- **FAIL:** `✗ Step 9 check failed: <which check, what's wrong>`. Do not re-dispatch. Surface the failure so a human can inspect.

## Review Principles

1. **Read the source, not just tests.**
2. **Be specific.** Every finding references `file:line`.
3. **Prioritize by breakage risk.**
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7.
6. **Do not run tests.** Static analysis only.
7. **One unit per run.** If you need to review multiple units, run the skill multiple times.
