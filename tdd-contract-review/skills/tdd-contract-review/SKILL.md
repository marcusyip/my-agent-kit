---
name: tdd-contract-review
description: Contract-based test quality review. Reviews ONE unit per run (one HTTP endpoint, one background job, or one queue consumer). Extracts contracts, audits tests, identifies gaps, produces a scored report with test stubs, and emits machine-readable findings.json for CI grading.
argument-hint: "<unit: 'POST /path' | 'JobClass' | file.rb> [quick] [critical|no-critical]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.36.1
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
├── 03d-gaps-money.md     ← cross-cutting money-correctness sub-report (critical mode only)
├── 03e-gaps-security.md  ← cross-cutting API-security sub-report (critical mode only)
├── 03-gaps.md            ← merged unified gap report
├── report.md             ← final scored report
└── findings.json         ← machine-readable gap list for eval.sh / CI
```

Per-type sub-files are kept on disk for traceability. The merged `03-gaps.md` is what Step 7-8 consumes. Sub-reports for contract types marked `Not applicable` or `Not detected` are skipped entirely.

The `unit-slug` is lowercase kebab-case of the unit identifier:
- `POST /api/v1/transactions` → `post-api-v1-transactions`
- `ProcessPaymentJob` → `process-payment-job`
- `WithdrawalConsumer` → `withdrawal-consumer`

## Checkpoint Interaction Pattern

At each of the 3 review checkpoints, the orchestrator runs a three-step interaction: echo the agent's Summary so the user has something to review, ask the checkpoint question with `AskUserQuestion`, then branch on the selection.

### Step A — Echo Summary first

Read `$RUN_DIR/<file>` and print its `## Summary` section to the terminal. Grep the file for the literal heading `## Summary` and print every line after it up to (but not including) the next `## ` heading. Format:

```
=== Checkpoint <N> summary ($RUN_DIR/<file>) ===
<verbatim Summary section body>
==============================================
```

If no `## Summary` section is found (agent deviation), print `(Summary section missing in $RUN_DIR/<file> — open the file to review)` and proceed anyway. The step's GATE check already validates file shape; the Summary echo is a UX affordance, not a gate.

After the Summary block, print the checkpoint-specific **Review Hint** defined in that checkpoint's PAUSE section below. Format:

```
--- What to look for at Checkpoint <N> ---
<verbatim hint bullets>
-------------------------------------------
```

The hint names the two or three things most likely to matter at this checkpoint. Its job is to turn a rubber-stamp Continue into a one-minute review — especially for reviewers who don't yet have the vocabulary to spot a weak extraction or a miscalibrated gap. Print verbatim; do not paraphrase.

Then print the full report path on its own line as a **clickable markdown link** so the user can open the file before deciding:

```
Open to review: [<ABS_PATH>](<ABS_PATH>)
```

Resolve `$RUN_DIR/<file>` to an absolute filesystem path first, then substitute that same absolute path into BOTH the link label and the link target — Claude Code renders `[label](target)` as a clickable link in the terminal, and plain text (or an unresolved `$RUN_DIR`) is not clickable. Keep the line on its own with nothing trailing.

### Step B — Ask the checkpoint question

Use the `AskUserQuestion` tool — do NOT ask for free-text confirmation.

- question: `Review checkpoint <N> of 3 — proceed to <next step>?` (the clickable path is already printed in Step A; do NOT repeat `$RUN_DIR/<file>` here — `AskUserQuestion` does not render markdown, so an inline path would show as unclickable duplicate noise)
- header: `Checkpoint <N>/3`
- options (exactly these three, in this order):
  - label `Continue` — description: `Proceed to <next step>.`
  - label `Revise` — description: `Re-run this step with a deeper pass. For specific feedback, pick 'Type something else' and type it.`
  - label `Stop` — description: `Preserve files and exit.`

### Step C — Branch on selection

