## TDD Contract Review — Summary

**Scope:** PR-scoped (branch `bittersweet-feta` vs `main`)
**Mode:** Fintech mode enabled (money/amount/balance fields, transaction/wallet models, payment gateway, decimal types)
**Framework:** Rails 7.1 / RSpec

### Scores

| Test File | Endpoint(s) | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|
| spec/requests/api/v1/transactions_spec.rb | POST + GET/:id + GET /transactions | 3.4/10 | WEAK | 18 | 6 |
| spec/requests/api/v1/wallets_spec.rb | POST + GET /wallets | 4.6/10 | NEEDS IMPROVEMENT | 12 | 6 |

### Missing Test Files (source exists but no test file)

- **PATCH /api/v1/wallets/:id** — endpoint exists in wallets_controller.rb but has zero test coverage. All fields (name, currency, status), not-found, IDOR, and validation scenarios are completely untested

### Non-Boundary Test Files (anti-patterns)

| File | Recommendation |
|---|---|
| spec/models/wallet_spec.rb | Delete — test `deposit!`/`withdraw!` behavior through POST /api/v1/transactions or a dedicated deposit endpoint instead |
| spec/services/transaction_service_spec.rb | Delete — tests implementation details (verifies internal method calls via `expect(service).to receive(:build_transaction)`). All behavior should be tested through POST /api/v1/transactions |

### Fintech-Specific Findings [FINTECH]

| Finding | Severity | Location |
|---|---|---|
| No idempotency key on POST /transactions | HIGH | transactions_controller.rb — mutating financial endpoint with no duplicate protection |
| No IDOR tests anywhere | HIGH | All endpoints — no test verifies user A cannot access user B's resources |
| No authentication tests | HIGH | All endpoints — no test for missing/expired/malformed auth token |
| PaymentGateway integration untested | HIGH | transaction_service.rb:57-69 — gateway success/failure/error all uncovered |
| Client can set wallet status on create | HIGH | wallets_controller.rb:44 — `wallet_params` permits `:status`, allowing creation of suspended/closed wallets |
| Transaction state machine untested | HIGH | transaction.rb:7 — 4 status values (pending/completed/failed/reversed) with no transition tests |
| Unique currency constraint untested | HIGH | wallet.rb:10 — UNIQUE(user_id, currency) could be removed without test failure |
| Balance operations tested only in model spec | MEDIUM | wallet_spec.rb — deposit!/withdraw! tested at model level, not through API boundary |

### Overall: 2 files reviewed, 30 HIGH gaps, 12 MEDIUM gaps

### Top 5 Priority Actions (across all files)

1. **Create `spec/requests/api/v1/patch_wallet_spec.rb`** — entire PATCH endpoint untested, including IDOR and status transitions
2. **Add response body + DB assertions to POST /transactions happy path** — 18 fields can break silently (currently only checks status 201)
3. **Add PaymentGateway external API test group** [FINTECH] — gateway success, failure, and ChargeError scenarios completely uncovered
4. **Add IDOR tests to all endpoints** [FINTECH] — no test verifies resource ownership anywhere in the suite
5. **Add wallet business rule tests** [FINTECH] — inactive wallet, currency mismatch, and duplicate currency constraint all untested
