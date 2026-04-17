# Test Audit — POST /api/v1/transactions

## Files Reviewed

- `spec/requests/api/v1/transactions_spec.rb` — request spec (contract boundary)
- `spec/services/transaction_service_spec.rb` — service spec (NON-boundary, see anti-patterns)

---

## Anti-Patterns

### Anti-pattern 1: Service spec is not a contract boundary

**File:** `spec/services/transaction_service_spec.rb`

`TransactionService` is an internal implementation detail of the `POST /api/v1/transactions` endpoint. It is not consumed by other teams or systems. This spec should be deleted and its behavioral coverage moved into the request spec.

**Recommendation:** Delete `spec/services/transaction_service_spec.rb` — test through `POST /api/v1/transactions` instead.

---

### Anti-pattern 2: Multiple endpoints in one request spec file

**File:** `spec/requests/api/v1/transactions_spec.rb`

The file contains three `describe` blocks covering three separate endpoints:
- `POST /api/v1/transactions` (line 21)
- `GET /api/v1/transactions/:id` (line 100)
- `GET /api/v1/transactions` (line 119)

Each endpoint must have its own file so gaps are immediately visible per endpoint.

**Recommendation:** Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, and `get_transactions_spec.rb`.

---

### Anti-pattern 3: Implementation testing in service spec

**File:** `spec/services/transaction_service_spec.rb` lines 12–25

Three tests (`calls build_transaction`, `calls validate_wallet_active!`, `calls validate_currency_match!`) verify that private methods are called, not what behavior is produced. These are implementation tests, not contract tests.

```ruby
# lines 12–25
it 'calls build_transaction' do
  expect(service).to receive(:build_transaction).and_call_original
  service.call
end
it 'calls validate_wallet_active!' do
  expect(service).to receive(:validate_wallet_active!).and_call_original
  service.call
end
it 'calls validate_currency_match!' do
  expect(service).to receive(:validate_currency_match!).and_call_original
  service.call
end
```

---

### Anti-pattern 4: Implementation testing — gateway method call instead of behavior

**File:** `spec/services/transaction_service_spec.rb` lines 47–51

The test asserts that `charge_payment_gateway` (an internal private method) is called, not that the correct params were sent to `PaymentGateway.charge` or that the transaction status was updated correctly.

```ruby
# lines 47–51
it 'calls charge_payment_gateway' do
  allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  expect(service).to receive(:charge_payment_gateway).and_call_original
  service.call
end
```

---

### Anti-pattern 5: Missing test foundation (no subject / no shared `run_test` helper)

**File:** `spec/requests/api/v1/transactions_spec.rb`

Each test manually calls `post '/api/v1/transactions', params: params, headers: headers` inline (e.g. lines 37, 46, 54, 63, 72, 90). There is no shared `subject` or `run_test` helper that all scenarios share. This means override-one-field isolation is not enforced and the structure is harder to audit.

---

### Anti-pattern 6: Error scenario tests assert only status code — no negative assertions

**File:** `spec/requests/api/v1/transactions_spec.rb` (lines 42–93)

Every error scenario (`amount nil`, `amount negative`, `currency nil`, `currency invalid`, `wallet not found`) asserts only `have_http_status`. None asserts:
- No DB record was created
- No outbound `PaymentGateway.charge` call was made
- No sensitive data leaked in the error response body

---

### Anti-pattern 7: Happy path asserts only status code

**File:** `spec/requests/api/v1/transactions_spec.rb` lines 35–40

```ruby
context 'with valid params' do
  it 'returns 201' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
  end
end
```

No response body fields, no DB assertions, no outbound API call assertions.

---

## Per-Field Coverage Notes

Fields are grouped by typed prefix. Coverage is assessed against `spec/requests/api/v1/transactions_spec.rb` only (the contract boundary file). The service spec is excluded from coverage credit due to being a non-boundary file.

---

### request header: Authorization

| Scenario | Covered? | Location |
|---|---|---|
| missing → 401 | NO | — |

Notes: No test sends a request without the `Authorization` header. No 401 scenario exists anywhere in the request spec.

---

### request field: transaction.amount

| Scenario | Covered? | Location |
|---|---|---|
| nil → 422 | YES | transactions_spec.rb:42 |
| negative → 422 | YES | transactions_spec.rb:51 |
| zero → 422 | NO | — |
| exceeds max (> 1_000_000) → 422 | NO | — |
| string that is not numeric → 422 | NO | — |
| equals wallet balance → 201, balance becomes 0 | NO | — |
| exceeds wallet balance → 422 | NO | — |

