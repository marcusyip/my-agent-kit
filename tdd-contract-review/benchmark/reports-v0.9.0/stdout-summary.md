## TDD Contract Review — Summary

**Scope:** PR-scoped (branch `bittersweet-feta` vs `main`)
**Fintech mode:** Enabled (money/amount/balance fields, payment gateway, transaction state machine, wallet balance with pessimistic locking)

| Test File | Endpoint(s) | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|
| `spec/requests/api/v1/transactions_spec.rb` | POST + GET/:id + GET /transactions | **3.6/10** | WEAK | 18 | 7 |
| `spec/requests/api/v1/wallets_spec.rb` | POST + GET /wallets | **4.75/10** | NEEDS IMPROVEMENT | 10 | 5 |

### Missing Test Files

- **PATCH /api/v1/wallets/:id** — entire endpoint untested (status transitions, name updates, not-found, IDOR)

### Non-Boundary Test Files (anti-patterns — delete these)

- **`spec/models/wallet_spec.rb`** — Tests `deposit!`/`withdraw!` directly. Test through the transaction endpoint instead.
- **`spec/services/transaction_service_spec.rb`** — Implementation testing (`expect(service).to receive(:build_transaction)`). Tests verify method calls, not behavior. Delete and test through `POST /api/v1/transactions`.

### Key Findings

The existing reports in `reports/` are comprehensive and accurate. My fresh analysis confirms:

**Structural issues:**
- Both test files contain multiple endpoints (should be 1 per file)
- No test foundation pattern (no `subject(:run_test)`, no DEFAULT constants)
- Status-only assertions throughout (~10 test cases check only HTTP status)

**Critical fintech gaps:**
1. **PaymentGateway integration: zero coverage** — success/failure/ChargeError paths completely untested
2. **IDOR on all endpoints** — other user's wallet/transaction not tested anywhere
3. **No authentication tests** — every controller uses `authenticate_user!` but no test sends unauthenticated request
4. **Currency mismatch untested** — validation exists in `TransactionService` but no test covers it
5. **Wallet status transitions untested** — PATCH endpoint doesn't exist as a test file
6. **No idempotency key** — duplicate POSTs create duplicate transactions (design gap)
7. **Concurrency: no TOCTOU or double-submit tests** — simultaneous requests could create race conditions

**Overall: 2 boundary files reviewed, 2 non-boundary files flagged, 28 HIGH gaps, 12 MEDIUM gaps**

### Top 5 Priority Actions

1. **Create `spec/requests/api/v1/patch_wallet_spec.rb`** — entire endpoint with zero coverage including fintech-critical status transitions
2. **Add response body + DB assertions to POST /transactions happy path** — the most-used endpoint has zero response/DB verification
3. **Add PaymentGateway scenarios** — payment processing is the core fintech feature, completely untested at API boundary
4. **Add IDOR + auth tests across all endpoints** — other user's wallet on POST, other user's transaction on GET/:id, unauthenticated requests
5. **Delete `transaction_service_spec.rb`** and test through the API — implementation testing gives false confidence

The full per-file reports with test structure trees, contract maps, and auto-generated test stubs are in `reports/transactions-spec.md` and `reports/wallets-spec.md`.
