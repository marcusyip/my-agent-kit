# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.34.1] - 2026-04-18

### tdd-contract-review

#### Fixed
- **Step 7-8 report agent was silently dropping MEDIUM and LOW gaps from `findings.json`.** The schema example showed only `"HIGH|MEDIUM|LOW"` and the instruction text said "include ONLY contract gaps and critical-mode gaps" — the agent reasonably read this as "HIGH is the floor" and emitted 0 MEDIUM, 0 LOW. Schema now lists all four priorities (`CRITICAL|HIGH|MEDIUM|LOW`) and the instruction explicitly says "include EVERY gap ... all four priorities. Do NOT drop MEDIUM or LOW." Benchmark score on `post-api-v1-transactions` rose from 16/24 → 19/24 with no other changes.
- **Step 9 check 2 only validated HIGH gaps had stubs, missing CRITICAL.** The SKILL spec has always said "stub: REQUIRED for CRITICAL and HIGH" but the jq filter was `priority == "HIGH"`. Now `(.priority == "CRITICAL" or .priority == "HIGH")`. Label renamed to `CRITICAL+HIGH gaps have stubs`.

## [0.34.0] - 2026-04-17

### tdd-contract-review

#### Added
- **Step 2.5 Previous Extraction Check** — if a previous run's `01-extraction.md` exists for the same unit-slug, the orchestrator offers a two-option AskUserQuestion (`Reuse` / `Extract fresh`) before dispatching the Step 3 extraction agent. Reuse copies the prior file into the current `$RUN_DIR`, runs the Checkpoint 1 shape GATE against the copy, and jumps straight to the Checkpoint 1 PAUSE. Extract fresh runs Step 3 normally. Saves the full extraction-agent cost when iterating on the same unit with unchanged source.
- **Previous-extraction lookup in Step 2 discovery** — glob `tdd-contract-review/*-{unit-slug}/01-extraction.md`, exclude the current `$RUN_DIR`, pick the most recent by `YYYYMMDD-HHMM` directory prefix. Result stored as `$PREV_EXTRACTION` (empty if none).
- **`Previous extraction:` line in the Run Preview** — shows `<path> (<timestamp>)` if one was found, or `none found (skip reuse ask)` otherwise. User sees the reuse opportunity before the first agent dispatches.
- **Critical-mode mismatch warning** — if the prior extraction's `Critical mode:` value differs from the current run's, Step 2.5 prepends a one-line warning above the two options recommending Extract fresh.
- **GATE-fail fallback** — if the reused file fails the Checkpoint 1 shape GATE (malformed or from an older skill version), the orchestrator prints the failure and falls through to a fresh Step 3 dispatch. No hard stop.

#### Notes
- Revise at Checkpoint 1 works identically on a reused file — the Step 3 DEEPEN REQUEST block overwrites `$RUN_DIR/01-extraction.md` regardless of how it arrived.
- Out of scope for v0.34.0: audit (`02-audit.md`) reuse, gaps (`03-gaps.md`) reuse, a CLI `no-reuse` skip flag, and mtime-based staleness detection. Revisit audit reuse if real usage shows audit cost dominating after this lands.

## [0.33.0] - 2026-04-17

### tdd-contract-review

#### Added
- **READ PROTOCOL in the audit agent prompt.** Three non-negotiable steps before writing `02-audit.md`: (1) grep each test file with the framework's test-function pattern to get a ground-truth count and line numbers, (2) read every test file to EOF with chunked `Read(offset=0/500/1000/...)` calls until returned lines < 500, (3) pre-write verification that Test Inventory count equals grep count per file. Closes the silent-under-reading failure mode that burned ~353K tokens across 3 revision runs pre-v0.33.0.
- **Per-framework grep pattern table** inlined in the audit prompt: Go testing, RSpec, Jest/Vitest, pytest, Minitest.
- **5-section audit output spec** (explicit and ordered): `## Test Inventory`, `## Scenario Inventory`, `## Per-Field Coverage Matrix`, `## Assertion Depth`, `## Anti-Patterns`. Replaces the previous vague "produce test structure findings, quality issues, anti-patterns (with file:line), per-field coverage notes" one-liner.
- **Grep-reconciliation bullets in `## Summary`**: `Test files (grep count): <N> files, <M> functions` + `Test Inventory (agent count): <M> functions ← MUST match`. The Checkpoint 2 Summary echo now surfaces any count mismatch directly in the terminal — user can spot incompleteness without opening the file.

