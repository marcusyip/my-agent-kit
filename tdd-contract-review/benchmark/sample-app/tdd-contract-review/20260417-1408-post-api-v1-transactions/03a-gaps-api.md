# API Inbound Gap Analysis — POST /api/v1/transactions

Scope: API inbound contract only — request header, request fields, response fields, error response fields. DB and outbound sections are covered in sibling reports.

---

## Test Structure Tree (API inbound)

```
POST /api/v1/transactions
│
├── request header: Authorization — PARTIAL
│   ├── ✗ missing token → 401, no DB write, no outbound API call, no data leak
│   ├── ✗ malformed token (e.g. "Bearer notarealjwt") → 401, no DB write, no data leak
│   ├── ✗ expired token → 401, no DB write, no data leak
│   └── ✗ token for deleted/disabled user → 401, no DB write, no data leak
│
├── request field: transaction.amount — PARTIAL
│   ├── ✓ nil → 422 (transactions_spec.rb:42)  [status only; missing: no DB write / no outbound / no data leak assertions]
│   ├── ✓ negative (e.g. -100) → 422 (transactions_spec.rb:51)  [status only; missing: no DB write / no outbound / no data leak assertions]
│   ├── ✗ empty string "" → 422, no DB write, no outbound API call, no data leak
│   ├── ✗ whitespace-only " " → 422, no DB write, no outbound API call, no data leak
│   ├── ✗ zero "0" → 422 (not greater_than: 0), no DB write, no outbound API call, no data leak
│   ├── ✗ type violation: non-numeric string ("abc") → 422, no DB write, no data leak
│   ├── ✗ type violation: array / object → 422, no DB write, no data leak
│   ├── ✗ boundary: just-above-zero "0.00000001" (decimal(20,8) min unit) → 201 if balance sufficient
│   ├── ✗ boundary: exactly max 1_000_000 → 201
│   ├── ✗ boundary: just-over-max 1_000_000.00000001 → 422, no DB write, no data leak
│   ├── ✗ boundary: far-over-max 10_000_000 → 422, no DB write, no data leak
│   ├── ✗ precision: amount with 9 decimal places (exceeds scale:8) → document behavior (round/truncate/reject) + assert DB persists scale:8 only
│   ├── ✗ float trap: amount sent as JSON float (0.1+0.2 style) → assert decimal precision preserved
│   ├── ✗ cross-field: amount == wallet.balance → 201, wallet.balance becomes 0
│   ├── ✗ cross-field: amount > wallet.balance (overdraft) → 422, no DB write, no outbound API call, no balance leak in error
│   ├── ✗ cross-field: amount == wallet.balance + 0.00000001 (by 1 satoshi) → 422, no DB write, no data leak
│   └── ✗ concurrency: two concurrent requests where each amount <= balance but sum > balance → only one succeeds, balance never negative (TOCTOU)
│
├── request field: transaction.currency — PARTIAL
│   ├── ✓ nil → 422 (transactions_spec.rb:60)  [status only; missing: no DB write / no data leak assertions]
│   ├── ✓ invalid value "ZZZ" → 422 (transactions_spec.rb:69)  [status only; missing: no DB write / no data leak assertions]
│   ├── ✗ empty string "" → 422, no DB write, no data leak
│   ├── ✗ whitespace-only " " → 422, no DB write, no data leak
│   ├── ✗ type violation: integer 123 → 422, no DB write, no data leak
│   ├── ✗ case sensitivity: "usd" (lowercase) → reject or normalize (assert contract behavior)
│   ├── ✗ leading/trailing whitespace: " USD " → reject or trim (assert contract behavior)
│   ├── ✗ enum value: USD → 201 (partial — baseline happy path at transactions_spec.rb:32 uses USD but asserts status only)
│   ├── ✗ enum value: EUR → 201, response currency == 'EUR'
│   ├── ✗ enum value: GBP → 201, response currency == 'GBP'
│   ├── ✗ enum value: BTC → 201, response currency == 'BTC'
│   ├── ✗ enum value: ETH → 201, response currency == 'ETH'
│   ├── ✗ injection: SQL payload "USD'; DROP TABLE" → 422 (not in enum), no DB write, no data leak
│   ├── ✗ injection: NULL byte "USD\0EUR" → 422, no DB write, no data leak
│   └── ✗ cross-field: request currency 'USD', wallet.currency 'EUR' (mismatch) → 422, no DB write, no outbound API call, no data leak
│
├── request field: transaction.wallet_id — PARTIAL
│   ├── ✓ wallet does not exist (nonexistent id) → 422 (transactions_spec.rb:78)  [status only; missing: no DB write / no data leak assertions]
│   ├── ✗ nil → 422, no DB write, no data leak
│   ├── ✗ empty string "" → 422, no DB write, no data leak
│   ├── ✗ type violation: string "abc" → 422, no DB write, no data leak
│   ├── ✗ type violation: negative integer -1 → 422, no DB write, no data leak
│   ├── ✗ type violation: zero 0 → 422, no DB write, no data leak
│   ├── ✗ boundary: very large integer (2^63) → 422, no DB write, no data leak; no stack trace leak
│   ├── ✗ IDOR: wallet exists but belongs to another user → 422 (find_by scoped to current_user), no DB write, no data leak, response must NOT confirm other user's wallet exists
│   ├── ✗ injection: SQL payload in wallet_id "1 OR 1=1" → 422, no DB write, no data leak
│   └── ✗ cross-field: wallet.status = 'suspended' → 422, no DB write, no outbound API call, no data leak
│
├── request field: transaction.description — NO TESTS
│   ├── ✗ omitted (optional) → 201, transaction.description == nil
│   ├── ✗ nil explicitly → 201, transaction.description == nil
│   ├── ✗ empty string "" → 201 or 422 (document contract), assert DB state matches
│   ├── ✗ whitespace-only " " → document contract (trim or persist as-is), assert DB state
│   ├── ✗ type violation: integer / array → 422, no DB write, no data leak
│   ├── ✗ boundary: exactly 500 chars → 201, persisted verbatim
│   ├── ✗ boundary: 501 chars → 422, no DB write, no data leak
│   ├── ✗ boundary: 10_000 chars → 422, no DB write, no data leak
│   ├── ✗ format: UTF-8 multi-byte chars (emoji, CJK) within 500-char limit → 201, persisted intact
│   ├── ✗ injection: SQL payload "'; DROP TABLE transactions; --" → 201, stored verbatim, NOT executed
│   ├── ✗ injection: XSS payload "<script>alert(1)</script>" → 201, stored verbatim (assert not rendered in any response path)
│   ├── ✗ injection: NULL byte "hello\0world" → 422 or stored (document contract)
│   └── ✗ injection: command injection "; rm -rf /" → 201, stored verbatim, no shell execution
│
├── request field: transaction.category — NO TESTS
│   ├── ✗ omitted → 201, defaults to 'transfer', response.category == 'transfer', db.category == 'transfer'
│   ├── ✗ nil → 201, defaults to 'transfer' (document contract — or reject as invalid)
│   ├── ✗ empty string "" → 422, no DB write, no data leak
│   ├── ✗ type violation: integer 1 → 422, no DB write, no data leak
│   ├── ✗ enum value: 'transfer' → 201, balance decremented, NO PaymentGateway.charge call
│   ├── ✗ enum value: 'payment' → 201, PaymentGateway.charge invoked exactly once (guard against dual-call path), balance decremented
│   ├── ✗ enum value: 'deposit' → 201, wallet.balance NOT decremented (withdraw skipped per deduct_balance!)
│   ├── ✗ enum value: 'withdrawal' → 201, balance decremented
│   ├── ✗ invalid value 'refund' → 422, no DB write, no outbound API call, no data leak
│   ├── ✗ case sensitivity: 'PAYMENT' (uppercase) → reject or normalize (document contract)
│   ├── ✗ injection: SQL payload "payment'; DROP TABLE --" → 422, no DB write, no data leak
│   └── ✗ cross-field: category 'payment' + PaymentGateway.charge returns failure → 422, status 'failed' persisted, no balance change (or rollback semantics documented)
│
├── response field: transaction.id — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; integer type; non-nil; matches Transaction.last.id
│
├── response field: transaction.amount — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; decimal-as-string (via .to_s); value matches request.amount (e.g. "100.00000000"); not a JSON float
│
├── response field: transaction.currency — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; string; value matches request.currency exactly (including case)
│
├── response field: transaction.status — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; string; one of pending/completed/failed/reversed
│   ├── ✗ for transfer/deposit/withdrawal: defaults to 'pending'
│   ├── ✗ for payment + gateway success: 'completed'
│   └── ✗ for payment + gateway failure: 'failed'
│
├── response field: transaction.description — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201 when provided; echoes input
│   └── ✗ nullability: when omitted, field present with null value (contract explicit — present vs. omitted)
│
├── response field: transaction.category — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; string; one of transfer/payment/deposit/withdrawal
│   └── ✗ when omitted in request, response.category == 'transfer' (default)
│
├── response field: transaction.wallet_id — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; integer; matches request.wallet_id
│
├── response field: transaction.created_at — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; ISO8601 format (via .iso8601)
│   └── ✗ string type (not raw Ruby Time object serialization), UTC offset present
│
├── response field: transaction.updated_at — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; ISO8601 format (via .iso8601)
│   └── ✗ >= created_at
│
├── response field: error (error envelope) — NO TESTS
│   ├── ✗ present on every 422 response; string; human-readable
│   ├── ✗ does NOT leak internal stack traces / SQL errors / class names
│   ├── ✗ for insufficient balance: error message is generic (no balance value in error string itself)
│   ├── ✗ for IDOR wallet (another user's wallet): error does NOT confirm wallet exists for another user
│   └── ✗ for payment gateway ChargeError: error == 'Payment processing failed' (exact match)
│
└── response field: details (error envelope) — NO TESTS
    ├── ✗ present on 422; array of strings
    ├── ✗ FINTECH SECURITY: for InsufficientBalanceError, details currently leak balance ("Current balance: X, requested: Y") — assert balance value is NOT present in details (remediation test)
    ├── ✗ does NOT leak account numbers, user IDs, internal resource IDs
    ├── ✗ does NOT leak SQL fragments or stack traces
    └── ✗ empty array allowed vs. required — document contract
```

