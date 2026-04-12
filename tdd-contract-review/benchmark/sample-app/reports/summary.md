## TDD Contract Review — Summary

**Scope:** PR-scoped (branch `bittersweet-feta` vs `main`)
**Fintech mode:** Enabled (money/amount/balance fields, payment gateway, transaction state machine, wallet operations)
**Framework:** Rails 7.1 / RSpec

| Test File | Endpoint(s) | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|
| spec/requests/api/v1/transactions_spec.rb | POST + GET /:id + GET /api/v1/transactions | 2.9/10 | WEAK | 23 | 8 |
| spec/requests/api/v1/wallets_spec.rb | POST + GET /api/v1/wallets | 3.8/10 | WEAK | 14 | 7 |

### Missing test files (source exists but no test file)

- **PATCH /api/v1/wallets/:id** — no test file exists. Full endpoint contract untested: update name, currency, status, not found, IDOR, validation errors.

### Non-boundary test files (flag as anti-pattern)

- **spec/models/wallet_spec.rb** — model spec testing `deposit!`/`withdraw!` directly. Recommend testing through API endpoints instead. If these methods are called by other teams/services, they qualify as contract boundaries — otherwise delete and test via the endpoint.
- **spec/services/transaction_service_spec.rb** — service spec with implementation-detail testing (`expect(service).to receive(:build_transaction)`). Delete this file and test TransactionService behavior through `POST /api/v1/transactions` instead.

### Structural Anti-Patterns

| Anti-Pattern | Files Affected | Recommendation |
|---|---|---|
| Multiple endpoints in one file | `transactions_spec.rb`, `wallets_spec.rb` | Split into one endpoint per file (6 files total) |
| No test foundation pattern | Both test files | Add `subject(:run_test)`, DEFAULT constants, and single-override-per-test structure |
| Implementation testing | `transaction_service_spec.rb` | Delete — verify behavior through API endpoint tests |
| Status-only assertions | `transactions_spec.rb` (all error tests) | Add response body, DB state, and side-effect assertions |

### Fintech-Specific Findings

| Finding | Severity | Details |
|---|---|---|
| No idempotency key on POST /transactions | HIGH | Financial mutation endpoint has no duplicate prevention |
| No rate limiting on any endpoint | MEDIUM | Financial endpoints vulnerable to brute-force/card testing |
| No audit trail | MEDIUM | Financial mutations not auditable |
| Status param permitted on wallet create | HIGH | User could create wallets in suspended/closed state |
| Transaction state machine untested | HIGH | 4 states (pending/completed/failed/reversed), 0 transition tests |
| Concurrent access untested | HIGH | `with_lock` on deposit!/withdraw! but no test verifies lock works |
| No DB transaction wrapping in TransactionService | HIGH | Race condition: wallet active check and transaction create are not atomic |
| `reversed` status has no transition path | MEDIUM | Enum value exists but no code transitions to it — dead state? |

### Overall: 2 files reviewed, 37 HIGH gaps, 15 MEDIUM gaps

### Top 5 Priority Actions (across all files)

1. **Add response body + DB assertions to POST /transactions happy path** — the most impactful single test improvement. Currently only checks status 201; all 9 response fields and DB state are unprotected.
2. **Create test file for PATCH /wallets/:id** — entire endpoint has zero coverage. Any regression in update/not-found/authorization goes undetected.
3. **Add PaymentGateway integration tests** (success/failure/ChargeError) — the payment path is the most critical business flow and has zero test coverage.
4. **Add wallet-active and currency-mismatch tests for POST /transactions** — core business rules enforced by TransactionService with zero coverage.
5. **Add IDOR + auth tests across all endpoints** — security-critical gaps: no test verifies that users cannot access other users' resources, and no test verifies authentication is required.
