## TDD Contract Review: spec/services/transaction_service_spec.rb

**Test file:** `spec/services/transaction_service_spec.rb`
**Source files:** `app/services/transaction_service.rb`
**Framework:** Rails 7.1 / RSpec

### Overall Score: 3.1 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 4/10 | 15% | 0.60 |
| Anti-Patterns | 1/10 | 10% | 0.10 |
| **Overall** | | | **3.10** |

### Verdict: WEAK

### Anti-Pattern: Service Layer Testing

This file tests `TransactionService` directly instead of through its API endpoint (`POST /api/v1/transactions`). The service is an internal implementation detail -- the contract boundary is the HTTP endpoint. These tests should be moved to `spec/requests/api/v1/post_transactions_spec.rb`.

**Exception rule:** This would be acceptable if `TransactionService` were a public API consumed by multiple callers. In this codebase, it is only called by `TransactionsController#create`, making it an internal implementation detail.

### Anti-Pattern: Implementation Testing

Three of the four "valid params" tests verify that internal methods are called (`build_transaction`, `validate_wallet_active!`, `validate_currency_match!`), not that the service produces correct output. These tests break when you refactor internals without changing behavior -- the opposite of contract testing.

```
transaction_service_spec.rb:12  expect(service).to receive(:build_transaction)
transaction_service_spec.rb:17  expect(service).to receive(:validate_wallet_active!)
transaction_service_spec.rb:22  expect(service).to receive(:validate_currency_match!)
transaction_service_spec.rb:49  expect(service).to receive(:charge_payment_gateway)
```

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/services/transaction_service.rb
Framework: Rails 7.1 / RSpec

TransactionService#call:
  Input: user, wallet, params (amount, currency, description, category)
  Success: Result(success?: true, transaction: <persisted>)
  Failures:
    - WalletInactiveError → Result(success?: false, error: 'Wallet is not active')
    - CurrencyMismatchError → Result(success?: false, error: 'Currency does not match wallet')
    - RecordInvalid → Result(success?: false, error: 'Validation failed', details: [...])
    - ChargeError → Result(success?: false, error: 'Payment processing failed', details: [...])
  Side effects:
    - When category=payment: calls PaymentGateway.charge
    - On gateway success: transaction.status → 'completed'
    - On gateway failure: transaction.status → 'failed'
============================
```

### Test Structure Tree

```
TransactionService#call
├── happy path
│   ├── ✗ (implementation test) expects build_transaction called
│   ├── ✗ (implementation test) expects validate_wallet_active! called
│   ├── ✗ (implementation test) expects validate_currency_match! called
│   ├── ✓ returns success? = true
│   ├── ✓ transaction is persisted
│   ├── ✗ transaction has correct field values (amount, currency, status, category, wallet_id)
│   └── ✗ DB assertions — Transaction record has correct values
├── field: wallet status
│   ├── ✓ suspended → failure with 'Wallet is not active'
│   └── ✗ closed → failure
├── field: currency mismatch — NO TESTS
│   └── ✗ currency != wallet.currency → failure
├── field: category = payment
│   ├── ✗ (implementation test) expects charge_payment_gateway called
│   ├── ✗ gateway success → transaction status = 'completed'
│   ├── ✗ gateway failure → transaction status = 'failed'
│   └── ✗ ChargeError → failure result
└── field: invalid params — NO TESTS
    └── ✗ RecordInvalid → failure with 'Validation failed'
```

### Gap Analysis by Priority

**HIGH** — This entire test file should be replaced by endpoint-level tests in `spec/requests/api/v1/post_transactions_spec.rb`. The gaps below are listed for completeness but the recommended action is to **delete this file and test through the API**.

- [ ] Currency mismatch scenario untested
- [ ] ChargeError handling untested
- [ ] Gateway success/failure status transitions untested
- [ ] RecordInvalid (validation failure) untested
- [ ] Happy path has no field-value assertions on the created transaction

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Service layer tested instead of API | `transaction_service_spec.rb` (entire file) | HIGH | Move tests to `post_transactions_spec.rb`, test through HTTP |
| Implementation testing (method call expectations) | `transaction_service_spec.rb:12,17,22,49` | HIGH | Replace with output/state assertions |
| Mocking internal methods | `transaction_service_spec.rb:12,17,22,49` | HIGH | Remove -- test behavior, not calls |
| No DB field-value assertions | `transaction_service_spec.rb:28-30` | MEDIUM | Assert transaction field values |

### Top 5 Priority Actions

1. **Delete this file** — all scenarios should be tested through `POST /api/v1/transactions` endpoint
2. **Remove all `expect(service).to receive(...)` calls** — these are implementation tests, not contract tests
3. **Move wallet-inactive test to endpoint level** — test via HTTP request, not service call
4. **Add currency mismatch, ChargeError, gateway success/failure scenarios at endpoint level**
5. **Add field-value assertions** for the created transaction

---