---

## Contract Map (API inbound)

| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
|---|---|---|---|---|---|
| request header | Authorization | Input | missing, malformed, expired, wrong-user | 0 | 4 |
| request field | transaction.amount | Input | nil, empty string, whitespace-only, zero, negative, non-numeric, wrong type, min-unit (0.00000001), exactly-max (1_000_000), just-over-max, far-over-max, precision >scale 8, float-trap, amount==balance, amount>balance, amount==balance+1sat, concurrent TOCTOU | nil, negative (status only) | 15 (2 PARTIAL upgrade) |
| request field | transaction.currency | Input | nil, empty string, whitespace-only, wrong type, lowercase, leading/trailing whitespace, USD, EUR, GBP, BTC, ETH, SQL injection, NULL byte, wallet currency mismatch | nil, invalid (status only); USD baseline (status only) | 12 (3 PARTIAL upgrade) |
| request field | transaction.wallet_id | Input | nil, empty string, wrong type (string/negative/zero), very-large int, nonexistent id, IDOR other-user wallet, SQL injection, wallet.status suspended cross-field | nonexistent id (status only) | 9 (1 PARTIAL upgrade) |
| request field | transaction.description | Input | omitted, nil, empty, whitespace, wrong type, exactly 500 chars, 501 chars, 10_000 chars, UTF-8 multibyte, SQL injection, XSS, NULL byte, command injection | 0 | 13 |
| request field | transaction.category | Input | omitted (default), nil, empty, wrong type, transfer, payment, deposit, withdrawal, invalid, case sensitivity, SQL injection, payment+gateway-failure cross-field | 0 | 12 |
| response field | transaction.id | Assertion | presence, integer type, matches DB | 0 | 1 |
| response field | transaction.amount | Assertion | presence, decimal-as-string format, value correctness | 0 | 1 |
| response field | transaction.currency | Assertion | presence, value matches input | 0 | 1 |
| response field | transaction.status | Assertion | presence, enum value correctness per category + gateway outcome | 0 | 1 |
| response field | transaction.description | Assertion | presence, nullability (omitted case) | 0 | 1 |
| response field | transaction.category | Assertion | presence, default value when omitted | 0 | 1 |
| response field | transaction.wallet_id | Assertion | presence, matches request | 0 | 1 |
| response field | transaction.created_at | Assertion | presence, ISO8601 format, string type | 0 | 1 |
| response field | transaction.updated_at | Assertion | presence, ISO8601 format, >= created_at | 0 | 1 |
| response field | error | Assertion | presence on 422, human-readable, no stack trace leak, no balance leak, IDOR non-disclosure, ChargeError exact message | 0 | 1 |
| response field | details | Assertion | presence on 422, array type, FINTECH no balance leak, no account/user leak, no SQL leak | 0 | 1 |

