<!-- version: 0.50.1 -->
# Gap Analysis Reference

Detailed guidance for Step 6 of the TDD Contract Review workflow. Step 6 runs per-type gap agents in parallel (A = API inbound, B = DB, C = Outbound API), plus two cross-cutting agents in critical mode (F1 = money-correctness, F2 = API-security). A final shell-only step (6c) writes a tiny index file (`03-index.md`) with gap counts and clickable links to each sub-file — there is no merge agent. Dedupe of overlapping gaps (F1 ↔ A, F2 ↔ A) happens inside Step 7 while the final report is composed.

## Scenario Enumeration Rules (per-type agents A/B/C)

**JSON schema field names (mandatory — wrong names cause render failure).** The renderer validates `$RUN_DIR/03[a-e]-gaps-*.json` against `[plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json` with `additionalProperties: false` everywhere. Use these exact field names.

**`test_tree.fields[].scenarios[]`** entries:
- REQUIRED: `description` (string — scenario text including expected outcome, e.g., `"nil → 422, no DB write, no data leak"`), `covered` (boolean — `true` / `false`, NEVER a string like `"✓"` / `"✗"` / `"covered"` / `"missing"`)
- OPTIONAL: `test_ref` (object `{path, line?, end_line?, note?}` or `null` — never a plain `"path:line"` string. Only `path` is required inside the object; omit `line` if not precisely known.), `partial_note` (string — only when `covered: true` but the assertion is weak)
- BANNED: `scenario`, `status`, `name`, `file`, `check`. Use `description` instead of `scenario`/`name`; use `covered: true|false` instead of `status: "covered"`/`"missing"`.

**`test_tree.fields[]`** entries:
- REQUIRED:
  - `field` (string — MUST include the typed prefix: `"request header: <name>"`, `"request field: <name>"`, `"response field: <name>"`, `"db field: <name>"`, `"outbound request field: <name>"`, `"outbound response field: <name>"`. NEVER a bare name like `"amount"` or `"status"` — without the prefix the reader cannot tell whether the field is set in the request or asserted on the response, and the tree loses most of its diagnostic value.)
  - `status` (enum: `"COVERED"` | `"PARTIAL"` | `"MISSING"`)
  - `scenarios` (array of scenario objects above)
- BANNED extras: `typed_prefix` (the prefix is INSIDE `field`, not a separate key), `role`, `type`, `constraints`, `notes`. These belong on `contract_map` rows, not on `test_tree.fields[]`.

**`contract_map`** rows:
- REQUIRED: `field` (string), `role` (enum: `"Input"` | `"Assertion"` — exactly these two strings. NEVER `"input"`, `"assertion"`, `"Both"`, `"N/A"`, or anything else; pick the dominant role per row), `scenarios_needed` (string — comma-separated free-form list), `gap_count` (string, NOT integer — e.g., `"0"`, `"2"`, `"3 (1 PARTIAL)"`)
- OPTIONAL: `field_kind` (string — left-most column in the rendered map, e.g., `"request field"`, `"response field"`, `"db field (input)"`), `current_coverage` (string)
- BANNED extras: `typed_prefix`, `scenarios_required`, `scenarios_covered`, `status`, `confidence`.

---

Every contract field produces a tree branch. The scenarios under it are derived from `scenario-checklist.md`, applied to the field's type and constraints.

- Every **input field** gets its own tree branch with enumerated scenarios.
- Every **assertion field** gets its OWN branch. Do NOT collapse assertions into a grouped 'HAPPY PATH assertions' block.
- Every **enum value** is its own scenario (e.g., `status` enum with 4 values = 4 scenarios, not 1).
- Status per scenario: `✓ covered` (cite `test file:line`) | `✗ missing` | `PARTIAL` (weak assertion — explain the weakness).

In critical mode, per-type agents also consult `money-correctness-checklists.md` and `api-security-checklists.md` for per-field checks relevant to the type (precision, enum values, sensitive-data leak, injection, etc.).

## Output File Shape — Per-type Sub-report (A/B/C)

Each per-type agent writes to a sub-file named in SKILL.md's substitution table (`03a-gaps-api.md` / `03b-gaps-db.md` / `03c-gaps-outbound.md`). The file has 4 sections.

Section headers MUST be exactly the literal H2 strings below, in this order. Do NOT number them (no `## 1. Test Structure Tree`). Do NOT add prefixes or suffixes beyond the `(<CONTRACT_TYPE>)` qualifier shown.

### 1. `## Test Structure Tree (<CONTRACT_TYPE>)`

