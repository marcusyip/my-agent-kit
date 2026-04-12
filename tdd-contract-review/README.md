# tdd-contract-review

A Claude Code plugin that reviews test quality through **contract-based analysis** and auto-generates test stubs for gaps.

Extract contracts from source code (API request/response fields, DB model fields, outbound API call params, UI component props), map test coverage per field, identify gaps, and generate test stubs for missing coverage.

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
/tdd-contract-review                              # PR-scoped (on branch) or entire project
/tdd-contract-review src/auth/                    # Review tests for auth module
/tdd-contract-review src/services/payment.ts      # Review tests for a source file
/tdd-contract-review spec/models/user_spec.rb     # Review a specific test file
/tdd-contract-review internal/handler/order.go    # Review tests for a Go handler
/tdd-contract-review quick                        # Quick mode: score + HIGH gaps only
/tdd-contract-review quick src/auth/              # Quick mode for a specific directory
```

## What It Does

1. **Determines scope** -- resolves paths, detects PR-scoped mode on branches
2. **Discovers** test files and detects the test framework
3. **Extracts contracts** from source code with confidence indicators
4. **Audits test structure** for the sessions pattern (group by feature > field)
5. **Audits test case quality** for assertion completeness, readability, isolation
6. **Maps gaps** per contract field with edge cases and priority levels
7. **Auto-generates test stubs** for HIGH priority gaps following your project's patterns
8. **Scores and reports** across 6 categories with weighted overall score

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
+-- skills/
|   +-- tdd-contract-review/
|       +-- SKILL.md
|       +-- fintech-checklists.md
+-- benchmark/
|   +-- sample-app/
|   +-- reports-v*/
+-- README.md
+-- LICENSE
```

## License

MIT