---

## Gap List

### CRITICAL

- **GAPI-001** — `response field: details` — **API inbound**
  - Priority: CRITICAL
  - Description: Error response `details` array currently includes raw balance in the InsufficientBalanceError path (`"Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"`). No test asserts that sensitive financial data is NOT leaked in error responses. This is a FINTECH security gap — error-path contract must forbid balance disclosure.
  - Stub: REQUIRED

- **GAPI-002** — `request field: transaction.wallet_id` (IDOR) — **API inbound**
  - Priority: CRITICAL
  - Description: No test exercises the IDOR scenario — a valid wallet_id belonging to a different user. Controller uses `current_user.wallets.find_by(...)` which should return 422, but without a test any future refactor (e.g. to `Wallet.find_by`) would silently permit cross-tenant writes. Must also assert the error response does NOT leak that the wallet exists for another user.
  - Stub: REQUIRED

- **GAPI-003** — `request header: Authorization` — **API inbound**
  - Priority: CRITICAL
  - Description: Zero coverage of any 401 path. Missing token, malformed token, expired token, and token for disabled user all unenforced in tests. Without these, a regression in `authenticate_user!` could expose transactions endpoint to the public.
  - Stub: REQUIRED

### HIGH

- **GAPI-004** — `request field: transaction.amount` (overdraft / amount>balance) — **API inbound**
  - Priority: HIGH
  - Description: No test submits an amount larger than wallet.balance. Must assert 422, zero DB writes, no PaymentGateway.charge call, and no balance value in error body (ties to GAPI-001).
  - Stub: REQUIRED