Root: the unit identifier. Branches per field with scenarios enumerated from the checklist.

### 2. `## Contract Map (<CONTRACT_TYPE>)`

Table. Column header:

```
| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
```

One row per field. `Scenarios Required` = comma-separated list of scenario names derived from the checklist for this field's type + constraints.

### 3. `## Gap List`

For each gap, write exactly these bullets at the top level (no nesting, no bold-inline attributes, no alternate ordering):

```
- **id**: G<TYPE_PREFIX>-<NNN>
- **priority**: CRITICAL
- **field**: typed prefix + field name
- **type**: <CONTRACT_TYPE>
- **description**: what is missing
- **stub**: (REQUIRED for CRITICAL; omit for HIGH/MEDIUM/LOW)
```

- `<TYPE_PREFIX>` is `API`, `DB`, `OUT`, `MONEY`, or `SEC`; gap ids therefore look like `GAPI-001`, `GDB-001`, `GOUT-001`, `GMONEY-001`, `GSEC-001`.
- `- **priority**: <PRIORITY>` MUST match this exact regex on its own line: `^- \*\*priority\*\*: (CRITICAL|HIGH|MEDIUM|LOW)$`. Step 6c greps this to count gaps per priority for the index file; any deviation produces a wrong count. Do not bold the value, do not add a period.
- `- **id**: G<PREFIX>-<NNN>` MUST match `^- \*\*id\*\*: G[A-Z]+-[0-9]+` on its own line. Step 6c greps this to count gaps per sub-file.

### 4. `## Test Stubs`

Pseudocode in the detected test framework's style, one stub per **CRITICAL** gap. HIGH/MEDIUM/LOW gaps carry no stub — field + description + priority is enough for a developer to write the real test. If there are no CRITICAL gaps in this sub-file, write `No CRITICAL gaps.` under the heading (do not omit the section).

## Output File Shape — F1 Money-Correctness (`03d-gaps-money.md`)

The F1 agent reads `money-correctness-checklists.md`. Its focus is SYSTEMIC cross-contract-type money-correctness gaps: precision anti-patterns, idempotency, transaction state machine integrity (transitions + terminal states), balance/ledger integrity, position/inventory integrity, concurrency (TOCTOU, lock placement, atomic balance updates), multi-step DB transaction atomicity, compensating actions on failures, external payment integration correctness (retry, reconciliation), refunds/reversals lifecycle, fees/tax calculation, holds/authorizations lifecycle, time/settlement/cutoffs, FX/conversion, transaction limit enforcement. Do NOT duplicate per-field gaps that the per-type agents will find — focus on unit-level integrity that spans multiple contract types.

### 1. `## Cross-cutting Money-Correctness Gaps`

For each dimension present in the checklist, assess and list gaps. For dimensions without gaps, write `No gaps detected`.

### 2. `## Gap List`

For each gap:

- **id**: `GMONEY-<NNN>`
- **priority**: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW`
- **field**: use `unit-level` for systemic dimensions (Idempotency, StateMachine integrity, Concurrency, multi-step atomicity, Reconciliation, Settlement). Only use a specific field when the gap is genuinely scoped to one field (e.g., Money/Precision on a specific amount field, FX rate on a specific quote field). Do NOT attach a systemic concern to a loosely-related field.
- **type**: `Money:<dimension>` — examples: `Money:Precision`, `Money:Idempotency`, `Money:StateMachine`, `Money:BalanceLedger`, `Money:PositionInventory`, `Money:Concurrency`, `Money:ExternalIntegration`, `Money:Refunds`, `Money:FeesTax`, `Money:Holds`, `Money:Settlement`, `Money:FX`, `Money:Limits`.
- **description**: what integrity property is missing
- **stub**: REQUIRED for CRITICAL; omit for HIGH/MEDIUM/LOW

### 3. `## Test Stubs`

Pseudocode per **CRITICAL** gap only. If there are no CRITICAL gaps, write `No CRITICAL gaps.` under the heading (do not omit the section).

## Output File Shape — F2 API-Security (`03e-gaps-security.md`)

The F2 agent reads `api-security-checklists.md`. Its focus is SYSTEMIC cross-contract-type security gaps: authentication coverage, authorization (IDOR on any resource-ID-accepting endpoint), privilege escalation, resource enumeration, rate limiting (per-user, not just per-IP), sensitive-data leaks in error/list responses, injection surfaces on string fields reaching DB/logs/HTML, audit trail absence and immutability, KYC/AML/sanctions gating, PCI scope, high-value operation MFA/approval, API key scoping, webhook trust (signature verification, replay protection, timestamp tolerance, tampered payload rejection). Do NOT duplicate per-field gaps that the per-type agents will find — focus on unit-level security integrity spanning contract types.