1. **Continue** → proceed to the next step.
2. **Stop** → preserve every file in `$RUN_DIR` and exit without proceeding. Print one line: `Stopped at checkpoint <N>. Files preserved in $RUN_DIR`.
3. **Revise** → NO follow-up question. Re-dispatch the same agent that produced the current file (the target is specified per checkpoint in that step's PAUSE reference) with the step-specific **DEEPEN REQUEST** block appended verbatim to the agent's original prompt. DEEPEN REQUEST blocks are defined near each PAUSE section below. Do NOT prompt the user for feedback.

   **Checkpoint 3 exception:** A "more complete" gap report usually means per-field gaps the per-type agents missed, not just a better merge. At Checkpoint 3, the Revise path first re-dispatches all `Extracted` per-type agents from Step 6b in parallel (each with its own deepen prompt) plus both critical-mode agents if applicable, then re-runs the merge agent. See the Checkpoint 3 PAUSE section for the per-type deepen prompt.

   After the re-dispatch(es) return, re-run the GATE check for this step. If the GATE fails, surface the failure and stop — do NOT loop on a failing gate. If the GATE passes, loop back to Step A (re-echo the updated Summary) and Step B (re-ask the checkpoint question).

4. **Type something else** (user picked the auto-provided free-text option — rendered as `Type something else` in the CLI) → interpret the typed text:
   - Affirmative words (`go`, `yes`, `ok`, `continue`, `proceed`) → treat as Continue.
   - Stop intent (`stop`, `quit`, `abort`, `cancel`, `no`) → treat as Stop.
   - Anything else → treat as **specific-feedback Revise**: re-dispatch the same agent, but append this block instead of the DEEPEN REQUEST block:

     ```
     REVISION REQUEST: The user reviewed $RUN_DIR/<file> and asked for changes. Regenerate the file, addressing this feedback verbatim:
     <paste the user's typed text here verbatim>
     Overwrite $RUN_DIR/<file>. Return only 'WROTE: $RUN_DIR/<file>' when done.
     ```

     Then re-run the GATE and loop back to Step A on pass. The typed text is passed through verbatim — the agent sees the user's own words, not a paraphrase.

**Revision cap: 3 per checkpoint**, counting any mix of Revise (deepen) and specific-feedback free-text paths. Track the count for this checkpoint in your working state for the run. On the 4th visit to the same checkpoint, drop the `Revise` option — present only `Continue` and `Stop`, and prepend `Revised 3 times already — please Continue or Stop.` to the question text.

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

If no unit identifier is provided, print the following and stop:

```
ERROR: unit identifier required.

Usage: /tdd-contract-review <unit> [quick] [critical|no-critical]

Unit examples:
  "POST /api/v1/transactions"     HTTP verb + path
  ProcessPaymentJob               class name
  app/controllers/foo.rb          file path

Flags:
  quick          abbreviated final report
  critical       force critical mode (money + API-security checklists)
  no-critical    disable critical mode even if auto-detected
```

### Step 2: Discovery + Unit Guard

1. **Find test files.** Glob for `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}`, `**/*_test.go`, `**/*_spec.rb`, `**/*.test.py`, `**/test_*.py`
2. **Detect test framework.**
3. **Resolve the unit to a single source file.**
   - If unit is `VERB /path`: grep for route definitions, find the handler.
   - If unit is a class name: glob + grep for `class ClassName`.
   - If unit is a file path: use it directly.
4. **Find DB schema files** traced from the unit's source: schema snapshot (`db/schema.rb`, `structure.sql`, `schema.prisma`) and model/entity files. Migrations are fallback only — do not include them when a snapshot exists.
5. **Find outbound API client files** traced from the unit's source.
6. **Check project conventions.** Read CLAUDE.md, config files.
7. **Detect critical mode** unless overridden by `critical`/`no-critical` arg. Money/balance/currency fields, payment gateways, or decimal types → critical mode ON (loads both money-correctness and API-security checklists).

**GATE (one-unit):** Exactly one source file must resolve from the unit identifier.
- **0 matches**: print the following and stop:
  ```
  ERROR: unit '<arg>' not found.

  Searched:
    <one line per glob / grep pattern actually tried>

  Closest matches:
    <top 3 fuzzy candidates — route definitions, class names, or file paths
     whose name shares a substring with <arg>, ranked by overlap length>
  ```
  If no fuzzy candidates exist, omit the "Closest matches" block entirely rather than printing an empty list.
- **>1 matches**: print `ERROR: unit '<arg>' ambiguous. Candidates:` followed by a numbered list, then stop.
- **1 match**: proceed.

**Compute unit-slug** from the identifier. Compute run directory: `tdd-contract-review/$(date +%Y%m%d-%H%M)-{unit-slug}/`. Create the directory. Store path as `$RUN_DIR`.

**Look for a previous extraction for this unit.** Glob `tdd-contract-review/*-{unit-slug}/01-extraction.md`, exclude `$RUN_DIR` itself, sort results by the `YYYYMMDD-HHMM` timestamp prefix in the directory name (lexicographic order works), pick the most recent. Store its path as `$PREV_EXTRACTION` (empty string if no match). This drives the optional reuse ask in Step 2.5.

**Run preview.** Before proceeding to Step 3, print this 1-screen summary so the user can interrupt before the first agent dispatch:

```
=== TDD Contract Review — Run Preview ===
Unit:                <unit identifier>
Source:              <resolved source file:line of handler or class def>
DB schema:           <N files, or "not found">
Outbound:            <N clients, or "not found">
Critical mode:       ON (reason: <one-line signal that triggered it, e.g., "decimal column 'balance' in db/schema.rb">)
                     OR OFF
Previous extraction: found at <$PREV_EXTRACTION> (<YYYY-MM-DD HH:MM from dir prefix>)
                     OR "none found (skip reuse ask)"
Pipeline:            <N> agent dispatches, 3 checkpoints
Run dir:             $RUN_DIR
```

The first checkpoint fires within ~30s of this preview (after extraction, or sooner if the user picks Reuse at Step 2.5). This preview is informational — it makes auto-detected critical mode visible and flags when a prior extraction is available for reuse. It is NOT a hard gate; do not wait for input here.

### Step 2.5: Previous Extraction Check (optional reuse)

If `$PREV_EXTRACTION` is empty, skip this step entirely — do not print anything, do not ask — and proceed to Step 3.

If `$PREV_EXTRACTION` is set, offer the user the choice to reuse it or run a fresh extraction. This saves the cost of re-extracting when iterating on the same unit with unchanged source.

**Critical-mode mismatch check (do this BEFORE the ask):** Read the `Critical mode:` line from `$PREV_EXTRACTION` (it appears in the file's `## Summary` section) and compare to the current run's critical-mode. If they differ, print a one-line warning with the path preview below: `Previous extraction was Critical mode: <X>, current run is Critical mode: <Y>. Fresh extraction recommended.`

**Path preview (print BEFORE calling AskUserQuestion):** Resolve `$PREV_EXTRACTION` to an absolute filesystem path, then print the clickable markdown link on its own line so the user can open the prior file before choosing:

```
Previous extraction: [<ABS_PATH>](<ABS_PATH>) (<timestamp from dir prefix>)
```

Same rules as the Checkpoint Interaction Pattern: substitute the same absolute path into BOTH the link label and the target — `AskUserQuestion` does not render markdown, so the clickable link must live in the preview line, not in the question text.

**AskUserQuestion** with two options (no Revise/Stop — nothing has been written in this run yet to revise):

```
Question:
  "A previous extraction for this unit exists (see path above).
   Reuse it as this run's 01-extraction.md, or run a fresh extraction?
   <critical-mode mismatch warning line if applicable>"
Options:
  A) Reuse       — copy into $RUN_DIR and go straight to Checkpoint 1
  B) Extract fresh — run the Step 3 extraction agent as normal
Multi-select: false
```

Free-text fallback (user typed something instead of picking): treat affirmative-sounding text ("reuse", "yes", "copy", "skip") as Reuse; anything else as Extract fresh.

**Branch — Reuse:**

1. Copy the file: `cp "$PREV_EXTRACTION" "$RUN_DIR/01-extraction.md"` via Bash.
2. Run the **Checkpoint 1 shape GATE** (same grep used in Step 3, described under "GATE (Checkpoint 1 shape)" below): verify all 5 required rows (`API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`) appear with a valid three-state status (`Extracted` | `Not detected` | `Not applicable`).
3. If GATE passes: jump directly to the **Checkpoint 1 PAUSE** in Step 3 — apply the Checkpoint Interaction Pattern with `<N>` = `1`, `<file>` = `01-extraction.md`, `<next step>` = `the test audit step`. The Revise target remains the Step 3 Contract extraction agent; Revise dispatches the agent with the DEEPEN REQUEST block, overwriting the reused file with a fresh, deeper extraction.
4. If GATE fails: print `GATE FAILED on reused $PREV_EXTRACTION (file is malformed or from an older skill version) — falling through to fresh extraction`, then proceed to Step 3 normally. Do not leave the malformed copy in `$RUN_DIR` — either remove it first (`rm "$RUN_DIR/01-extraction.md"`) or let Step 3's agent overwrite it.

**Branch — Extract fresh:** proceed to Step 3 directly with no file copy.

### Step 3: Contract Extraction

Determine the skill directory and plugin root. Dispatch the Staff Engineer agent. The file-shape spec for `01-extraction.md` lives in `contract-extraction.md` under "Output File Shape" — the orchestrator gate below greps for the literal row labels that spec mandates, so the agent must follow it verbatim.

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

   Read [skill dir]/contract-extraction.md in full. It contains:
   - 'Output File Shape (01-extraction.md)' — the mandatory three opening sections (Summary, Files Examined, Checkpoint 1 table). Follow row labels and column headers verbatim; the orchestrator grep-gates on them.
   - Per-framework extraction guidance for API / DB / Jobs / Outbound / UI Props.
   - 'Contract Extraction Summary Example' — the typed-prefix format for fields following the three mandatory sections.

   If critical mode: also read [skill dir]/money-correctness-checklists.md and [skill dir]/api-security-checklists.md, and append the Money-correctness + API-security dimension tables after the Contract Extraction Summary.

   WRITE the full output to $RUN_DIR/01-extraction.md. Do NOT return the content in your response body; return only 'WROTE: $RUN_DIR/01-extraction.md' when done."
```

**GATE (Checkpoint 1 shape):** Grep `$RUN_DIR/01-extraction.md` for exactly 5 Checkpoint 1 rows: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`. Each row must have a three-state status: `Extracted` | `Not detected` | `Not applicable`. If any row is missing, print which one and stop with a specific error (do not silently re-dispatch).

**PAUSE for user confirmation:** Apply the **Checkpoint Interaction Pattern** with:
- `<N>` = `1`
- `<file>` = `01-extraction.md`
- `<next step>` = `the test audit step`
- Revise re-dispatch target = the Step 3 **Contract extraction** agent above. Reuse its original prompt verbatim. On Revise (auto-iterate), append the DEEPEN REQUEST block below. On specific-feedback free-text fallback, append the REVISION REQUEST block from the Checkpoint Interaction Pattern instead.

**Review Hint (Checkpoint 1):**

```
- Files Examined drives everything. If the handler delegates to a service class that isn't listed, the extraction missed a branch — CP2 and CP3 will inherit that gap. Fixing it here is cheaper than three Revises later.
- `Not applicable` is a claim, not a gap. It asserts this contract type cannot apply to this unit. If `Outbound API: Not applicable` on a handler you think calls an external service, pick Revise — the agent may have missed the call site.
- Contract fields are the vocabulary for CP2 and CP3. A field that isn't extracted here can never be audited or gap-checked downstream. When in doubt, Revise now.
```

**DEEPEN REQUEST block (Checkpoint 1):**

```
DEEPEN REQUEST: The user reviewed $RUN_DIR/01-extraction.md and asked for a
more complete pass. Re-examine the source exhaustively:
- Re-read every file in `Files Examined` and look for fields / headers / params
  you missed.
- For every Checkpoint 1 row marked `Not detected`: investigate harder — look
  for implicit contracts (session keys, cookies, cache entries, audit-log
  fields, feature flags).
- For every `Extracted` row: count again. Optional fields, nullable columns,
  derived/computed fields, fields set via callbacks or hooks.
- If critical mode is on: re-check money-correctness and API-security
  dimensions for anything missed.
Overwrite $RUN_DIR/01-extraction.md. The `## Summary` section MUST reflect
updated counts. Return only 'WROTE: $RUN_DIR/01-extraction.md' when done.
```

### Step 4-5: Test Audit

Dispatch the Staff Engineer agent. The read protocol and `02-audit.md` file-shape spec live in `test-patterns.md`.

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
   Read [skill dir]/test-patterns.md in full. It contains:
   - 'Read Protocol (Test Audit)' — non-negotiable 3-step protocol: (1) framework-pattern grep count, (2) chunked read-to-EOF, (3) reconcile grep count against Test Inventory before writing. Skip any step and the audit is rejected.
   - 'Output File Shape (02-audit.md)' — mandatory `## Summary` preamble plus 5 sections in order: Test Inventory, Scenario Inventory, Per-Field Coverage Matrix, Assertion Depth, Anti-Patterns. Follow headings verbatim.
   - Input/Assertion Model, sessions pattern, anti-patterns to flag, quality checklists.

   WRITE the full output to $RUN_DIR/02-audit.md. Return only 'WROTE: $RUN_DIR/02-audit.md' when done."
```

**PAUSE for user confirmation:** Apply the **Checkpoint Interaction Pattern** with:
- `<N>` = `2`
- `<file>` = `02-audit.md`
- `<next step>` = `the gap analysis step`
- Revise re-dispatch target = the Step 4-5 **Test structure audit** agent above. Reuse its original prompt verbatim. On Revise (auto-iterate), append the DEEPEN REQUEST block below. On specific-feedback free-text fallback, append the REVISION REQUEST block from the Checkpoint Interaction Pattern instead.

**Review Hint (Checkpoint 2):**

```
- Reconciliation first. `Test files (grep count)` MUST equal `Test Inventory (agent count)` in the Summary. Mismatch means the agent skipped reads; Revise before judging anything else — the coverage matrix is only trustworthy once counts reconcile.
- A test that runs is not a test that verifies. WEAK assertions (presence-only checks like `expect(x).not_to be_nil`, smoke checks with no value comparison) don't catch silent corruption. Scan Assertion Depth for WEAK entries on fields that matter — money amounts, auth headers, state transitions.
- UNCOVERED fields preview CP3 gaps. Any UNCOVERED field you're surprised by (a required request param, an enum value, a computed column) is a gap you already care about. Note it before advancing; if several look wrong, Revise.
```

**DEEPEN REQUEST block (Checkpoint 2):**

```
DEEPEN REQUEST: The user reviewed $RUN_DIR/02-audit.md and asked for a more
complete pass. START WITH RECONCILIATION:
- Verify the `## Summary`: `Test files (grep count)` MUST equal
  `Test Inventory (agent count)`. If mismatch, the inventory is incomplete —
  that is the first thing to fix.
- Re-run READ PROTOCOL Step 1 (framework-pattern grep) on every test file
  to confirm the grep count is current.
- Re-run READ PROTOCOL Step 2 (chunked reads) on any file where your original
  Test Inventory was short of the grep count.
Then re-examine the tests exhaustively:
- Re-read every test file to EOF. Look for cases you skipped: nested
  describes, shared examples, helpers, setup/teardown blocks, parameterised
  tests.
- For every contract field from $RUN_DIR/01-extraction.md: confirm whether a
  test exists and cite test file:line in the Per-Field Coverage Matrix.
- Look harder for anti-patterns: mocking internal code, assertion-free tests,
  over-stubbing, fragile setup, order-dependent tests, time-sensitive tests.
- Re-check per-field coverage: each assertion, each boundary, each enum
  value, each error branch. Downgrade WEAK assertions to PARTIAL in the
  Coverage Matrix.
Overwrite $RUN_DIR/02-audit.md. The `## Summary` reconciliation lines MUST
match after revision. Return only 'WROTE: $RUN_DIR/02-audit.md' when done.
```

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

**Scenario checklist.** Every field in the Test Structure Tree MUST enumerate every applicable scenario from `[skill dir]/scenario-checklist.md`, applied per the field's type + constraints. Do NOT collapse assertion fields into a "HAPPY PATH assertions" group — each assertion field gets its own branch. Per-type prompts reference this file by path; do not inline the matrix.

**Progress output.** Before dispatching, print the plan (list only agents that will actually run — skip types marked `Not detected` / `Not applicable` in Checkpoint 1):

```
=== Step 6b: Gap analysis (<N> parallel agents) ===
→ API inbound
→ DB
→ Outbound API
→ money-correctness (critical mode)     [if critical mode]
→ API-security (critical mode)          [if critical mode]
```

After all agents return, print one `✓ <sub-file> (<N> gaps)` line per produced sub-file before proceeding to Step 6c.

**Prompt template — per-type agent (used for A/B/C):**

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Gap analysis — <CONTRACT_TYPE>
Prompt:
  "TASK: Exhaustive per-field gap analysis for CONTRACT TYPE: <CONTRACT_TYPE>
   Skill directory: [skill dir]
   Run directory: $RUN_DIR
   Critical mode: [yes/no]

   Read $RUN_DIR/01-extraction.md — focus ONLY on the <CONTRACT_TYPE> section. Ignore other contract types.
   Read $RUN_DIR/02-audit.md — identify existing test coverage for <CONTRACT_TYPE> fields.
   Read [skill dir]/scenario-checklist.md — every field in the tree MUST enumerate every applicable scenario from that matrix, applied to the field's type + constraints.
   Read [skill dir]/gap-analysis.md — follow 'Scenario Enumeration Rules (per-type agents A/B/C)' and 'Output File Shape — Per-type Sub-report (A/B/C)'. Section headings, order, and the (<CONTRACT_TYPE>) qualifier on Test Structure Tree / Contract Map are non-negotiable.
   Read [skill dir]/test-patterns.md for scenario conventions.
   If critical mode: also read [skill dir]/money-correctness-checklists.md and [skill dir]/api-security-checklists.md for per-field checks relevant to this contract type (precision, enum values, sensitive-data leak, injection).

   Use <TYPE_PREFIX> in gap ids (GAPI-NNN for API, GDB-NNN for DB, GOUT-NNN for Outbound — per the substitution table below this prompt).

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
   Read [skill dir]/gap-analysis.md — follow 'Output File Shape — F1 Money-Correctness (03d-gaps-money.md)'. The systemic focus areas (precision, idempotency, state machine, balance/ledger, concurrency, multi-step atomicity, external integration, refunds, fees/tax, holds, settlement, FX, limits) and the Money:<dimension> type format are described there. Do NOT duplicate per-field gaps that the per-type agents will find — systemic, unit-level integrity only.

   WRITE to $RUN_DIR/03d-gaps-money.md. Return only 'WROTE: $RUN_DIR/03d-gaps-money.md' when done."
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
   Read [skill dir]/gap-analysis.md — follow 'Output File Shape — F2 API-Security (03e-gaps-security.md)'. The systemic focus areas (authN, authZ/IDOR, rate limiting, data leaks, injection, audit trail, KYC/AML, PCI, MFA, webhook trust) and the Security:<dimension> type format are described there. Do NOT duplicate per-field gaps that the per-type agents will find — systemic, unit-level security integrity only.

   WRITE to $RUN_DIR/03e-gaps-security.md. Return only 'WROTE: $RUN_DIR/03e-gaps-security.md' when done."
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
   Skill directory: [skill dir]
   Run directory: $RUN_DIR

   Read every sub-file that exists: $RUN_DIR/03a-gaps-api.md, $RUN_DIR/03b-gaps-db.md, $RUN_DIR/03c-gaps-outbound.md, $RUN_DIR/03d-gaps-money.md, $RUN_DIR/03e-gaps-security.md.
   Also read $RUN_DIR/02-audit.md for the anti-patterns section.
   Skip any sub-file that does not exist.

   Read [skill dir]/gap-analysis.md — follow 'Output File Shape — Merged Report (03-gaps.md)'. The 7-section structure, Checkpoint 2 row labels, dedupe rules, and hygiene-section copy-forward are non-negotiable. The orchestrator grep-gates on the Checkpoint 2 row labels (API inbound, DB, Outbound API, Jobs, UI Props).

   WRITE $RUN_DIR/03-gaps.md. Return only 'WROTE: $RUN_DIR/03-gaps.md' when done."
```

**GATE (Checkpoint 2 shape):** Grep `$RUN_DIR/03-gaps.md` for the 5 Checkpoint 2 rows (`API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`). Every type that was `Extracted` in Checkpoint 1 must show `Yes` in Gaps Checked. If any `Extracted` type shows `N/A` or is missing, print which one and stop.

**PAUSE for user confirmation:** Apply the **Checkpoint Interaction Pattern** with:
- `<N>` = `3`
- `<file>` = `03-gaps.md`
- `<next step>` = `the final report step (Step 7-8)`
- Revise re-dispatch target — Checkpoint 3 has TWO paths:
  - **Revise (auto-iterate deepen)** — NOT just a merge re-run. A "more complete" gap report usually means per-field gaps the per-type agents missed, not just a better merge. Execute this sequence:
    1. Re-dispatch all per-type agents from Step 6b (every agent whose sub-file exists) in parallel, each with the **Per-type DEEPEN REQUEST block** appended to its Step 6b prompt. Include the F1 money-correctness and F2 API-security agents if their sub-files exist. Print the same `=== Step 6b: Gap analysis (<N> parallel agents) ===` plan line and the `✓ <sub-file> (<N> gaps)` breadcrumbs as the original Step 6b run.
    2. After all per-type agents return and the Step 6b sub-files GATE passes, re-dispatch the Step 6c **Gap merge** agent with the **Merge DEEPEN REQUEST block** appended.
    3. Re-run the Checkpoint 2 gap-coverage GATE on the updated `$RUN_DIR/03-gaps.md`. If it fails, surface the failure and stop.
  - **Specific-feedback free-text fallback** (user typed free text that is not affirmative / not stop-intent) — re-dispatch only the Step 6c **Gap merge** agent with the REVISION REQUEST block from the Checkpoint Interaction Pattern. If the typed text clearly names a single contract type that needs re-analysis (not just re-merging), you MAY first re-dispatch that single per-type agent from Step 6b, then re-run the merge agent.

**Review Hint (Checkpoint 3):**

```
- Priority calibration is the main risk. CRITICAL = data loss, security breach, or money off by a cent. If a CRITICAL gap reads "academic" or a MEDIUM describes a real outage path, use the free-text Revise path with specific re-calibration feedback — the agent will honor typed requests verbatim.
- Test stubs are executable specs. Read one CRITICAL stub end-to-end — if you can't tell what it asserts, the gap description isn't concrete enough to act on. That's a Revise signal, not a Continue signal.
- Dedupe sanity check. The cross-cutting money (F1) and security (F2) agents overlap with the per-type agents by design. The merge step is supposed to collapse duplicates (same field + same failure mode). Two gaps describing the same failure mean the merge missed — Revise.
```

**Per-type DEEPEN REQUEST block (appended to each Step 6b per-type agent):**

```
DEEPEN REQUEST: Re-examine your previous $RUN_DIR/<sub-file>. For every field
in your Contract Map:
- Re-enumerate scenarios from [skill dir]/scenario-checklist.md — are any
  applicable scenarios missing from the Test Structure Tree?
- For each ✓ covered status: re-verify the cited test file:line actually
  asserts what the scenario requires. Weak assertion → downgrade to PARTIAL.
- For each ✗ missing or PARTIAL: is the priority right given critical mode?
Overwrite $RUN_DIR/<sub-file>. Return only 'WROTE: $RUN_DIR/<sub-file>' when done.
```

**Merge DEEPEN REQUEST block (appended to the Step 6c merge agent):**

```
DEEPEN REQUEST: The per-type sub-files have been re-generated with a deeper
pass. Re-merge $RUN_DIR/03-gaps.md from the updated sub-files. In addition:
- Look harder for cross-type interactions (e.g., an API field and a DB column
  that both map to the same logical entity and share a gap).
- Re-calibrate priorities: if critical mode is on, missing coverage on money
  or security dimensions should usually be CRITICAL or HIGH, not MEDIUM.
- Keep dedupe rules from the original prompt (highest priority wins, combine
  descriptions, keep richer stub).
Overwrite $RUN_DIR/03-gaps.md. The `## Summary` section MUST reflect updated
counts. Return only 'WROTE: $RUN_DIR/03-gaps.md' when done.
```

### Step 7-8: Report + findings.json

Dispatch the Staff Engineer agent. The report template, findings.json schema, scoring rubric, and output rules all live in `report-template.md`.

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
   Read [skill dir]/report-template.md in full. It contains:
   - 'Output Instructions' — what to write to report.md vs findings.json, Hygiene section requirement, and the rule that findings.json must include all four priorities (CRITICAL, HIGH, MEDIUM, LOW) and must NOT include hygiene entries.
   - 'findings.json Schema' — exact JSON schema and field rules. CRITICAL+HIGH gaps MUST have a stub; Step 9 gate-checks this.
   - 'Scoring' — 6-category rubric, weights, verdict bands, and calibration anchors.
   - 'report.md Template' — full report structure (default mode).
   - 'Quick Mode Template' — abbreviated form when quick mode is on.

   Return only 'WROTE: report.md, findings.json' when done."
```

### Step 9: Deterministic Check

No agent dispatch. Run shell checks on `$RUN_DIR/findings.json`:

1. **Valid JSON:** `jq empty $RUN_DIR/findings.json` (or fallback python3 json parse)
2. **CRITICAL+HIGH gaps have stubs:** `jq -e '.gaps | map(select((.priority == "CRITICAL" or .priority == "HIGH") and (.stub == null or .stub == ""))) | length == 0' $RUN_DIR/findings.json`
3. **All Extracted types represented:** for each Checkpoint 1 type with status `Extracted` in `01-extraction.md`, `jq` must find at least one gap OR the report must explicitly note coverage is complete. (Skip this check if the type is `Not detected` or `Not applicable`.)

Print:
- **PASS:** `✓ Step 9 checks passed. Report: [<ABS_PATH>](<ABS_PATH>)` — resolve `$RUN_DIR/report.md` to an absolute filesystem path and substitute it into BOTH the link label and target so Claude Code renders a clickable link.
- **FAIL:** `✗ Step 9 check failed: <which check, what's wrong>`. Do not re-dispatch. Surface the failure so a human can inspect.

## Review Principles

1. **Read the source, not just tests.**
2. **Be specific.** Every finding references `file:line`.
3. **Prioritize by breakage risk.**
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7.
6. **Do not run tests.** Static analysis only.
7. **One unit per run.** If you need to review multiple units, run the skill multiple times.
