# tdd-contract-review — Eval Test Plan

Test case catalogue for evaluating the `tdd-contract-review` skill. The harness grades
the artifacts a run produces; it does not re-run the interactive skill itself (the skill
has 3 checkpoints that block on `AskUserQuestion`). Run the skill version under test
manually, then run `./run-matrix.sh` to score the artifacts across all declared cases.

## Why this doc exists

- Pre-existing eval grades ONE unit (POST /api/v1/transactions) on content only — substring
  match against `expected_gaps.yaml`. It is insufficient to detect skill regressions like
  the `"fintech"` → `"critical"` schema rename, missing Checkpoint 1 rows, dropped
  `Files Examined` section, sub-files that silently disappear.
- Learning captured on 2026-04-17 in auto-memory: the evaluation harness compounds across
  every future version. Build it before running more versions.
- This plan makes each version bump auditable: a new version either passes every case or
  surfaces the regression in a specific cell of the matrix.

## How to run

Manual (one unit):

```bash
./grade-content.sh post-api-v1-transactions \
  sample-app/tdd-contract-review/20260417-1408-post-api-v1-transactions/
./grade-shape.sh \
  sample-app/tdd-contract-review/20260417-1408-post-api-v1-transactions/
```

Matrix (all declared units, latest run of each):

```bash
./run-matrix.sh            # grades every unit that has both expected_gaps + a run dir
./run-matrix.sh --strict   # fail if any unit has no run dir to grade
./run-matrix.sh --unit post-api-v1-transactions   # single-unit
```

`run-matrix.sh` writes a JSON summary to `benchmark/last-eval.json` (git-ignored) and prints
a pass/fail matrix. Exit code is 0 iff every case passes.

## Test Case Categories

Five categories, decreasing by automation readiness. A and B are fully automated today.
C/D/E are documented as a Phase 2 roadmap — each needs either fixture scaffolding or a
way to drive the skill non-interactively.

### A. Gap Detection (content)

Does the skill find the seeded gaps in each unit? This is the existing `grade-content.sh` style —
substring match against `expected_gaps.yaml`. Expanded from one unit to five to cover
contract-type variety (create vs read vs update), critical-mode sensitivity, and the
headline "no tests at all" case (`PATCH /wallets/:id`).

| Case | Unit slug                      | Source                                                      | Critical | Why this case                                                         |
|------|--------------------------------|-------------------------------------------------------------|----------|-----------------------------------------------------------------------|
| A1   | post-api-v1-transactions       | app/controllers/api/v1/transactions_controller.rb (create)  | ON       | Richest unit, full pipeline (API+DB+Outbound+Money+Security)          |
| A2   | post-api-v1-wallets            | app/controllers/api/v1/wallets_controller.rb (create)       | ON       | Critical-lite — balance/currency but no outbound, exercises lighter path |
| A3   | patch-api-v1-wallets           | app/controllers/api/v1/wallets_controller.rb (update)       | ON       | No existing tests at all; known data-leak bug in 422 response         |
| A4   | get-api-v1-transactions        | app/controllers/api/v1/transactions_controller.rb (index)   | OFF-leaning | Tests pagination + date filters + IDOR on list read                |
| A5   | get-api-v1-transactions-id     | app/controllers/api/v1/transactions_controller.rb (show)    | OFF-leaning | IDOR on single-resource read (non-create endpoint)                 |

Pass criterion per case: every `match` pattern in the unit's expected_gaps section hits
a corresponding entry in findings.json. Priority-label mismatches are reported but not
gating (priority drift is information; absence is the failure).

### B. Structural Invariants (shape)

Cheap bash checks on a run directory. These catch skill regressions that content grading
misses — e.g. the schema rename or a dropped section. Every case is a grep / jq one-liner.

