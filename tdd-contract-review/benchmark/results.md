# Benchmark Results — tdd-contract-review

**Sample app:** Rails 7.1 API (transactions, wallets, users) with 3 test files and 13 known gaps

**Convention:** Each run writes to `reports-v{version}/`. Raw stdout goes to `stdout-summary.md`, per-file reports keep their original names.

| Folder | Date | Version |
|---|---|---|
| `reports-v0.7.0/` | 2026-04-11 | v0.7.0 (pre-fintech) |
| `reports-v0.9.0/` | 2026-04-12 | v0.9.0 (fintech/concurrency/security) |
| `reports-v0.10.0/` | 2026-04-12 | v0.10.0 (reference file + gates) |
| `reports-v0.11.0/` | 2026-04-12 | v0.11.0 (inline scenarios + absence flagging) |
| `reports-v0.12.0/` | 2026-04-12 | v0.12.0 (report quality: full contract map, readable stubs, strict summary) |
| `reports-v0.14.0/` | 2026-04-12 | v0.14.0 (balance/position validation, common field type scenarios) |

## Version Comparison

| Metric | Baseline (no skill) | v0.1.0 | v0.2.0 | v0.3.0 | v0.9.0 | v0.10.0 | v0.11.0 | v0.12.0 | v0.14.0 |
|---|---|---|---|---|---|---|---|---|---|
| Duration | 88s | 168s | 171s | 125s | 336s | 406s | 440s | ~450s | ~344s |
| Cost | $0.39 | $0.58 | $0.60 | $0.43 | ~$0.70 | ~$0.85 | ~$0.90 | ~$0.95 | ~$0.85 |
| Output tokens | 3,301 | 10,907 | 11,723 | 8,069 | ~2,000 (summary only) | ~46,000 (full reports) | ~55,000 | ~55,000 | ~64,000 |
| Known gaps found | 12/13 | 12/13 | 13/13 | 13/13 | 7/13 | 13/13 | 13/13 | 13/13 | **13/13** |
| Fintech gaps found | N/A | N/A | N/A | N/A | 8/18 | 14/18 | 18/18 | 18/18 | **17/18** |
| `reversed` enum found | No | No | Yes | Yes | No | Yes | Yes | Yes | **Yes** |
| Test Structure Tree | No | No | No | Yes | No (not written) | Yes | Yes | Yes | **Yes** |
| Report files written | No | Yes | Yes | Yes | No (regression) | Yes (3 files) | Yes (3 files) | Yes (3 files) | **Yes (3 files)** |
| Fintech mode detected | N/A | N/A | N/A | N/A | Yes | Yes | Yes | Yes | **Yes** |
| Scoring anchors | No | No | Yes | Yes | Summary scores only | Yes | Yes | Yes | **Yes** |
| Auto-generated stubs | No | Yes | Yes | Yes | No | Yes | Yes | Yes | **Yes** |
| Missing infra flagged | No | No | No | No | No | No | Yes | Yes | **Yes** |
| DB fields in contract map | No | No | No | No | No | Partial | Partial | Full | **Full** |
| Outbound API in contract map | No | No | No | No | No | Partial | Partial | Full | **Full** |
| Stub labels readable | N/A | N/A | N/A | N/A | N/A | No | No | Yes | **Yes** |
| Summary = strict rollup | N/A | N/A | N/A | N/A | N/A | No | No | Yes | **Yes** |
| Balance validation on amount | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | **No** |
| Common field type scenarios | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | **Partial** |

## Gap Detection (13 known gaps)

| # | Known Gap | Priority | Baseline | v0.3.0 | v0.9.0 | v0.10.0 | v0.11.0 | v0.12.0 | v0.14.0 |
|---|-----------|----------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | Happy path assertions incomplete | HIGH | Found | Found | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 2 | No PaymentGateway external API scenarios | HIGH | Found | Found + stubs | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 3 | No PATCH /wallets/:id tests | HIGH | Found | Found + stubs | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 4 | No wallet-belongs-to-another-user test | HIGH | Found | Found + stubs | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 5 | No suspended/closed wallet scenarios | HIGH | Found | Found + stubs | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 6 | No currency mismatch test | MEDIUM | Found | Found + stubs | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 7 | Missing description/category fields | MEDIUM | Found | Found + stubs | Not found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 8 | No pagination/ordering tests | MEDIUM | Found | Found | Not found | Found | Found | Found | **Found** |
| 9 | No txn-belongs-to-another-user (show) | MEDIUM | Found | Found | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 10 | Missing boundary cases (amount=0, max) | MEDIUM | Found | Found | Not found | Found | Found | Found + stubs | **Found + stubs** |
| 11 | Missing duplicate currency test | MEDIUM | Found | Found | Not found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| 12 | Missing name-too-long test | LOW | Found | Found | Not found | Found + stubs | Found + stubs | Found | **Found** |
| 13 | Missing reversed status scenario | LOW | Not found | Found | Not found | Found | Found | Found | **Found** |