Notes: `nil` and negative are covered. Zero, above-max, non-numeric string, boundary balance (exact match, overdraft) are all missing.

---

### request field: transaction.currency

| Scenario | Covered? | Location |
|---|---|---|
| nil → 422 | YES | transactions_spec.rb:60 |
| invalid value → 422 | YES | transactions_spec.rb:69 |
| empty string → 422 | NO | — |
| valid values: USD, EUR, GBP, BTC, ETH (happy path baseline covers USD only) | PARTIAL | transactions_spec.rb:32 |

Notes: `nil` and invalid string covered. Empty string missing. Only USD exercised in happy path; other valid currencies not tested.

---

### request field: transaction.wallet_id

| Scenario | Covered? | Location |
|---|---|---|
| wallet does not exist → 422 | YES | transactions_spec.rb:78 |
| wallet belongs to another user → 422 | NO | — |
| nil wallet_id → 422 | NO | — |

Notes: Non-existent wallet_id covered. IDOR scenario (wallet owned by different user) and nil wallet_id are missing.

---

### request field: transaction.description

| Scenario | Covered? | Location |
|---|---|---|
| omitted (optional) → 201 | NO | — |
| provided → 201, persisted correctly | NO | — |
| exceeds 500 chars → 422 | NO | — |

Notes: No tests for the `description` field at all. The default happy-path params do not include `description`.

---

### request field: transaction.category

| Scenario | Covered? | Location |
|---|---|---|
| omitted → defaults to 'transfer' | NO | — |
| 'transfer' → 201 | NO | — |
| 'payment' → 201, calls PaymentGateway | NO | — |
| 'deposit' → 201, balance NOT decremented | NO | — |
| 'withdrawal' → 201 | NO | — |
| invalid value → 422 | NO | — |

Notes: No tests for the `category` field whatsoever in the request spec. The service spec touches `category: 'payment'` but on a non-boundary file and only asserts internal method dispatch.

---

### db field: wallet.status (input precondition)

| Scenario | Covered? | Location |
|---|---|---|
| active (happy path) | PARTIAL | wallet created without explicit status; factory default assumed active |
| suspended → 422 | NO | — |
| closed → 422 | NO | — |

Notes: The happy path implicitly uses an active wallet (factory default), but there is no explicit assertion that the wallet status determines access. `suspended` and `closed` wallet scenarios are absent from the request spec (noted in comments at line 97 of the spec).

---

### db field: wallet.currency (input precondition)

| Scenario | Covered? | Location |
|---|---|---|
| currency mismatch → 422 | NO | — |

Notes: The wallet is created with `currency: 'USD'` and all request params also use `'USD'`, so currency mismatch is never exercised. There is a comment gap marker at line 97.

---

### db field: wallet.balance (input precondition)

| Scenario | Covered? | Location |
|---|---|---|
| sufficient balance (happy path) | PARTIAL | wallet uses factory default balance, not explicitly set |
| exact balance match → 201, balance becomes 0 | NO | — |
| insufficient balance → 422 | NO | — |
| balance leaks in error response details | NO | — |

Notes: The insufficient balance scenario is called out in comments (line 13) but no test exists. The balance data-leak scenario (InsufficientBalanceError details containing "Current balance: X") is also not tested.

---

### response field: transaction.id

| Covered? | Notes |
|---|---|
| NO | Happy path only asserts status 201, never parses or checks response body |

---

### response field: transaction.amount

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.currency

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.status

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.description

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.category

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.wallet_id

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.created_at

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: transaction.updated_at

| Covered? | Notes |
|---|---|
| NO | Not asserted in any test |

---

### response field: error (error response)

| Scenario | Covered? | Location |
|---|---|---|
| error message present on 422 | NO | Error tests assert only status code, never parse body |
| no sensitive data leak | NO | — |

---

### response field: details (error response)

| Scenario | Covered? | Location |
|---|---|---|
| details array present on 422 | NO | — |
| InsufficientBalanceError leaks balance value | NO | — |

---

### db field: transaction.user_id (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block |

---

### db field: transaction.wallet_id (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block |

---

### db field: transaction.amount (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block |

---

### db field: transaction.currency (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block |

---

### db field: transaction.status (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block; no payment category scenario exists in request spec |

---

### db field: transaction.description (assertion)

| Covered? | Notes |
|---|---|
| NO | No description field tests exist at all |

---

### db field: transaction.category (assertion)

