---
name: tdd-contract-review
description: Contract-based test quality review. Extracts contracts from source code, maps test coverage per field, identifies gaps, produces a scored report with prioritized actions, and auto-generates test stubs for high-priority gaps.
argument-hint: "[path, file, or 'quick' for abbreviated output -- defaults to PR scope or project root]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.25.0
---

# TDD Contract Review

Contract-based test quality review. Dispatches a Principal QA Engineer agent for each step with focused context.

## Review Workflow

### Step 1: Determine Scope

Resolve `$ARGUMENTS` to find test and source files.

**Parsing rules:** split `$ARGUMENTS` on whitespace. If the first token is `quick`, enable quick mode. Otherwise all tokens are scope.

- **`quick` keyword**: Enable quick mode (abbreviated output).
- **Specific test file**: review that file, locate its source
- **Source file**: find corresponding test files
- **Directory**: find all test files in that tree
- **No argument + non-default branch**: PR-scoped mode. Use `git diff` against base branch to find changed source files, check ENTIRE test suite.
- **No argument + default branch**: review entire project test suite

### Step 2: Discovery

1. **Find test files.** Glob for `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}`, `**/*_test.go`, `**/*_spec.rb`, `**/*.test.py`, `**/test_*.py`
2. **Detect test framework.**
3. **Find source files — handlers/controllers.** Include jobs (`app/jobs/`, `app/workers/`) and message consumers.
4. **Find DB schema files — trace from handlers.** Do NOT rely on handler code alone. Find:
   - Migrations: `db/migrate/*.rb`, `database/migrations/*.sql`, `**/migrate/*.go`
   - Models: `app/models/*.rb`, `internal/model/*.go`, `src/models/*.ts`, `**/models.py`
   - ORM schemas: `prisma/schema.prisma`, `db/schema.rb`, `**/schema.sql`
   - Generated queries: SQLC, TypeORM, Drizzle
5. **Find outbound API client files — trace from handlers.** Find HTTP client code, not internal services.
6. **Check project conventions.** Read CLAUDE.md, config files.
7. **Detect fintech domain.** Money/balance/currency fields, payment gateways, decimal types → enable **fintech mode**.

**GATE:** Verify three categories of source files found (handlers, DB schema, outbound clients). Do NOT proceed with only handlers.

### Step 3: Contract Extraction

Determine the skill directory path and the plugin root path (parent of `skills/`). Dispatch the Principal QA Engineer agent:

```
Agent:       tdd-contract-review:principal-qa-engineer
Model:       sonnet
Description: Contract extraction
Prompt:
  "TASK: Extract contracts from source files.
   Skill directory: [path]
   Read `contract-extraction.md` at [skill dir]/contract-extraction.md for extraction guidance and format example.
   If fintech mode: also read `fintech-checklists.md` at [skill dir]/fintech-checklists.md.

   Source files by category:
   - Handlers: [list]
   - DB schema: [list]
   - Outbound clients: [list]

   Fintech mode: [yes/no]

   Produce: Contract Extraction Summary (typed prefixes per field) + Checkpoint 1 table + fintech dimensions (if applicable)."
```

**GATE:** Verify Checkpoint 1 table has all 5 rows. If any "Extracted" row shows 0 fields, re-dispatch. Save output as `$EXTRACTION`.

### Step 4-5: Test Audit

```
Agent:       tdd-contract-review:principal-qa-engineer
Model:       sonnet
Description: Test structure audit
Prompt:
  "TASK: Audit test files against the contract extraction.
   Skill directory: [path]
   Read `test-patterns.md` at [skill dir]/test-patterns.md for sessions pattern, anti-patterns, quality checklists.

   Test files: [list]
   Extraction: $EXTRACTION

   Produce: test structure findings, quality issues, anti-patterns (with file:line), per-field coverage notes."
```

Save output as `$AUDIT`.

### Step 6: Gap Analysis

```
Agent:       tdd-contract-review:principal-qa-engineer
Model:       opus
Description: Gap analysis
Prompt:
  "TASK: Analyze gaps between contracts and test coverage.
   Skill directory: [path]
   If fintech mode: read `fintech-checklists.md` at [skill dir]/fintech-checklists.md for gap scenario checklists.

   Extraction: $EXTRACTION
   Audit: $AUDIT
   Fintech mode: [yes/no]

   Produce: Test Structure Tree (grouped by field) + Contract Map (one row per field) + gap analysis by priority + test stubs for HIGH gaps + Checkpoint 2 table."
```

**GATE:** Verify Checkpoint 2 table. Every "Extracted" type must show "Yes". Save output as `$GAPS`.

### Step 7-8: Report Writing

```
Agent:       tdd-contract-review:principal-qa-engineer
Model:       sonnet
Description: Report writing
Prompt:
  "TASK: Write report files to disk.
   Skill directory: [path]
   Read `report-template.md` at [skill dir]/report-template.md for template, scoring, and format.

   Extraction: $EXTRACTION
   Audit: $AUDIT
   Gaps: $GAPS
   Quick mode: [yes/no]

   Write reports to `tdd-contract-review/{datetime}-report/`. Get time via `date +%Y%m%d-%H%M`.
   Verify files exist after writing."
```

**GATE:** Verify report files written. List the directory.

### Step 9: Report Review

```
Agent:       tdd-contract-review:principal-qa-engineer
Model:       opus
Description: Report quality review
Prompt:
  "TASK: Review report quality against your Quality Checklist.
   Report directory: [path]
   Extraction (for cross-reference): $EXTRACTION

   Read every report file. Check each item in your Quality Checklist.
   Output: 'QUALITY: PASS' or 'QUALITY: FAIL' with list of failures and which step should fix each."
```

**If PASS:** print summary.
**If FAIL:** re-dispatch the agent for the responsible step with the specific fix. Max 1 round. Then print summary.

## Review Principles

1. **Read the source, not just tests.**
2. **Be specific.** Every finding references `file:line`.
3. **Prioritize by breakage risk.**
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7.
6. **Do not run tests.** Static analysis only.