## Fintech Gap Detection (18 expected findings — v0.9.0+)

| # | Category | Expected Finding | Priority | v0.9.0 | v0.10.0 | v0.11.0 | v0.12.0 | v0.14.0 |
|---|----------|-----------------|----------|:---:|:---:|:---:|:---:|:---:|
| F1 | Money/Precision | decimal(20,8) correct type noted | INFO | Not found | Found | Found | Found | **Found** |
| F2 | Money/Precision | No precision overflow test | HIGH | Not found | Found | Found | Found | **Found** |
| F3 | Money/Precision | No zero amount test | MEDIUM | Not found | Found | Found | Found | **Found** |
| F4 | Money/Precision | No max amount (1M) boundary test | MEDIUM | Not found | Found | Found | Found | **Found** |
| F5 | Money/Precision | No over-max (1M+1) test | MEDIUM | Not found | Found | Found | Found | **Found** |
| F6 | Idempotency | No idempotency key on POST | HIGH | Found | Found | Found | Found | **Found** |
| F7 | State Machine | Transaction transitions untested | HIGH | Partial | Found | Found | Found | **Found** |
| F8 | State Machine | No invalid transition test | HIGH | Not found | Found | Found | Found | **Found** |
| F9 | State Machine | Wallet states untested | HIGH | Found | Found | Found | Found | **Found** |
| F10 | Concurrency | TransactionService TOCTOU risk | HIGH | Found | Not found | Found | Found | **Found** |
| F11 | Concurrency | No concurrent debit test | HIGH | Found | Not found | Found | Found | **Found** |
| F12 | Concurrency | No double-submit prevention | MEDIUM | Found | Not found | Found | Found | **Found** |
| F13 | Security | No auth tests (missing token → 401) | HIGH | Found | Found | Found | Found | **Found** |
| F14 | Security | IDOR: other user's transaction | HIGH | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| F15 | Security | IDOR: other user's wallet | MEDIUM | Found | Found + stubs | Found + stubs | Found + stubs | **Found + stubs** |
| F16 | Security | No rate limiting | MEDIUM | Not found | Not found | Found | Found | **Found** |
| F17 | Security | Error response data leak risk | LOW | Not found | Found | Found | Found | **Not found** |
| F18 | Compliance | No audit trail fields | MEDIUM | Not found | Not found | Found | Found | **Found** |

**v0.9.0: 8/18** — strong on concurrency, missed money/precision.
**v0.10.0: 14/18** — recovered money/precision, lost concurrency.
**v0.11.0: 18/18** — all fintech criteria found. Inline scenarios + absence flagging closed the remaining gaps.
**v0.12.0: 18/18** — maintained. Report quality improvements: full DB/outbound contract map, readable stub labels, strict summary rollup.
**v0.14.0: 17/18** — minor regression: F17 (error response data leak) not flagged. New features (balance/position on amount, common field type scenarios) not yet picked up by the model.

## Changes Per Version