- **GAPI-005** — `request field: transaction.amount` (exact balance boundary) — **API inbound**
  - Priority: HIGH
  - Description: No test submits amount == wallet.balance. This is the critical boundary where the account should drain to exactly zero. Must assert 201 and final wallet.balance == 0.
  - Stub: REQUIRED

- **GAPI-006** — `request field: transaction.amount` (just-over-max 1_000_000) — **API inbound**
  - Priority: HIGH
  - Description: No boundary test at the regulatory limit. `less_than_or_equal_to: 1_000_000` means exactly 1_000_000 should succeed, 1_000_000.00000001 must reject. Neither covered.
  - Stub: REQUIRED

- **GAPI-007** — `request field: transaction.amount` (zero) — **API inbound**
  - Priority: HIGH
  - Description: No test for amount=0. `numericality greater_than: 0` means zero must be rejected with 422. Currently untested; a change to `>= 0` would pass silently.
  - Stub: REQUIRED

- **GAPI-008** — `request field: transaction.amount` (non-numeric string) — **API inbound**
  - Priority: HIGH
  - Description: No test submits "abc" or other non-numeric string. BigDecimal coercion behavior on junk input is undefined without a test pinning it.
  - Stub: REQUIRED

- **GAPI-009** — `request field: transaction.amount` (precision >scale:8) — **API inbound**
  - Priority: HIGH
  - Description: No test submits amount with 9+ decimal places. DB schema is `decimal(20,8)`; the system must either round, truncate, or reject — pin the behavior with a test.
  - Stub: REQUIRED

- **GAPI-010** — `request field: transaction.currency` (cross-field wallet mismatch) — **API inbound**
  - Priority: HIGH
  - Description: No test where request currency does not match wallet currency. `validate_currency_match!` is untested through the endpoint. Must assert 422, no DB write, no outbound call.
  - Stub: REQUIRED

