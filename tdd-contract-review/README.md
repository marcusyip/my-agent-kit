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
/tdd-contract-review "POST /api/v1/transactions" fintech
/tdd-contract-review "POST /api/v1/transactions" no-fintech
```

**Arguments:**
- **unit identifier** (required): `VERB /path`, a class name, or a source file path
- **`quick`** (optional): abbreviated report, HIGH gaps only
- **`fintech`** / **`no-fintech`** (optional): force fintech mode on or off. Fintech mode is auto-detected from money/balance/currency fields, payment gateways, and decimal types.

## What It Does

The skill dispatches a Staff Engineer agent at each step and pauses for user review at three checkpoints:

1. **Discovery + Unit Guard** -- resolves the unit to exactly one source file, fails fast on 0 or >1 matches
2. **Contract Extraction** -- extracts API inbound, DB, Outbound API, Jobs, UI Props contracts with typed field prefixes; writes `01-extraction.md` -> **Checkpoint 1**
3. **Test Audit** -- audits test structure, quality, anti-patterns against the extracted contract; writes `02-audit.md` -> **Checkpoint 2**
4. **Gap Analysis** -- parallel per-type agents (API, DB, Outbound, Fintech) each enumerate every scenario per field; a merge agent produces `03-gaps.md` -> **Checkpoint 3**
5. **Report + findings.json** -- scored `report.md` with test stubs + machine-readable `findings.json` for CI

Every run writes to a flat, unit-scoped directory: `tdd-contract-review/{YYYYMMDD-HHMM}-{unit-slug}/`.

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
|       +-- SKILL.md              # orchestrator workflow
|       +-- contract-extraction.md
|       +-- test-patterns.md
|       +-- fintech-checklists.md
|       +-- report-template.md
+-- benchmark/
|   +-- sample-app/               # ground-truth Rails app
|   +-- eval.sh                   # substring-match grader
|   +-- expected_gaps.yaml        # expected findings per unit
+-- README.md
+-- LICENSE
```

## License

MIT