| Case  | Assertion                                                                                 | File            |
|-------|-------------------------------------------------------------------------------------------|-----------------|
| B1    | findings.json is valid JSON                                                               | findings.json   |
| B2    | findings.json top-level keys: `unit` (string), `critical` (bool), `gaps` (array)          | findings.json   |
| B3    | Every gap has `id`, `priority`, `field`, `type`, `description`                            | findings.json   |
| B4    | Every HIGH gap has a non-empty `stub`                                                     | findings.json   |
| B5    | No gap has `type` starting with `Fintech:` (schema-rename regression guard)               | findings.json   |
| B6    | No gap description mentions "hygiene" / "anti-pattern" (those live in report.md only)     | findings.json   |
| B7    | `01-extraction.md` contains `## Summary`, `## Files Examined`, `## Checkpoint 1`          | 01-extraction   |
| B8    | Checkpoint 1 table has 5 required rows, exact labels, 3-state status                      | 01-extraction   |
| B9    | `Files Examined` has `### Call trees` and `### Root set` subsections                       | 01-extraction   |
| B10   | `02-audit.md` contains `## Summary`, `## Test Inventory`, `## Per-Field Coverage Matrix`  | 02-audit        |
| B11   | `02-audit.md` grep-count equals Test-Inventory-count (reconciliation line)                | 02-audit        |
| B12   | `02-audit.md` does NOT contain `## Gaps` or `## Scorecard` (belong to later steps)        | 02-audit        |
| B13   | Per-type sub-file exists for each Extracted type from Checkpoint 1 (03a/03b/03c)          | run dir         |
| B14   | In critical mode, 03d-gaps-money.md and 03e-gaps-security.md exist                        | run dir         |
| B15   | Each per-type sub-file has `## Test Structure Tree (<TYPE>)` and `## Contract Map (<TYPE>)` | 03a/b/c         |
| B16   | Gap IDs use the right prefix per sub-file (GAPI in 03a, GDB in 03b, GOUT in 03c)          | 03a/b/c         |
| B17   | `03-gaps.md` contains Summary + Test Structure Tree (unified) + Contract Map (unified) + Gap Analysis by Priority + Hygiene + Checkpoint 2 | 03-gaps         |
| B18   | Checkpoint 2 table: every Extracted type from Checkpoint 1 shows `Yes` in Gaps Checked    | 03-gaps         |
| B19   | `report.md` exists and is non-empty                                                       | report.md       |
| B20   | `findings.json` has at least one gap per Extracted type OR explicit coverage note in report.md | cross-file |

B1–B20 run identically against every A-case run dir. The same run directory is graded
by both an A-case (content) and all B-cases (shape). That's why the tests compound: one
run yields ~21 graded assertions.

### C. Argument & Discovery (gates) — Phase 2

These exercise the Step 1–2 guard paths. They require either (a) a small fixture with
known ambiguity/not-found state or (b) a harness that drives the skill non-interactively
until the guard prints its error.

| Case  | Input                                                | Expected result                                     |
|-------|------------------------------------------------------|-----------------------------------------------------|
| C1    | `POST /api/v1/transactions`                          | Resolves to transactions_controller.rb#create, proceeds |
| C2    | `TransactionService`                                 | Resolves to app/services/transaction_service.rb, proceeds |
| C3    | `app/services/transaction_service.rb`                | Uses path directly, proceeds                        |
| C4    | (no argument)                                        | Prints usage, exits without creating $RUN_DIR       |
| C5    | `POST /no/such/route`                                | Prints "not found" + fuzzy suggestions, exits       |
| C6    | `Wallet` (ambiguous — matches model + request spec)  | Prints "ambiguous. Candidates:" + numbered list, exits |
| C7    | `POST /api/v1/transactions random-garbage-flag`      | Either ignores unknown flag or exits — document actual behaviour |

### D. Critical-Mode Detection — Phase 2

| Case  | Unit + flag                                            | Expected detection                                  |
|-------|--------------------------------------------------------|-----------------------------------------------------|
| D1    | POST /api/v1/transactions (auto)                       | Critical mode ON — decimal amount + balance + PaymentGateway |
| D2    | GET /api/v1/wallets (auto)                             | Critical mode ON (balance field serialized) — known to trip |
| D3    | A fixture endpoint with zero money signals (auto)      | Critical mode OFF                                   |
| D4    | POST /api/v1/transactions `no-critical`                | Forced OFF, skips 03d/03e                           |
| D5    | Non-money endpoint `critical`                          | Forced ON, runs 03d/03e anyway                      |

D3 needs a new fixture (a tiny standalone controller without money signals); the sample
app is fintech-saturated and can't express an OFF case faithfully.