- **GAPI-011** — `request field: transaction.currency` (per-enum coverage) — **API inbound**
  - Priority: HIGH
  - Description: Only USD is exercised (and only for status code). EUR, GBP, BTC, ETH each need their own happy-path test with matching wallet currency and response assertion.
  - Stub: REQUIRED

- **GAPI-012** — `request field: transaction.category` (every enum value) — **API inbound**
  - Priority: HIGH
  - Description: Zero coverage for category field. Each enum value drives different code paths: 'payment' triggers PaymentGateway.charge, 'deposit' skips balance deduction. Each enum must be its own test.
  - Stub: REQUIRED

- **GAPI-013** — `request field: transaction.category` (default 'transfer') — **API inbound**
  - Priority: HIGH
  - Description: No test confirms that omitting category results in 'transfer'. `TransactionService#build_transaction` default is untested.
  - Stub: REQUIRED

- **GAPI-014** — `request field: transaction.category` (invalid value) — **API inbound**
  - Priority: HIGH
  - Description: No test for an invalid category value (e.g. 'refund'). Must return 422 with no DB write and no outbound call.
  - Stub: REQUIRED

- **GAPI-015** — `request field: transaction.description` (length boundary) — **API inbound**
  - Priority: HIGH
  - Description: No test for description field at all. Needs boundary tests at 500 chars (accepted) and 501 chars (422) to guard the `length maximum: 500` validation.
  - Stub: REQUIRED

- **GAPI-016** — `response field: transaction.id / amount / currency / status / wallet_id / category / description / created_at / updated_at` — **API inbound**
  - Priority: HIGH
  - Description: Happy path at transactions_spec.rb:35-40 asserts only status 201 — response body is never parsed. Every response field needs value + type + format assertions. amount must be asserted as decimal-as-string; created_at/updated_at as ISO8601.
  - Stub: REQUIRED

- **GAPI-017** — `response field: error` on 422 paths — **API inbound**
  - Priority: HIGH
  - Description: No error-body assertions in any error test. Each 422 must assert error string is present, human-readable, and free of SQL/stack trace content. ChargeError path must assert exact 'Payment processing failed' message.
  - Stub: REQUIRED

- **GAPI-018** — `request field: transaction.currency` (empty string) — **API inbound**
  - Priority: HIGH
  - Description: nil is covered but empty string "" is not. These take separate controller validation paths.
  - Stub: REQUIRED

- **GAPI-019** — `request field: transaction.wallet_id` (nil) — **API inbound**
  - Priority: HIGH
  - Description: No test for nil wallet_id — the `find_by(id: nil)` path.
  - Stub: REQUIRED

- **GAPI-020** — Existing error tests assert status code only — **API inbound**
  - Priority: HIGH
  - Description: transactions_spec.rb:42, 51, 60, 69, 78 assert only `have_http_status(:unprocessable_entity)`. None assert no DB record created (`expect { run_test }.not_to change(Transaction, :count)`), no PaymentGateway.charge call, and no data leak in body. Upgrade existing PARTIAL tests.
  - Stub: REQUIRED

### MEDIUM

- **GAPI-021** — `request field: transaction.description` (injection payloads) — **API inbound**
  - Priority: MEDIUM
  - Description: description is a free-text string persisted to DB. SQL injection, XSS, command injection, NULL-byte payloads should all be stored verbatim (not executed). No tests assert this.
  - Stub: not required

- **GAPI-022** — `request field: transaction.currency` (case sensitivity, whitespace) — **API inbound**
  - Priority: MEDIUM
  - Description: Document contract behavior on "usd" (lowercase) and " USD " (padded). Likely rejected (enum exact-match), but untested.
  - Stub: not required

- **GAPI-023** — `request field: transaction.amount` (type violations: array, object) — **API inbound**
  - Priority: MEDIUM
  - Description: Sending non-string non-number (array `[100]`, object `{}`) should 422 gracefully without 500.
  - Stub: not required

- **GAPI-024** — `response field: transaction.description` nullability — **API inbound**
  - Priority: MEDIUM
  - Description: When description is omitted in request, does the response include `"description": null` or omit the key entirely? Document the contract.
  - Stub: not required

### LOW

