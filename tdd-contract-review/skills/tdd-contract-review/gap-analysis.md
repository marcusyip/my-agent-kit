<!-- version: 0.34.1 -->
# Gap Analysis Reference

Detailed guidance for Step 6 of the TDD Contract Review workflow. Step 6 runs per-type gap agents in parallel (A = API inbound, B = DB, C = Outbound API), plus two cross-cutting agents in critical mode (F1 = money-correctness, F2 = API-security), then a single merge agent (6c) that produces the unified `03-gaps.md`.

## Scenario Enumeration Rules (per-type agents A/B/C)

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

For each gap:

- **id**: `G<TYPE_PREFIX>-<NNN>` (e.g., `GAPI-001`, `GDB-001`, `GOUT-001`)
- **priority**: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW`
- **field**: typed prefix + field name
- **type**: `<CONTRACT_TYPE>`
- **description**: what is missing
- **stub**: REQUIRED for CRITICAL and HIGH

### 4. `## Test Stubs`

Pseudocode in the detected test framework's style, one stub per HIGH/CRITICAL gap.

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
- **stub**: REQUIRED for CRITICAL and HIGH

### 3. `## Test Stubs`

Pseudocode per HIGH/CRITICAL gap.

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
- **stub**: REQUIRED for CRITICAL and HIGH

### 3. `## Test Stubs`

Pseudocode per HIGH/CRITICAL gap.

## Output File Shape — Merged Report (`03-gaps.md`)

Step 6c reads every sub-file that exists (`03a-gaps-api.md`, `03b-gaps-db.md`, `03c-gaps-outbound.md`, `03d-gaps-money.md`, `03e-gaps-security.md`) plus `02-audit.md`'s anti-patterns section, and produces the unified `03-gaps.md`. Skip any sub-file that does not exist.

The merged file has 7 sections in this order.

### 1. `## Summary`

Scannable one-screen overview shown at Checkpoint 3 before the user is asked to proceed. Bullets only, 4-8 lines max. No prose.

```
## Summary

- Gaps by priority: CRITICAL: <N>, HIGH: <N>, MEDIUM: <N>, LOW: <N>
- Gaps by contract type: API: <N> | DB: <N> | Outbound: <N> | Money: <N> | Security: <N>  (omit lines for types not present)
- Test stubs generated: <N> (for CRITICAL + HIGH gaps)
- Hygiene/anti-patterns carried from audit: <N>
```

### 2. `## Test Structure Tree (unified)`

One root (the unit identifier). Under it, concatenate per-type branches grouped by contract type:

- `### API inbound` (from `03a-gaps-api.md`)
- `### DB` (from `03b-gaps-db.md`)
- `### Outbound API` (from `03c-gaps-outbound.md`)

Preserve every field branch and every scenario verbatim from the sub-files.

### 3. `## Contract Map (unified)`

Single table with all rows from all sub-reports. Column header:

```
| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
```

### 4. `## Gap Analysis by Priority`

Merge gap lists from all sub-reports. **Dedupe** by `(field + description key phrase)`. When duplicates appear (e.g., F1 money + outbound agent both flag amount-mismatch, or F2 security + API agent both flag missing auth), keep the highest priority, combine descriptions, keep the richer stub.

Group by `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` in that order.

### 5. `## Hygiene (from audit)`

Copy the anti-patterns section from `$RUN_DIR/02-audit.md` verbatim (with `file:line` references). These are test-code hygiene issues, NOT contract gaps. They inform the report but are excluded from `findings.json`.

### 6. `## Test Stubs for CRITICAL / HIGH Gaps`

Collected from sub-reports, deduped by gap id. Use the richer stub when duplicates exist.

### 7. `## Checkpoint 2: Gap Coverage`

STRICT table — the orchestrator greps for literal row labels. Column header MUST be:

```
| Contract Type | Gaps Checked | Count | Notes |
```

- Row labels MUST be exactly: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props` (same 5 as Checkpoint 1).
- `Gaps Checked` MUST be one of: `Yes` | `N/A`.
- For each type that had a sub-file: `Yes`, with `Count` = number of gaps from that sub-report.
- For types marked `Not applicable` or `Not detected` in Checkpoint 1: `N/A` with an explanation in `Notes`.
