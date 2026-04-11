# Benchmark Results — tdd-contract-review

**Date:** 2026-04-11
**Sample app:** Rails 7.1 API (transactions, wallets, users) with 3 test files and 13 known gaps

## Version Comparison

| Metric | Baseline (no skill) | v0.1.0 | v0.2.0 | v0.3.0 |
|---|---|---|---|---|
| Duration | 88s | 168s | 171s | 125s |
| Cost | $0.39 | $0.58 | $0.60 | $0.43 |
| Output tokens | 3,301 | 10,907 | 11,723 | 8,069 |
| Gaps found | 12/13 | 12/13 | 13/13 | 13/13 |
| `reversed` enum found | No | No | Yes | Yes |
| Test Structure Tree | No | No | No | Yes |
| Scoring anchors | No | No | Yes | Yes |

## Gap Detection (13 known gaps)

| # | Known Gap | Priority | Baseline | v0.1.0 | v0.2.0 | v0.3.0 |
|---|-----------|----------|:---:|:---:|:---:|:---:|
| 1 | Happy path assertions incomplete | HIGH | Found | Found | Found | Found |
| 2 | No PaymentGateway external API scenarios | HIGH | Found | Found + stubs | Found + stubs | Found + stubs |
| 3 | No PATCH /wallets/:id tests | HIGH | Found | Found + stubs | Found + stubs | Found + stubs |
| 4 | No wallet-belongs-to-another-user test | HIGH | Found | Found + stubs | Found + stubs | Found + stubs |
| 5 | No suspended/closed wallet scenarios | HIGH | Found | Found + stubs | Found + stubs | Found + stubs |
| 6 | No currency mismatch test | MEDIUM | Found | Found + stubs | Found + stubs | Found + stubs |
| 7 | Missing description/category fields | MEDIUM | Found | Found + stubs | Found + stubs | Found + stubs |
| 8 | No pagination/ordering tests | MEDIUM | Found | Found | Found | Found |
| 9 | No txn-belongs-to-another-user (show) | MEDIUM | Found | Found | Found | Found |
| 10 | Missing boundary cases (exact balance, amount=0) | MEDIUM | Found | Found | Found | Found |
| 11 | Missing duplicate currency test | MEDIUM | Found | Found | Found | Found |
| 12 | Missing name-too-long test | LOW | Found | Found | Found | Found |
| 13 | Missing reversed status scenario | LOW | Not found | Not found | Found | Found |

## Changes Per Version

### v0.1.0 → v0.2.0
- Added `$ARGUMENTS` parsing rules (split on whitespace, `quick` is first token)
- Added enum exhaustion check in Step 3 (fixes gap #13)
- Added scoring calibration anchors (what a 2, 5, 7, 9 look like)

### v0.2.0 → v0.3.0
- Added Test Structure Tree to report template (visual `✓`/`✗` map of coverage)
- Performance improved: 125s vs 171s, $0.43 vs $0.60

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