### E. Reuse & Revision paths — Phase 2

| Case  | Scenario                                                   | Expected                                            |
|-------|------------------------------------------------------------|-----------------------------------------------------|
| E1    | No prior extraction dir for unit                           | Step 2.6 silent, proceeds to Step 3                 |
| E2    | Prior extraction exists, same critical mode                | AskUserQuestion offered, Reuse copies + goes to Checkpoint 1 |
| E3    | Prior extraction exists, different critical mode           | AskUserQuestion offered WITH mismatch warning line  |
| E4    | Reuse picked, but prior file malformed (missing Checkpoint 1 row) | GATE fails, falls through to fresh extraction |
| E5    | Free-text feedback at Checkpoint 1 ("look closer at audit log fields") | Step 3 agent re-dispatched with REVISION REQUEST block appended verbatim |
| E6    | Free-text feedback at Checkpoint 2 ("please add the foo scenario") | REVISION REQUEST block appended verbatim    |
| E7    | 4th visit to same checkpoint                               | Prompt prefix added; further free-text treated as Continue |
| E8    | Free-text feedback at Checkpoint 3 naming one contract type | That single per-type agent re-dispatched, then merge agent re-runs |

AskUserQuestion only surfaces Continue / Stop — auto-iterate `Revise` was removed in v0.45.0
(see CHANGELOG). All revision goes through the free-text path, which requires specific user input.

Realistic automation of E requires intercepting the skill's tool calls (mock
AskUserQuestion, mock Agent dispatch, capture prompts). Worth it once E4/E8 regressions
become expensive.

## Test Case Registry

Declarative source of truth. `run-matrix.sh` loops this list.

| ID   | Category | Unit slug                  | Automated | Needs                                     |
|------|----------|----------------------------|-----------|-------------------------------------------|
| A1   | A        | post-api-v1-transactions   | yes       | existing expected_gaps + run dir           |
| A2   | A        | post-api-v1-wallets        | yes       | expected_gaps entry (added in this PR)     |
| A3   | A        | patch-api-v1-wallets       | yes       | expected_gaps entry (added in this PR)     |
| A4   | A        | get-api-v1-transactions    | yes       | expected_gaps entry (added in this PR)     |
| A5   | A        | get-api-v1-transactions-id | yes       | expected_gaps entry (added in this PR)     |
| B*   | B        | (applies to every A-run)   | yes       | grade-shape.sh (added in this PR)          |
| C*   | C        | —                          | no        | gate-capture harness or recorded invocations |
| D*   | D        | —                          | partial   | non-money fixture + skill-run capture      |
| E*   | E        | —                          | no        | tool-call interception                     |

## Phase 2 Roadmap

To close C/D/E deterministically without running the skill end-to-end:

1. **Gate-capture mode.** Add a `--dry-run-guard` flag to the skill that runs Steps 1–2
   (argument parse + unit guard + critical-mode detection) and exits after printing a
   machine-readable status line. Grade with grep. Closes C1–C7 and D1–D5.

2. **Mini-fixtures directory.** `benchmark/fixtures/` with tiny apps that trigger specific
   guard paths: `no-money/` (for D3), `ambiguous-unit/` (for C6), `duplicate-route/` (alt C6).
   Cheap and self-contained.

3. **Tool-call transcripts.** Record the Agent tool prompts the skill dispatches for known
   good/bad runs. Replay detection: for a new version, dispatch same prompts, diff outputs.
   Covers E5/E6 DEEPEN and REVISION request propagation.

4. **Prior-run fixture.** Checked-in sample `01-extraction.md` files (same-critical, different-critical, malformed) under `benchmark/fixtures/prior-extractions/` so Step 2.6
   branches can be exercised from a contrived `$PREV_EXTRACTION`. Closes E2–E4.

None of these are needed for the compound value promised by A+B. Add them when a C/D/E
regression actually bites.

## Versioning

When a new plugin version ships:

1. Run the skill manually against each A-case unit (5 runs).
2. Run `./run-matrix.sh` — grades all runs in one pass.
3. Append a row to `results.md` with the version, matrix pass/fail counts, and any
   new-version-only notes. Keep the historical matrix — regressions are best diagnosed
   against prior passes.