### v0.1.0 → v0.2.0
- Added `$ARGUMENTS` parsing rules (split on whitespace, `quick` is first token)
- Added enum exhaustion check in Step 3 (fixes gap #13)
- Added scoring calibration anchors (what a 2, 5, 7, 9 look like)

### v0.2.0 → v0.3.0
- Added Test Structure Tree to report template (visual `✓`/`✗` map of coverage)
- Performance improved: 125s vs 171s, $0.43 vs $0.60

### v0.3.0 → v0.9.0
- Added fintech domain detection (Money/Precision, Idempotency, State Machine, Balance/Ledger, Concurrency, Security)
- Added concurrency contract extraction and gap analysis (TOCTOU, locking, deadlock, double-submit)
- Added security contract extraction and gap analysis (auth, IDOR, amount tampering, rate limiting, data exposure)
- SKILL.md grew from ~727 lines to ~933 lines

### v0.9.0 → v0.10.0
- Extracted detailed fintech checklists to `fintech-checklists.md` reference file (SKILL.md: 933 → 768 lines)
- Added contract extraction completeness gate (10+ fields minimum before proceeding)
- Added report file write gate (must write files before printing summary)

### v0.10.0 → v0.11.0
- Added inline top 2-3 scenarios per fintech category in Step 6 (concurrency, security) to ensure gap generation
- Added "absence flagging" section: explicitly flag missing rate limiting, audit trail, idempotency as infrastructure gaps
- Removed `[FINTECH]` tag from instructions — tree uses natural prefixes (`security:`, `concurrency:`, `business:`)
- SKILL.md: 768 → 789 lines

### v0.11.0 → v0.12.0
- Removed agent definition — skill is the sole entry point (fixes "Agent type not found" on fresh installs)
- Added explicit instruction for readable stub labels — "never use shorthand labels like Stub H1, Stub H4"
- Enforced summary as strict rollup — every finding must appear in a per-file report first
- Strengthened Contract Extraction Summary and Contract Map to require all contract types (API, DB, outbound, jobs)
- Updated report gate to check for contract type completeness
- SKILL.md: 789 → ~800 lines

### v0.12.0 → v0.14.0
- Added balance/position validation scenarios to amount field gap checklists
- Added cross-reference notes to avoid double-flagging between amount-level and balance/ledger-level checks
- Added Position & Inventory extraction guidance and gap checklist to fintech-checklists.md
- Added Common Field Type Scenarios section (pagination, date/time, array, formatted string, file upload)
- Updated test structure tree example to include balance/position scenarios
- SKILL.md: ~800 → ~901 lines; fintech-checklists.md: 136 → 155 lines

## v0.14.0 Analysis

### What improved (vs v0.12.0)
- **Duration improved** to ~344s (down from ~450s) — possibly variance, but notable
- **All report quality metrics maintained** — report files written, full contract maps, readable stubs, strict summary rollup
- **Known gaps: 13/13** — maintained

### What regressed (vs v0.12.0)
- **Fintech gaps: 17/18** (down from 18/18) — F17 (error response data leak risk) not flagged. Neither report mentions testing that error responses don't leak sensitive data (balances, account numbers, stack traces). This was found in v0.12.0 but missed here.

### New features not picked up
- **Balance validation on amount field**: The amount field tree does NOT show "exceeds available balance → 422" despite the sample app's TransactionService checking balance before creating transactions. Balance scenarios appear only under the Balance & Ledger Integrity dimension, not inline with the amount field. The new guidance to add balance/position scenarios to the amount field's test tree was not applied.
- **Common field type scenarios**: Pagination fields are flagged as gaps generically ("missing pagination tests") but without the specific scenarios from the new checklist (zero page, negative page, very large limit, invalid cursor). Date/time fields (`created_at`, `updated_at`) are listed as response fields but not checked for format/timezone scenarios.
- **Position validation**: Not applicable — sample app has no position/inventory fields.

### Root cause hypothesis
The new sections add ~100 lines to SKILL.md (now 901 lines) and ~20 lines to fintech-checklists.md (now 155 lines). The model reads the fintech-checklists.md reference file for extraction guidance but the new "Common Field Type Scenarios" section in Step 6 may be competing with the fintech gap analysis for attention. The balance-on-amount guidance is in the sessions pattern example (line 270-272) and fintech-checklists.md but the model doesn't cross-apply it to the amount field tree — it treats balance as a separate dimension.

### Recommended fixes
1. **F17 regression**: Add "error response data leak" as an inline must-check in Step 6 security section (currently only in fintech-checklists.md). Same pattern that fixed F10-F12 in v0.11.0.
2. **Balance on amount**: Add explicit instruction in Step 6 gap analysis: "When an amount field's endpoint has a balance check in its code path, add 'exceeds balance' and 'equals balance' as amount-field scenarios in the tree, not just under Balance & Ledger." This makes the cross-dimension connection explicit.
3. **Common field types**: Consider moving the section earlier (before fintech) or making it a reference file to avoid attention dilution.

## Value-Add Analysis (skill vs baseline)

The skill does NOT find more gaps than baseline (both hit 12/13 on v0.1.0). Its value is in output quality:

- **Contract extraction summary** with confidence levels (baseline: none)
- **Contract map table** — field-by-field audit trail (baseline: none)
- **Test structure tree** — visual coverage map with ✓/✗ (baseline: none)
- **Weighted scoring rubric** — calibrated 0-10 with anchors (baseline: none)
- **Test stubs** — ready-to-paste code for all HIGH gaps (baseline: none)
- **Anti-pattern table** — file:line references (baseline: prose)
- **Sessions pattern audit** — checks test foundation (baseline: not checked)

v0.3.0 closes the performance gap: 125s / $0.43 vs baseline 88s / $0.39, while delivering significantly richer output.

## v0.9.0 Analysis

### What worked
- **Fintech mode detected correctly** — skill identified money/balance fields, payment gateway, state machines, pessimistic locking
- **Security/IDOR findings surfaced** — auth tests, IDOR on wallets and transactions, these are new findings not in any prior version
- **Concurrency findings surfaced** — TOCTOU risk, double-submit, race conditions correctly identified
- **Idempotency gap identified** — noted as a design gap, not just a test gap
- **Non-boundary spec flagging improved** — correctly recommended deleting service/model specs

### What regressed
- **Report files not written** (regression from v0.3.0) — skill referenced `reports/` directory but files don't exist. Only summary printed to stdout
- **Known gap detection dropped from 13/13 to 7/13** — all MEDIUM/LOW gaps missed (description/category, pagination, boundary cases, duplicate currency, name-too-long, reversed enum)
- **No test structure tree** (regression from v0.3.0)
- **No contract extraction summary** — Step 3 output not visible
- **No auto-generated test stubs** — Step 7 output not visible
- **Duration increased** from 125s to 336s — likely due to larger SKILL.md (933 lines vs ~600)

### Root cause hypothesis
The skill is now 933 lines. The added fintech/concurrency/security sections may be causing the model to prioritize high-level summary over the detailed 8-step workflow. The model appears to have:
1. Detected fintech mode and extracted high-level fintech findings (security, concurrency, idempotency)
2. Skipped the detailed per-field contract extraction that catches MEDIUM/LOW gaps
3. Skipped writing report files, producing only a summary

### Recommended fixes for v0.10.0
1. **Reduce SKILL.md size** — the fintech sections add ~200 lines of detailed checklists. Consider moving the per-field scenario checklists (Step 6 fintech) to a reference file loaded on demand, keeping only the extraction dimensions (Step 3) in SKILL.md
2. **Strengthen the Step 8 file-write instruction** — add an explicit gate: "You MUST write report files before printing the summary. If no files exist in reports/ after this step, you have not completed the review."
3. **Add a completeness check** — "Before producing output, verify: did you list every contract field from Step 3? If fewer than 10 contract fields were extracted, re-read the source files."

## v0.10.0 Analysis

### What improved (vs v0.9.0)
- **Known gaps: 13/13** (recovered from 7/13) — all MEDIUM/LOW gaps found again including description, category, pagination, boundaries, duplicate currency, name-too-long, reversed enum
- **Fintech gaps: 14/18** (up from 8/18) — money/precision fully recovered (F1-F5), state machine fully recovered (F7-F8), error data leak found (F17)
- **Report files written** — 3 files (transactions-spec.md, wallets-spec.md, summary.md). Gate worked
- **Test structure tree** — detailed per-scenario ✓/✗ tree restored
- **Contract extraction summary** — 45+ fields extracted for transactions, 30+ for wallets
- **Auto-generated test stubs** — ready-to-paste Ruby code for all HIGH gaps, following sessions pattern
- **New finding: mass assignment risk** — detected `wallet_params` permits `:status` allowing clients to create suspended wallets (not in known gaps list — bonus find)

### What regressed (vs v0.9.0)
- **Concurrency findings lost** (F10-F12) — TOCTOU, concurrent debit, double-submit not mentioned. The reference file approach moved these to `fintech-checklists.md` but the skill didn't read it for concurrency scenarios
- **Duration increased** to 406s (from 336s) — writing report files takes more time
- **Cost increased** to ~$0.85 — significantly more output tokens (~46k vs ~2k)

### What's still missing (both versions)
- F16: Rate limiting (not visible in source code — may be middleware/config)
- F18: Audit trail (not present in source — correct to not find it, but should flag absence)

### Net assessment
v0.10.0 is the best version overall. The reference file + gates approach recovered the detailed per-field analysis that v0.9.0 lost while retaining most fintech findings. The concurrency gap (F10-F12) suggests the skill reads `fintech-checklists.md` for extraction but doesn't consistently apply all gap analysis categories.

| | v0.3.0 | v0.9.0 | v0.10.0 | v0.11.0 | v0.12.0 | v0.14.0 |
|---|---|---|---|---|---|---|
| Known gaps | 13/13 | 7/13 | 13/13 | 13/13 | 13/13 | **13/13** |
| Fintech gaps | N/A | 8/18 | 14/18 | 18/18 | 18/18 | **17/18** |
| Report files | Yes | No | Yes | Yes | Yes | **Yes** |
| Test stubs | Yes | No | Yes | Yes | Yes | **Yes** |
| Missing infra | No | No | No | Yes | Yes | **Yes** |
| Full contract map | No | No | Partial | Partial | Yes | **Yes** |
| Readable stubs | N/A | N/A | No | No | Yes | **Yes** |
| Strict summary | N/A | N/A | No | No | Yes | **Yes** |
| Duration | 125s | 336s | 406s | 440s | ~450s | **~344s** |

## v0.11.0 Analysis

### What improved (vs v0.10.0)
- **Fintech gaps: 18/18** (up from 14/18) — perfect score. All 4 remaining gaps closed:
  - F10 (TOCTOU): "No locking on transaction creation" flagged in extraction + "no concurrency tests despite `with_lock` usage" in gap analysis
  - F11 (concurrent debit): "`with_lock` not verified" — gap entry for both deposit! and withdraw!
  - F12 (double-submit): "two rapid identical POSTs must not create duplicates" in tree
  - F16 (rate limiting): "No rate limiting detected" in Missing Infrastructure section
  - F18 (audit trail): "No audit trail table or fields detected" in Missing Infrastructure section
- **Missing Infrastructure section** — new dedicated section in reports for absence-based findings
- **Known gaps: 13/13** — maintained from v0.10.0
- **Bonus find maintained**: `wallet_params` permits `:status` (mass assignment risk on create)

### What stayed the same
- Report file writing: consistent since v0.10.0 gate
- Contract extraction depth: 45+ fields transactions, 30+ fields wallets
- Duration: ~440s (slightly up from 406s, within noise)

### Cosmetic note
The model still outputs `[FINTECH]` tags in some places despite removing the instruction. This is residual behavior from training/context — not actionable. The tree prefixes (`security:`, `concurrency:`, `business:`) appear alongside the tags.

## v0.12.0 Analysis

### What improved (vs v0.11.0)
- **Contract Map now includes all contract types** — DB fields (Transaction: 7 rows, Wallet: 6 rows) and outbound API fields (PaymentGateway.charge: 5 rows) all have dedicated rows in the Contract Map table. Previously these were partially or inconsistently included.
- **Stub labels are human-readable** — each stub uses the full gap description as its heading (e.g. "POST /api/v1/transactions happy path — no response body assertions") instead of shorthand like "Stub H4".
- **Summary is a strict rollup** — summary.md contains only scores, critical findings, and counts. No unique analysis or findings that don't appear in per-file reports.
- **Boundary cases got stubs** — amount=0, max boundary (1,000,000), over-max now have generated test code (previously just flagged as gaps without stubs).

### What stayed the same
- **Known gaps: 13/13** — maintained
- **Fintech gaps: 18/18** — maintained
- **Report file writing**: consistent (3 files)
- **Duration**: ~450s (within noise of v0.11.0's 440s)
- **`[FINTECH]` tags**: still appear in tree despite instruction removal (cosmetic, not actionable)

### Net assessment
v0.12.0 is a report quality release. Gap detection accuracy is unchanged from v0.11.0 (already at ceiling). The improvements are in report readability: readers can now understand stub headings without cross-referencing, the contract map is complete across all contract types, and the summary doesn't contain surprise findings.
