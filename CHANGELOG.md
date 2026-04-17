# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

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
