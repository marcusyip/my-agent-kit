## TDD Contract Review -- Summary

**Scope:** benchmark/sample-app/ (full project)
**Framework:** Rails / RSpec
**Date:** 2026-04-12

| Test File | Endpoint | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|
| spec/requests/api/v1/transactions_spec.rb | POST + GET/:id + GET /api/v1/transactions | 3.6/10 | WEAK | 9 | 6 |
| spec/requests/api/v1/wallets_spec.rb | POST + GET /api/v1/wallets | 4.6/10 | NEEDS IMPROVEMENT | 2 | 6 |

**Missing test files** (source exists but no test file):
- `PATCH /api/v1/wallets/:id` -- no test file exists (controller at app/controllers/api/v1/wallets_controller.rb:30)
- `GET /api/v1/transactions/:id` -- tested in combined file, should have its own file
- `GET /api/v1/transactions` -- tested in combined file, should have its own file
- `GET /api/v1/wallets` -- tested in combined file, should have its own file

**Non-boundary test files (anti-patterns):**
- Delete `spec/services/transaction_service_spec.rb` -- tests internal service with implementation testing (verifies `build_transaction`, `validate_wallet_active!`, `validate_currency_match!` are called). Move behavioral coverage to `POST /api/v1/transactions` endpoint spec instead.
- Delete `spec/models/wallet_spec.rb` -- tests `Wallet#deposit!` and `Wallet#withdraw!` which are internal model methods. Test these behaviors through the API endpoints that invoke them.

**Structural issues:**
- `transactions_spec.rb` combines 3 endpoints in one file (should be 3 separate files)
- `wallets_spec.rb` combines 2 endpoints in one file (should be 2 separate files, plus a 3rd for PATCH)
- `transaction_service_spec.rb` tests an internal service with `expect(service).to receive(:build_transaction)` -- this is implementation testing, not contract testing

**Overall: 2 boundary test files reviewed, 11 HIGH gaps, 12 MEDIUM gaps**

### Top 5 Cross-Project Priority Actions

1. **Add response body and DB assertions to POST /api/v1/transactions happy path** -- the most critical endpoint's happy path only checks status 201, leaving all 9 response fields and DB state completely unverified. Highest breakage risk.

2. **Create test file for PATCH /api/v1/wallets/:id** -- entire endpoint has zero coverage. Any change to update logic, validation, or authorization can break silently.

3. **Add PaymentGateway.charge scenarios to POST /api/v1/transactions** -- the payment flow triggers an external API that can change transaction status (pending -> completed/failed). Zero test coverage on this critical integration.

4. **Add description and category field tests to POST /api/v1/transactions** -- two request params with validations (max 500 chars, enum with 4 values, default value) have zero test coverage.

5. **Add wallet business rule tests** (suspended/closed wallet, currency mismatch, another user's wallet) -- four business rules enforced in TransactionService and the controller's `set_wallet` filter have zero test coverage through the API.

### File Organization Recommendation

Current structure (anti-pattern):
```
spec/
├── requests/api/v1/
│   ├── transactions_spec.rb     # 3 endpoints combined
│   └── wallets_spec.rb          # 2 endpoints combined (missing PATCH)
├── models/
│   └── wallet_spec.rb           # internal model tests (delete)
└── services/
    └── transaction_service_spec.rb  # implementation testing (delete)
```

Recommended structure:
```
spec/
└── requests/api/v1/
    ├── post_transactions_spec.rb    # POST /api/v1/transactions
    ├── get_transaction_spec.rb      # GET /api/v1/transactions/:id
    ├── get_transactions_spec.rb     # GET /api/v1/transactions
    ├── post_wallets_spec.rb         # POST /api/v1/wallets
    ├── get_wallets_spec.rb          # GET /api/v1/wallets
    └── patch_wallet_spec.rb         # PATCH /api/v1/wallets/:id
```