#### Changed
- **Checkpoint 2 DEEPEN REQUEST block** now leads with reconciliation: verify grep-count vs agent-count first, re-run chunked reads on any short file, then proceed to the exhaustive-examination steps. Misreads get caught first, not after another full pass.
- **Audit output explicitly excludes `## Gaps` and `## Scorecard`.** Gaps are Step 6's job; scoring is Step 7-8's job. The audit is an input to both, not a partial duplicate.

#### Notes
- Audit agent stays on `Model: sonnet`. The forcing functions (read protocol + 5-section spec + reconciliation) should land the audit on first run without a model upgrade. If sonnet with the hardened prompt still burns revision cycles, revisit upgrading to opus in a future version.

## [0.32.0] - 2026-04-17

### tdd-contract-review

#### Added
- **`## Summary` sections** in three agent outputs — extraction (`01-extraction.md`), audit (`02-audit.md`), merge (`03-gaps.md`). Each is a scannable 4-8 bullet one-screen overview placed as the first section of the file. Extraction summary: total fields, Checkpoint 1 matrix one-liner, critical-mode status + triggering signal, files-examined counts. Audit summary: test framework, file + case counts, anti-pattern count, per-contract-type coverage. Merge summary: gaps by priority, gaps per contract type, stubs generated, hygiene count.
- **Summary echo before each checkpoint** — the orchestrator prints the written file's Summary section to the terminal before asking Continue/Revise/Stop, so the user has something to review without opening the file.
- **Per-type DEEPEN REQUEST + Merge DEEPEN REQUEST blocks** at Checkpoint 3 — Revise re-dispatches all Extracted per-type agents (plus critical-mode agents if applicable) in parallel before re-running the merge agent. Matches the intent of "make the report more complete" instead of just re-merging existing sub-files.

#### Changed
- **Per-type gap agents (API / DB / Outbound) downgraded from opus → sonnet.** The F1 money-correctness, F2 API-security, and Step 6c merge agents stay on opus. Per-type analysis is narrow-context scenario enumeration against a matrix — sonnet handles this well and cuts ~60% of gap-analysis cost per run.
- **Revise is now an auto-iterate deepen pass** — no follow-up "what should be revised?" prompt. Selecting Revise re-dispatches the same agent with a step-specific DEEPEN REQUEST block appended (re-examine source exhaustively, re-verify cited tests, re-calibrate priorities). The description in the Checkpoint option list changed from `Re-run this step with your feedback.` to `Re-run this step with a deepen pass (no input needed).`
- **Specific-feedback path preserved** via the existing free-text fallback. Typing free text at the checkpoint (instead of picking Continue/Revise/Stop) still routes through the REVISION REQUEST block with the user's verbatim text — unchanged from v0.31.0.
- **Revision cap (3 per checkpoint)** now counts any mix of deepen Revise and specific-feedback free-text paths.
- **Checkpoint Interaction Pattern section rewritten** as a three-step shape (Step A — Echo Summary, Step B — Ask, Step C — Branch) so all three checkpoints share one spec.

## [0.31.0] - 2026-04-17

### tdd-contract-review

#### Added
- `scenario-checklist.md` reference file — the per-field input/assertion scenario matrix previously inlined into every per-type gap prompt is now a single reference loaded by the per-type agents. One place to edit; smaller prompts.
- **Run preview** printed at end of Step 2 (before Step 3 dispatches): unit, resolved source, schema/outbound counts, critical-mode status with the signal that triggered it, pipeline shape, and run dir. Makes auto-detected critical mode visible and gives users a cancellation window before any agent spends tokens.
- **Progress breadcrumbs** in Step 6b: print the list of parallel gap agents before dispatch and one `✓ <sub-file> (<N> gaps)` line per agent after all return. No more silent multi-minute gaps.
- Not-found error (Step 2 GATE) now shows the globs actually searched and up to 3 fuzzy candidate matches, symmetrical with the ambiguous-match path.
- Missing-unit error (Step 1) now prints the full argument hint with unit-form examples and flag descriptions.

#### Changed
- Renumbered cross-cutting gap sub-files: `03f-gaps-money.md` → `03d-gaps-money.md`, `03g-gaps-security.md` → `03e-gaps-security.md`. Output layout is now sequential `03a/03b/03c/03d/03e`.

## [0.30.0] - 2026-04-17

### tdd-contract-review

