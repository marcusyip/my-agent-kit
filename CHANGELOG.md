# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

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