- **GAPI-025** — UTF-8 multibyte in description — **API inbound**
  - Priority: LOW
  - Description: Emoji/CJK chars within 500-char limit must persist intact.
  - Stub: not required

- **GAPI-026** — `request field: transaction.wallet_id` very-large integer — **API inbound**
  - Priority: LOW
  - Description: 2^63 integer should 422 cleanly, not raise PG::RangeError 500.
  - Stub: not required

---

## Test Stubs

RSpec pseudocode for HIGH/CRITICAL gaps. Uses the `run_test`/`defaults` foundation the audit recommended introducing (`spec/requests/api/v1/post_transactions_spec.rb`).

```ruby
RSpec.describe 'POST /api/v1/transactions', type: :request do
  # --- Foundation ---
  DEFAULT_AMOUNT    = '100'
  DEFAULT_CURRENCY  = 'USD'
  DEFAULT_CATEGORY  = 'transfer'
  WALLET_BALANCE    = '500'

  subject(:run_test) do
    post '/api/v1/transactions',
         params: { transaction: params },
         headers: headers,
         as: :json
  end

  let(:user)    { create(:user) }
  let(:headers) { auth_headers(user) }
  let!(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, balance: WALLET_BALANCE, status: 'active') }
  let(:params) do
    { amount: amount, currency: currency, wallet_id: wallet_id,
      description: description, category: category }.compact
  end
  let(:amount)      { DEFAULT_AMOUNT }
  let(:currency)    { DEFAULT_CURRENCY }
  let(:wallet_id)   { wallet.id }
  let(:description) { nil }
  let(:category)    { nil }

  before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

  # =========================================================================
  # GAPI-001 (CRITICAL) — details MUST NOT leak balance
  # =========================================================================
  context 'when amount exceeds balance (FINTECH: no balance leak)' do
    let(:amount) { '10000' } # far above WALLET_BALANCE

    it 'returns 422 and does not leak balance in error details' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)

      body = JSON.parse(response.body)
      expect(body['error']).to be_present
      expect(body['details']).to be_an(Array)
      # Balance MUST NOT be disclosed in any string of error payload
      serialized = body.to_json
      expect(serialized).not_to match(/#{Regexp.escape(wallet.balance.to_s)}/)
      expect(serialized).not_to match(/Current balance/i)
    end
  end

  # =========================================================================
  # GAPI-002 (CRITICAL) — IDOR: wallet owned by another user
  # =========================================================================
  context 'when wallet_id belongs to a different user' do
    let(:other_user)  { create(:user) }
    let!(:other_wallet) { create(:wallet, user: other_user, currency: DEFAULT_CURRENCY, balance: '500') }
    let(:wallet_id) { other_wallet.id }

    it 'returns 422, writes nothing, and does not confirm the other wallet exists' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)

      body = JSON.parse(response.body)
      expect(body['error']).to be_present
      # Must not expose other_wallet.id or other_user.id
      serialized = body.to_json
      expect(serialized).not_to include(other_user.id.to_s)
    end
  end

  # =========================================================================
  # GAPI-003 (CRITICAL) — Authorization header enforcement
  # =========================================================================
  context 'when Authorization header is missing' do
    let(:headers) { {} }

    it 'returns 401 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unauthorized)
      expect(PaymentGateway).not_to have_received(:charge)
      body = JSON.parse(response.body)
      expect(body.to_json).not_to match(/stack|ActiveRecord|NoMethodError/)
    end
  end

  context 'when Authorization header is malformed' do
    let(:headers) { { 'Authorization' => 'Bearer not-a-real-token' } }
    it 'returns 401 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when Authorization token is expired' do
    let(:headers) { expired_auth_headers(user) }
    it 'returns 401 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # GAPI-004 (HIGH) — amount > balance: full negative assertions
  # =========================================================================
  context 'when amount exceeds wallet.balance' do
    let(:amount) { (BigDecimal(WALLET_BALANCE) + 1).to_s }
    it 'returns 422, no DB write, no gateway call' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
      expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE))
    end
  end

  # =========================================================================
  # GAPI-005 (HIGH) — amount == balance drains to zero
  # =========================================================================
  context 'when amount equals wallet.balance' do
    let(:amount) { WALLET_BALANCE }
    it 'returns 201 and sets wallet.balance to 0' do
      run_test
      expect(response).to have_http_status(:created)
      expect(wallet.reload.balance).to eq(0)
      body = JSON.parse(response.body)
      expect(body['transaction']['amount']).to eq(BigDecimal(WALLET_BALANCE).to_s)
    end
  end

  # =========================================================================
  # GAPI-006 (HIGH) — amount boundary at regulatory cap 1_000_000
  # =========================================================================
  context 'when amount is exactly 1_000_000' do
    let!(:wallet) { create(:wallet, user: user, currency: 'USD', balance: '1000000') }
    let(:amount) { '1000000' }
    it 'returns 201' do
      run_test
      expect(response).to have_http_status(:created)
    end
  end

  context 'when amount is just above 1_000_000' do
    let(:amount) { '1000000.00000001' }
    it 'returns 422, no DB write' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  # =========================================================================
  # GAPI-007 (HIGH) — zero amount
  # =========================================================================
  context 'when amount is zero' do
    let(:amount) { '0' }
    it 'returns 422 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  # =========================================================================
  # GAPI-008 (HIGH) — non-numeric amount
  # =========================================================================
  context 'when amount is a non-numeric string' do
    let(:amount) { 'abc' }
    it 'returns 422 and writes nothing, no 500' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body.to_json).not_to match(/BigDecimal|ArgumentError|stack/)
    end
  end

  # =========================================================================
  # GAPI-009 (HIGH) — precision beyond scale:8
  # =========================================================================
  context 'when amount has precision beyond decimal(20,8)' do
    let(:amount) { '100.123456789' } # 9 decimal places
    it 'rounds/truncates/rejects per pinned contract' do
      run_test
      if response.status == 201
        persisted = Transaction.last.amount
        expect(persisted.to_s.split('.').last.length).to be <= 8
      else
        expect(response).to have_http_status(:unprocessable_entity)
        expect(Transaction.count).to eq(0)
      end
    end
  end

  # =========================================================================
  # GAPI-010 (HIGH) — currency mismatch vs wallet.currency
  # =========================================================================
  context 'when request currency does not match wallet.currency' do
    let(:currency) { 'EUR' } # wallet is USD
    it 'returns 422, no DB write, no gateway call' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  # =========================================================================
  # GAPI-011 (HIGH) — each currency enum value as its own scenario
  # =========================================================================
  %w[USD EUR GBP BTC ETH].each do |iso|
    context "when currency is #{iso} (matching wallet)" do
      let!(:wallet) { create(:wallet, user: user, currency: iso, balance: '500') }
      let(:currency) { iso }
      it "returns 201 and response.currency == #{iso}" do
        run_test
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['transaction']['currency']).to eq(iso)
      end
    end
  end

  # =========================================================================
  # GAPI-012 (HIGH) — each category enum value
  # =========================================================================
  context "when category is 'transfer'" do
    let(:category) { 'transfer' }
    it 'returns 201, debits balance, does not call PaymentGateway' do
      run_test
      expect(response).to have_http_status(:created)
      expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE) - BigDecimal(DEFAULT_AMOUNT))
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  context "when category is 'payment'" do
    let(:category) { 'payment' }
    it 'returns 201 and calls PaymentGateway.charge exactly once' do
      run_test
      expect(response).to have_http_status(:created)
      expect(PaymentGateway).to have_received(:charge)
        .with(hash_including(amount: BigDecimal(DEFAULT_AMOUNT), currency: DEFAULT_CURRENCY, user_id: user.id))
        .once # guards against the dual-call path documented in extraction
    end
  end

  context "when category is 'deposit'" do
    let(:category) { 'deposit' }
    it 'returns 201 and does NOT decrement wallet.balance' do
      run_test
      expect(response).to have_http_status(:created)
      expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE))
    end
  end

  context "when category is 'withdrawal'" do
    let(:category) { 'withdrawal' }
    it 'returns 201 and decrements wallet.balance' do
      run_test
      expect(response).to have_http_status(:created)
      expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE) - BigDecimal(DEFAULT_AMOUNT))
    end
  end

  # =========================================================================
  # GAPI-013 (HIGH) — omitted category defaults to 'transfer'
  # =========================================================================
  context 'when category is omitted' do
    let(:category) { nil }
    it "defaults to 'transfer'" do
      run_test
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['transaction']['category']).to eq('transfer')
      expect(Transaction.last.category).to eq('transfer')
    end
  end

  # =========================================================================
  # GAPI-014 (HIGH) — invalid category
  # =========================================================================
  context "when category is invalid" do
    let(:category) { 'refund' }
    it 'returns 422 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  # =========================================================================
  # GAPI-015 (HIGH) — description length boundaries
  # =========================================================================
  context 'when description is exactly 500 chars' do
    let(:description) { 'a' * 500 }
    it 'returns 201 and persists it verbatim' do
      run_test
      expect(response).to have_http_status(:created)
      expect(Transaction.last.description.length).to eq(500)
    end
  end

  context 'when description is 501 chars' do
    let(:description) { 'a' * 501 }
    it 'returns 422 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # =========================================================================
  # GAPI-016 (HIGH) — happy-path response body assertions (every field)
  # =========================================================================
  context 'happy path — full response contract' do
    let(:description) { 'coffee' }
    let(:category)    { 'transfer' }

    it 'returns 201 with all response fields correctly typed and formatted' do
      run_test
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      txn  = body['transaction']

      expect(txn['id']).to be_a(Integer).and be > 0
      expect(txn['amount']).to eq(BigDecimal(DEFAULT_AMOUNT).to_s) # decimal-as-string
      expect(txn['amount']).to be_a(String) # not JSON float
      expect(txn['currency']).to eq(DEFAULT_CURRENCY)
      expect(txn['status']).to eq('pending')
      expect(txn['description']).to eq('coffee')
      expect(txn['category']).to eq('transfer')
      expect(txn['wallet_id']).to eq(wallet.id)
      expect(txn['created_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/) # ISO8601
      expect(txn['updated_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(Time.iso8601(txn['updated_at'])).to be >= Time.iso8601(txn['created_at'])
    end
  end

  # =========================================================================
  # GAPI-017 (HIGH) — error envelope assertions
  # =========================================================================
  context 'error envelope on every 422 path' do
    let(:amount) { '-1' } # any 422 trigger
    it 'returns { error: String, details: Array } with no stack leak' do
      run_test
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to be_a(String).and be_present
      expect(body['details']).to be_an(Array)
      expect(body.to_json).not_to match(/ActiveRecord::|NoMethodError|\.rb:\d+/)
    end
  end

  context 'ChargeError path returns exact error message' do
    let(:category) { 'payment' }
    before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError) }
    it "error == 'Payment processing failed'" do
      run_test
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Payment processing failed')
    end
  end

  # =========================================================================
  # GAPI-018 (HIGH) — currency empty string
  # =========================================================================
  context 'when currency is empty string' do
    let(:currency) { '' }
    it 'returns 422 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # =========================================================================
  # GAPI-019 (HIGH) — wallet_id nil
  # =========================================================================
  context 'when wallet_id is nil' do
    let(:wallet_id) { nil }
    it 'returns 422 and writes nothing' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  # =========================================================================
  # GAPI-020 (HIGH) — upgrade existing PARTIAL tests to assert no side effects
  # =========================================================================
  shared_examples 'a rejected request with no side effects' do
    it 'does not create a transaction, does not call gateway, does not leak' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
      body = JSON.parse(response.body)
      expect(body.to_json).not_to match(/ActiveRecord|stack|BigDecimal/)
    end
  end

  context 'when amount is nil' do
    let(:amount) { nil }
    it_behaves_like 'a rejected request with no side effects'
  end

  context 'when amount is negative' do
    let(:amount) { '-100' }
    it_behaves_like 'a rejected request with no side effects'
  end

  context 'when currency is nil' do
    let(:currency) { nil }
    it_behaves_like 'a rejected request with no side effects'
  end

  context 'when currency is invalid enum' do
    let(:currency) { 'ZZZ' }
    it_behaves_like 'a rejected request with no side effects'
  end

  context 'when wallet does not exist' do
    let(:wallet_id) { 0 }
    it_behaves_like 'a rejected request with no side effects'
  end
end
```