#### Changed
- Review checkpoints now use the `AskUserQuestion` harness instead of "Reply continue" text prompts. Each of the 3 checkpoints (after extraction, audit, and gap analysis) renders three explicit options: **Continue**, **Revise**, **Stop**.
- Added a shared **Checkpoint Interaction Pattern** section in SKILL.md so all three checkpoints share one spec.

#### Added
- **Revise** option: re-dispatches the same step's agent with user feedback appended as a REVISION REQUEST block, overwrites the intermediate file, re-runs the step's GATE check, and returns to the same checkpoint.
- Revision cap: 3 revisions per checkpoint before the option is dropped, to prevent unbounded loops.
- Natural-language fallback: if the user types free text instead of selecting (via the auto-added "Other" input), affirmative words proceed, stop-intent words exit, and any other text is treated as revise feedback directly.

## [0.14.0] - 2026-04-12

### tdd-contract-review

#### Added
- Balance and position validation scenarios for amount fields in gap analysis
- Position & Inventory extraction guidance and gap checklist in fintech-checklists.md
- Common Field Type Scenarios section (pagination, date/time, array, formatted string, file upload)
- Cross-dimension rule: amount fields show balance/position constraints in test tree
- Stronger error response data leak check in security gap analysis

#### Changed
- Cross-reference notes between amount-level and balance/ledger-level checks to avoid double-flagging
- Updated test structure tree example to include balance/position scenarios

## [0.13.0] - 2026-04-12

### tdd-contract-review

#### Added
- Full fintech dimension coverage across all 8 categories
- Benchmark reports for v0.13.0 validating complete gap detection

#### Changed
- Expanded SKILL.md fintech analysis instructions for broader scenario coverage

## [0.12.0] - 2026-04-12

### tdd-contract-review

#### Added
- Contract Map now requires every extracted field to have a row (DB fields, outbound API params, not just API request/response)
- Contract Extraction Summary in reports must include all contract types found

#### Changed
- Stub headings use full gap descriptions instead of shorthand labels like "Stub H4"
- Summary enforced as strict rollup — every finding must appear in a per-file report first
- Removed agent definition; skill is the sole entry point (fixes "Agent type not found" on fresh installs)

#### Fixed
- DB table fields and outbound API contracts now consistently appear in Contract Map
- Summary no longer contains findings absent from per-file reports

## [0.11.0] - 2026-04-12

### tdd-contract-review

#### Added
- Absence flagging: explicitly flags missing rate limiting, audit trail, and idempotency as infrastructure gaps
- Inline top 2-3 scenarios per fintech category (concurrency, security) to ensure gap generation
- Missing Infrastructure section in reports for absence-based findings

#### Changed
- Replaced `[FINTECH]` tags with natural prefixes (`security:`, `concurrency:`, `business:`)

#### Fixed
- Fintech gap detection now 18/18 (up from 14/18) — closed concurrency and infrastructure gaps

## [0.10.0] - 2026-04-12

### tdd-contract-review

#### Added
- Contract extraction completeness gate (minimum 10 fields before proceeding)
- Report file write gate (must write files before printing summary)
- Mass assignment risk detection (bonus finding: `wallet_params` permits `:status`)

#### Changed
- Extracted detailed fintech checklists to `fintech-checklists.md` reference file (SKILL.md: 933 -> 768 lines)

#### Fixed
- Recovered all 13/13 known gap detection (regressed to 7/13 in v0.9.0)
- Restored money/precision and state machine fintech findings
- Report file writing restored (regressed in v0.9.0)

## [0.9.0] - 2026-04-12

### tdd-contract-review

#### Added
- Fintech domain auto-detection (money/balance fields, payment gateways, state machines)
- 8-dimension fintech contract extraction: Money/Precision, Idempotency, State Machine, Balance/Ledger, External Integrations, Regulatory, Concurrency, Security
- Concurrency gap analysis (TOCTOU, locking, deadlock, double-submit)
- Security gap analysis (auth, IDOR, amount tampering, rate limiting, data exposure)
- Idempotency design gap detection

## [0.6.0] - 2026-04-11

### tdd-contract-review

#### Added
- Benchmark suite with sample Rails 7.1 API app (transactions, wallets, users)
- `$ARGUMENTS` parsing with quick mode (`/tdd-contract-review quick`)
- Test structure tree output (visual coverage map with checkmarks)
- Scoring calibration anchors (what a 2, 5, 7, 9 look like)
- Enum exhaustion checking in contract extraction
- Auto-generated test stubs for HIGH priority gaps