### 1. `## Cross-cutting API-Security Gaps`

For each dimension present in the checklist, assess and list gaps. For dimensions without gaps, write `No gaps detected`.

### 2. `## Gap List`

For each gap:

- **id**: `GSEC-<NNN>`
- **priority**: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW`
- **field**: use `unit-level` for systemic dimensions (Auth, AuthZ/IDOR, RateLimit, AuditLog, KYC, Webhook). Only use a specific field when the gap is genuinely scoped to one field (e.g., injection on `request field: description`). Do NOT attach a systemic concern to a loosely-related field (e.g., rate limiting is NOT `request header: Authorization`).
- **type**: `Security:<dimension>` — examples: `Security:Auth`, `Security:AuthZ`, `Security:RateLimit`, `Security:AuditTrail`, `Security:KYC`, `Security:Webhook`, `Security:DataLeak`, `Security:Injection`, `Security:PCI`, `Security:MFA`.
- **description**: what integrity property is missing
- **stub**: REQUIRED for CRITICAL; omit for HIGH/MEDIUM/LOW

### 3. `## Test Stubs`

Pseudocode per **CRITICAL** gap only. If there are no CRITICAL gaps, write `No CRITICAL gaps.` under the heading (do not omit the section).

## Step 6c — Index file shape (`03-index.md`)

Step 6c is shell-only (no agent dispatch). It reads each sub-file that exists, counts gaps by priority and per-type, and writes `$RUN_DIR/03-index.md`. The exact bash block lives in `SKILL.md` under "Step 6c — Write `03-index.md`"; this section describes the output file's contract so the GATE and graders can verify it.

The index has exactly two top-level sections, in this order:

### 1. `## Summary`

```
## Summary

Gaps by priority (across all sub-reports):
- CRITICAL: <N>
- HIGH: <N>
- MEDIUM: <N>
- LOW: <N>

Gaps by contract type:
- API inbound: <N> — [03a-gaps-api.md](<abs-path>)
- DB: <N> — [03b-gaps-db.md](<abs-path>)
- Outbound API: <N> — [03c-gaps-outbound.md](<abs-path>)
- Money (cross-cutting): <N> — [03d-gaps-money.md](<abs-path>)     # critical mode only
- Security (cross-cutting): <N> — [03e-gaps-security.md](<abs-path>) # critical mode only

Critical mode: ON|OFF
```

Per-type lines appear only when the corresponding sub-file exists on disk. The priority counts are totals across every sub-file that exists — the same gap may be counted twice if F1 money and A API both flagged it (dedupe happens in Step 7, not here).

### 2. `## Checkpoint 3: Gap Coverage`

STRICT table — the orchestrator greps for literal row labels. Column header MUST be:

```
| Contract Type | Gaps Checked | Count | Notes |
```

- Row labels MUST be exactly these 5 strings, in this order: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props` (same 5 as Checkpoint 1).
- `Gaps Checked` MUST be one of: `Yes` | `N/A`.
- For each type with an `Extracted` status at Checkpoint 1 and a sub-file on disk: `Yes`, with `Count` = gap count from `grep -c '^- \*\*id\*\*: G'` on that sub-file, and `Notes` = `see <sub-file>`.
- For types marked `Not detected` or `Not applicable` at Checkpoint 1: `N/A` with `Count` = 0 and an explanation in `Notes`.

There is NO Test Structure Tree, NO Contract Map, NO unified Gap Analysis, NO Hygiene section, NO Test Stubs section in `03-index.md`. Those live in the per-type sub-files (trees, maps, stubs) and `02-audit.md` (hygiene). Step 7-8 reads them directly.

## Dedupe (Step 7 responsibility)

The F1 money and F2 security cross-cutting agents deliberately overlap with the per-type A/B/C agents: F1 flags amount-precision gaps on the same amount fields A-API flags; F2 flags missing auth gaps on the same endpoint A-API audits. This overlap is intentional — it is how cross-cutting concerns are caught even when a per-type agent missed them.

Step 7 (report writing) composes the final `report.md` and `findings.json` from every sub-file. During that pass, it dedupes by `(field + failure-mode key phrase)`: when two sub-files describe the same failure on the same field, the report agent keeps the highest priority, combines descriptions, and uses the richer stub. The per-type sub-files themselves are preserved unedited on disk — dedupe lives in the final synthesis, not in the sub-files.
