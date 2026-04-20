# tdd-contract-review

A Claude Code plugin that reviews test quality through **contract-based analysis**, identifies gaps, and auto-generates test stubs for the missing coverage.

One run reviews ONE unit -- one HTTP endpoint, one background job, or one queue consumer. The plugin extracts contracts from source (API request/response fields, DB model fields, outbound API call params, UI component props), maps test coverage per field, identifies gaps, and emits a scored report plus a machine-readable `findings.json` for CI grading.

## Philosophy

Tests protect against breaking changes by verifying contracts -- the agreements between components about data shape and behavior. A contract field without tests means changes to that field can break things silently.

**Principles:**
- Test contracts, not implementation details
- Mock minimally -- only external API calls
- Use real database, never mock DB
- Group tests by feature > field so gaps are visible at a glance

## Installation

```bash
claude plugin install path/to/tdd-contract-review
```

Or manually copy the plugin directory into your Claude Code plugins location.

## Usage

```
/tdd-contract-review "POST /api/v1/transactions"
/tdd-contract-review ProcessPaymentJob
/tdd-contract-review app/controllers/api/v1/transactions_controller.rb
/tdd-contract-review "POST /api/v1/transactions" quick
/tdd-contract-review "POST /api/v1/transactions" critical
/tdd-contract-review "POST /api/v1/transactions" no-critical
```

**Arguments:**
- **unit identifier** (required): `VERB /path`, a class name, or a source file path
- **`quick`** (optional): abbreviated report, HIGH gaps only
- **`critical`** / **`no-critical`** (optional): force critical mode on or off. Critical mode loads BOTH the money-correctness and API-security checklists and runs two extra cross-cutting gap agents. It is auto-detected from money/balance/currency fields, payment gateways, and decimal types.

## Workflow

The skill is an orchestrator that dispatches a Staff Engineer agent at each step, writes intermediate artifacts to disk, and pauses for user review at three checkpoints. Every run writes to a flat, unit-scoped directory: `tdd-contract-review/{YYYYMMDD-HHMM}-{unit-slug}/`.

| Step | Action | Model | Artifact |
|---|---|---|---|
| 1-2 | **Discovery + Unit Guard** -- resolve the unit to exactly one source file, detect critical mode, print run preview | -- | -- |
| 2.5 | **Previous-extraction reuse** (optional) -- if a prior extraction for this unit exists, offer to reuse instead of re-running Step 3 | -- | copies `01-extraction.md` |
| 3 | **Contract Extraction** -- extract API inbound / DB / Outbound API / Jobs / UI Props contracts with typed field prefixes | sonnet | `01-extraction.md` |
|  | **Checkpoint 1** -- user reviews extraction shape, Files Examined, `Not applicable` vs `Not detected` claims |
| 4-5 | **Test Audit** -- inventory tests, reconcile grep count vs agent count, per-field coverage matrix, assertion depth, anti-patterns | sonnet | `02-audit.md` |
|  | **Checkpoint 2** -- user reviews reconciliation, WEAK assertions on fields that matter, UNCOVERED fields |
| 6a | **Type selection** -- for each `Extracted` contract type, dispatch one per-type agent; if critical mode, add F1/F2 | -- | -- |
| 6b | **Per-type gap analysis (parallel)** -- A: API inbound, B: DB, C: Outbound API; F1: money-correctness, F2: API-security (critical mode only) | A/B/C sonnet, F1/F2 **opus** | `03a-gaps-api.md`, `03b-gaps-db.md`, `03c-gaps-outbound.md`, `03d-gaps-money.md`, `03e-gaps-security.md` |
| 6c | **Merge** -- dedupe per-type gaps, collapse F1/F2 overlap with A/B/C, calibrate priorities, copy-forward hygiene findings | **opus** | `03-gaps.md` |
|  | **Checkpoint 3** -- user reviews priority calibration, stub concreteness, dedupe sanity |
| 7-8 | **Report + findings.json** -- scored `report.md` with test stubs + machine-readable `findings.json` for CI | sonnet | `report.md`, `findings.json` |
| 9 | **Deterministic gate** -- `jq` checks: valid JSON, CRITICAL+HIGH gaps have stubs, all Extracted types represented | -- | -- |

At each checkpoint the user picks **Continue** / **Revise** / **Stop**. Revise auto-dispatches a DEEPEN pass on the responsible agent; free-text feedback re-dispatches with the user's words verbatim. Cap: 3 revises per checkpoint.

## Design Rationale

- **One unit per run.** Extraction depth scales with focus; batching units yields shallow analysis and tangled gap reports.
- **Three human checkpoints.** CP1 locks the contract vocabulary, CP2 reconciles test counts, CP3 calibrates priorities -- the judgments humans are better at than the model.
- **Parallel per-type gap agents + merge.** Splitting by contract type keeps each agent's context narrow enough to enumerate every scenario per field instead of collapsing them. Critical mode adds two cross-cutting agents (money, security) kept separate from A/B/C.
- **Model split.** Per-type enumeration uses sonnet; merge and cross-cutting synthesis use opus. Opus where reasoning quality pays off, sonnet where it doesn't.

Token cost per run: ~160k non-critical / ~290k critical. See [`benchmark/notes/token-usage.md`](./benchmark/notes/token-usage.md) for the per-step breakdown.

## Scoring

| Category | Weight | Focus |
|---|---|---|
| Contract Coverage | 25% | Are all contract fields tested? |
| Test Grouping | 15% | Grouped by feature > field for visible gaps? |
| Scenario Depth | 20% | Per field: null, empty, boundary, invalid variants? |
| Test Case Quality | 15% | Assertion completeness, readability, meaningful data? |
| Isolation & Flakiness | 15% | Real DB? Only external APIs mocked? No flaky patterns? |
| Anti-Patterns | 10% | Implementation testing, over-mocking, assert-free tests? |

**Verdicts:** STRONG (8-10) / ADEQUATE (6-7.9) / NEEDS IMPROVEMENT (4-5.9) / WEAK (0-3.9)

## Supported Frameworks

- **RSpec** (Ruby) -- describe/context/it, let/subject, shared_examples
- **Go testing** -- table-driven tests, subtests, testify
- **Jest/Vitest** (JS/TS) -- describe/it/expect, mocking
- **pytest** (Python) -- fixtures, marks, parametrize
- **Framework-agnostic** -- general contract-based testing principles

## Plugin Structure

```
tdd-contract-review/
+-- .claude-plugin/
|   +-- plugin.json
+-- agents/
|   +-- staff-engineer.md         # dispatched at every step
+-- skills/
|   +-- tdd-contract-review/
|       +-- SKILL.md                         # orchestrator workflow
|       +-- contract-extraction.md
|       +-- test-patterns.md
|       +-- money-correctness-checklists.md  # critical mode: money lifecycle
|       +-- api-security-checklists.md       # critical mode: auth / trust / audit
|       +-- report-template.md
+-- benchmark/
|   +-- sample-app/               # ground-truth Rails app
|   +-- expected_gaps.yaml        # expected findings per unit
|   +-- grade-content.sh          # Category A: per-unit content grader
|   +-- grade-shape.sh            # Category B: per-unit shape invariants
|   +-- run-matrix.sh             # wraps both across every declared unit
+-- README.md
+-- LICENSE
```

## License

MIT