| Covered? | Notes |
|---|---|
| NO | No category field tests exist at all |

---

### db field: transaction.created_at (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block |

---

### db field: transaction.updated_at (assertion)

| Covered? | Notes |
|---|---|
| NO | Happy path has no DB assertion block |

---

### db field: wallet.balance (assertion — decremented after non-deposit)

| Scenario | Covered? | Location |
|---|---|---|
| balance decremented by amount after transfer | NO | — |
| balance not decremented for deposit | NO | — |
| balance updated to zero when amount equals balance | NO | — |

---

### outbound response field: PaymentGateway.charge.success? (input — mock return)

| Scenario | Covered? | Location |
|---|---|---|
| success? = true → transaction status 'completed' | NO | — |
| success? = false → transaction status 'failed' | NO | — |

Notes: No outbound API scenario exists in the request spec. The service spec stubs `PaymentGateway.charge` once (`double(success?: true)`) but is a non-boundary file and does not assert the transaction status update.

---

### outbound response field: PaymentGateway.charge — ChargeError raised (input — mock return)

| Scenario | Covered? | Location |
|---|---|---|
| ChargeError raised → 422, error 'Payment processing failed' | NO | — |
| ChargeError raised → no DB status change / no committed completed state | NO | — |

---

### outbound request field: amount (assertion)

| Covered? | Notes |
|---|---|
| NO | No request spec test verifies what params are sent to PaymentGateway.charge |

---

### outbound request field: currency (assertion)

| Covered? | Notes |
|---|---|
| NO | Same as above |

---

### outbound request field: user_id (assertion)

| Covered? | Notes |
|---|---|
| NO | Same as above |

---

### outbound request field: transaction_id (assertion)

| Covered? | Notes |
|---|---|
| NO | Same as above |

---

## Coverage Summary

| Field (typed prefix) | Scenarios Covered | Scenarios Missing |
|---|---|---|
| request header: Authorization | 0 | 1 (missing → 401) |
| request field: transaction.amount | 2 (nil, negative) | 5 (zero, >max, non-numeric, exact balance, overdraft) |
| request field: transaction.currency | 2 (nil, invalid) | 2 (empty string, each valid enum value) |
| request field: transaction.wallet_id | 1 (not found) | 2 (nil, other-user IDOR) |
| request field: transaction.description | 0 | 3 (omitted, provided, >500 chars) |
| request field: transaction.category | 0 | 6 (omitted/default, transfer, payment, deposit, withdrawal, invalid) |
| db field: wallet.status (input) | 0 explicit | 2 (suspended, closed) |
| db field: wallet.currency (input) | 0 | 1 (mismatch → 422) |
| db field: wallet.balance (input) | 0 explicit | 3 (exact, insufficient, balance leak) |
| response field: transaction.id | 0 | 1 |
| response field: transaction.amount | 0 | 1 |
| response field: transaction.currency | 0 | 1 |
| response field: transaction.status | 0 | 1 |
| response field: transaction.description | 0 | 1 |
| response field: transaction.category | 0 | 1 |
| response field: transaction.wallet_id | 0 | 1 |
| response field: transaction.created_at | 0 | 1 |
| response field: transaction.updated_at | 0 | 1 |
| response field: error | 0 | 1 |
| response field: details | 0 | 2 (present, balance leak) |
| db field: transaction.user_id (assertion) | 0 | 1 |
| db field: transaction.wallet_id (assertion) | 0 | 1 |
| db field: transaction.amount (assertion) | 0 | 1 |
| db field: transaction.currency (assertion) | 0 | 1 |
| db field: transaction.status (assertion) | 0 | 1 |
| db field: transaction.description (assertion) | 0 | 1 |
| db field: transaction.category (assertion) | 0 | 1 |
| db field: transaction.created_at (assertion) | 0 | 1 |
| db field: transaction.updated_at (assertion) | 0 | 1 |
| db field: wallet.balance (assertion) | 0 | 3 |
| outbound response field: PaymentGateway.charge.success? | 0 | 2 (true→completed, false→failed) |
| outbound response field: PaymentGateway.charge — ChargeError | 0 | 2 (422 response, no status change) |
| outbound request field: amount | 0 | 1 |
| outbound request field: currency | 0 | 1 |
| outbound request field: user_id | 0 | 1 |
| outbound request field: transaction_id | 0 | 1 |

**Total fields:** 36
**Fields with at least one covered scenario:** 3 (transaction.amount — partial, transaction.currency — partial, transaction.wallet_id — partial)
**Fields with zero coverage:** 33
