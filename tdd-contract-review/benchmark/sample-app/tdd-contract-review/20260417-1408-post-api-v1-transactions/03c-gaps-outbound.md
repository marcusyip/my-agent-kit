# Outbound API Gap Analysis — POST /api/v1/transactions → PaymentGateway.charge

**Contract Type:** Outbound API (SDK boundary — no HTTP URL present in codebase; `PaymentGateway.charge` is the boundary)
**Triggered by:** `transaction.category == 'payment'` — invoked synchronously from `TransactionService#charge_payment_gateway` (line 78) AND `Transaction#notify_payment_gateway` after_create callback (model line 28) — **dual call paths**
**Boundary file in test scope:** `spec/requests/api/v1/transactions_spec.rb`
**Fintech mode:** yes

---

## Test Structure Tree (Outbound API)

```
POST /api/v1/transactions → PaymentGateway.charge(amount:, currency:, user_id:, transaction_id:)
│
├── outbound response field: PaymentGateway.charge.success? (input — mock return) — NO TESTS
│   ├── ✗ success? returns true (category='payment') → 201, db transaction.status='completed', wallet.balance decremented, response transaction.status='completed'
│   ├── ✗ success? returns false (category='payment') → 422 or transaction.status='failed', no wallet.balance change beyond what service flow did, no data leak
│   ├── ✗ success? returns non-boolean truthy (e.g. "yes", 1, {}) → must not silently coerce to completed; assert system behavior (accept or reject)
│   ├── ✗ success? returns nil → transaction.status not left in inconsistent 'pending', no data leak
│   ├── ✗ upstream response object is nil → NoMethodError not leaked in 500; controller returns 422 or handles gracefully
│   ├── ✗ upstream response missing .success? method (wrong shape) → not silently passes; 422 with generic error
│   ├── ✗ partial response: success?=true but no transaction reference/id field parsed → flag as reconciliation gap (source does not parse reference today)
│   └── ✗ upstream amount/currency mismatch in response (if parsed) — source does not parse; flag as gap [FINTECH]
│
├── outbound response field: PaymentGateway::ChargeError (input — mock raises) — NO TESTS
│   ├── ✗ ChargeError raised (category='payment') → 422, response error='Payment processing failed', no completed status in DB, no data leak
│   ├── ✗ ChargeError raised → db transaction.status NOT 'completed' (stays 'pending' or set to 'failed' per service flow)
│   ├── ✗ ChargeError raised → wallet.balance side effects consistent with service flow (no orphan debit)
│   └── ✗ ChargeError raised → response body does not leak gateway internals / stack trace
│
├── outbound response field: timeout / network error (input — mock raises Timeout::Error, Net::ReadTimeout, etc.) — NO TESTS
│   └── ✗ timeout/network error NOT modeled in source; no rescue beyond ChargeError → unhandled exception escapes to 500, leaking class name; assert explicit handling or flag as GAP [FINTECH HIGH]
│
├── outbound request field: amount (assertion — must be sent correctly) — NO TESTS
│   ├── ✗ called with amount equal to transaction.amount (BigDecimal/decimal, not string) — happy path payment category
│   ├── ✗ called with correct amount when amount has fractional scale (e.g. 10.12345678) — precision preserved
│   └── ✗ type correctness: amount argument is Decimal/BigDecimal, not String coerced from params
│
├── outbound request field: currency (assertion — must be sent correctly) — NO TESTS
│   └── ✗ called with currency equal to transaction.currency — happy path payment category
│
├── outbound request field: user_id (assertion — must be sent correctly) — NO TESTS
│   └── ✗ called with user_id equal to current_user.id (not params-forgeable) — happy path payment category
│
├── outbound request field: transaction_id (assertion — must be sent correctly) — NO TESTS
│   ├── ✗ called with transaction_id equal to the created Transaction.id — happy path payment category
│   └── ✗ transaction_id references a persisted row (transaction.id is not nil — charge happens after create)
│
├── outbound call-count: invoked exactly ONCE on payment category — NO TESTS [FINTECH CRITICAL]
│   ├── ✗ category='payment' happy path → PaymentGateway.charge received exactly 1 time (NOT 2)
│   └── ✗ source has dual call paths (TransactionService#charge_payment_gateway line 78 + Transaction#notify_payment_gateway after_create line 28) — double-charge risk; test must pin call count to 1
│
├── outbound call-count: invoked ZERO times on non-payment categories — NO TESTS
│   ├── ✗ category='transfer' → PaymentGateway.charge NOT called
│   ├── ✗ category='deposit' → PaymentGateway.charge NOT called
│   ├── ✗ category='withdrawal' → PaymentGateway.charge NOT called
│   └── ✗ category omitted (defaults to 'transfer') → PaymentGateway.charge NOT called
│
├── outbound call-count: invoked ZERO times when request validation fails — NO TESTS
│   ├── ✗ amount nil (422) → PaymentGateway.charge NOT called
│   ├── ✗ amount negative / zero / >max / non-numeric (422) → PaymentGateway.charge NOT called
│   ├── ✗ currency nil / invalid / empty (422) → PaymentGateway.charge NOT called
│   ├── ✗ wallet_id not found / foreign wallet (422) → PaymentGateway.charge NOT called
│   ├── ✗ description > 500 chars (422) → PaymentGateway.charge NOT called
│   ├── ✗ category invalid (422) → PaymentGateway.charge NOT called
│   ├── ✗ wallet.status = suspended/closed (422) → PaymentGateway.charge NOT called
│   ├── ✗ wallet.currency mismatch (422) → PaymentGateway.charge NOT called
│   ├── ✗ wallet.balance insufficient (422) → PaymentGateway.charge NOT called
│   └── ✗ Authorization header missing (401) → PaymentGateway.charge NOT called
│
└── outbound call: idempotency key (assertion) — NO TESTS [FINTECH HIGH]
    └── ✗ PaymentGateway.charge does NOT receive an idempotency key today — source does not pass one; flag as gap; retries/duplicates may double-charge upstream
```

---

## Contract Map (Outbound API)

| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
|---|---|---|---|---|---|
| outbound response field | PaymentGateway.charge.success? | Input (mock return) | 8 (true, false, non-bool truthy, nil, nil response, missing method, partial/no reference, amount/currency mismatch) | 0 | 8 |
| outbound response field | PaymentGateway::ChargeError | Input (mock raises) | 4 (response body, db status, wallet side effect, no leak) | 0 | 4 |
| outbound response field | timeout / network error | Input (mock raises) | 1 (unhandled — flag source gap) | 0 | 1 |
| outbound request field | amount | Assertion | 3 (value match, fractional precision, type Decimal not String) | 0 | 3 |
| outbound request field | currency | Assertion | 1 (value match) | 0 | 1 |
| outbound request field | user_id | Assertion | 1 (value match current_user.id) | 0 | 1 |
| outbound request field | transaction_id | Assertion | 2 (value match, references persisted row) | 0 | 2 |
| outbound call-count | exactly once on payment | Assertion | 1 (CRITICAL — double-charge risk from dual call paths) | 0 | 1 |
| outbound call-count | zero on non-payment categories | Assertion | 4 (transfer, deposit, withdrawal, default) | 0 | 4 |
| outbound call-count | zero on validation failure | Assertion | 10 (all 422/401 scenarios) | 0 | 10 |
| outbound call | idempotency key | Assertion | 1 (absent in source — flag) | 0 | 1 |

**Total outbound scenarios required:** 36
**Scenarios covered:** 0
**Gap count:** 36

---

## Gap List

### GOUT-001 — PaymentGateway.charge invoked exactly ONCE per payment transaction [FINTECH CRITICAL]

- **priority:** CRITICAL
- **field:** `outbound call-count: PaymentGateway.charge` (exactly once on category='payment')
- **type:** Outbound API
- **description:** Source has TWO call paths to `PaymentGateway.charge`: `TransactionService#charge_payment_gateway` (line 78) and `Transaction#notify_payment_gateway` after_create callback (model line 28). For category='payment', the gateway is charged twice per request — customers are double-charged. No test pins the call count to exactly 1. Must assert `have_received(:charge).once` on happy path with category='payment'.
- **stub:** REQUIRED (see Test Stubs)

### GOUT-002 — success?=true on payment category → transaction.status='completed' and completion flow [HIGH]

- **priority:** HIGH
- **field:** `outbound response field: PaymentGateway.charge.success?` (input=true)
- **type:** Outbound API
- **description:** No test stubs `PaymentGateway.charge` to return `double(success?: true)` on a `category='payment'` request and asserts the downstream contract: (1) response 201, (2) db `transaction.status == 'completed'`, (3) response body `transaction.status == 'completed'`, (4) wallet.balance decremented once. This is the core happy path for the payment branch and it is entirely absent from the request spec.
- **stub:** REQUIRED

### GOUT-003 — success?=false on payment category → transaction.status='failed', error surfaced [HIGH]

- **priority:** HIGH
- **field:** `outbound response field: PaymentGateway.charge.success?` (input=false)
- **type:** Outbound API
- **description:** No test stubs gateway to return `double(success?: false)` on payment category. Must assert: response status (422 or 201 per contract — pin current behavior), db `transaction.status == 'failed'` (per TransactionService flow), no data leak in error body.
- **stub:** REQUIRED

### GOUT-004 — PaymentGateway::ChargeError raised → 422 + "Payment processing failed" + no completed state [HIGH]

- **priority:** HIGH
- **field:** `outbound response field: PaymentGateway::ChargeError`
- **type:** Outbound API
- **description:** No test raises `PaymentGateway::ChargeError` from the mock. Must assert: (1) response 422, (2) response error message equals `"Payment processing failed"` (per source), (3) db `transaction.status != 'completed'`, (4) no gateway internals/stack trace leaked in body.
- **stub:** REQUIRED

### GOUT-005 — outbound request field: amount sent correctly [HIGH]

- **priority:** HIGH
- **field:** `outbound request field: amount`
- **type:** Outbound API
- **description:** No test verifies the amount argument sent to `PaymentGateway.charge`. Must assert `have_received(:charge).with(hash_including(amount: BigDecimal('100.00')))` on payment happy path. Fractional-scale variant also missing (e.g. `10.12345678`).
- **stub:** REQUIRED

### GOUT-006 — outbound request field: currency sent correctly [HIGH]

- **priority:** HIGH
- **field:** `outbound request field: currency`
- **type:** Outbound API
- **description:** No test verifies the currency argument sent to `PaymentGateway.charge`. Must assert `have_received(:charge).with(hash_including(currency: 'USD'))` (or whatever default) on payment happy path.
- **stub:** REQUIRED

### GOUT-007 — outbound request field: user_id sent correctly (not forgeable) [HIGH]

- **priority:** HIGH
- **field:** `outbound request field: user_id`
- **type:** Outbound API
- **description:** No test verifies user_id is taken from `current_user.id` (authenticated identity), not from params. Must assert `have_received(:charge).with(hash_including(user_id: user.id))`.
- **stub:** REQUIRED

### GOUT-008 — outbound request field: transaction_id sent correctly (references persisted row) [HIGH]

- **priority:** HIGH
- **field:** `outbound request field: transaction_id`
- **type:** Outbound API
- **description:** No test verifies that the transaction_id sent to the gateway matches the id of the Transaction row just created (non-nil — persisted before call). Must assert `have_received(:charge).with(hash_including(transaction_id: Transaction.last.id))`.
- **stub:** REQUIRED

### GOUT-009 — PaymentGateway.charge NOT called on non-payment categories [HIGH]

- **priority:** HIGH
- **field:** `outbound call-count: zero on non-payment categories`
- **type:** Outbound API
- **description:** No test asserts that `category='transfer' | 'deposit' | 'withdrawal' | omitted` does NOT invoke `PaymentGateway.charge`. Without this, a regression that extends the gateway call to all categories would pass silently.
- **stub:** REQUIRED

### GOUT-010 — PaymentGateway.charge NOT called on validation failures (422 / 401) [HIGH]

- **priority:** HIGH
- **field:** `outbound call-count: zero on validation failure`
- **type:** Outbound API
- **description:** No error-scenario test asserts `expect(PaymentGateway).not_to have_received(:charge)`. Every 422/401 path (amount invalid, currency invalid, wallet not found, wallet suspended/closed, insufficient balance, currency mismatch, description too long, missing auth) should assert no outbound call.
- **stub:** REQUIRED

### GOUT-011 — Idempotency key absent on outbound charge [FINTECH HIGH]

- **priority:** HIGH
- **field:** `outbound call: idempotency key`
- **type:** Outbound API
- **description:** `PaymentGateway.charge` is called with NO idempotency key (e.g. `idempotency_key: transaction.id.to_s`). On retry or the existing dual-call-path bug, the upstream gateway cannot dedupe. Source-level gap — add the key, then test it is passed consistently and stable per transaction.
- **stub:** REQUIRED

### GOUT-012 — Timeout / network error handling missing in source [FINTECH HIGH]

- **priority:** HIGH
- **field:** `outbound response field: timeout / network error`
- **type:** Outbound API
- **description:** Source only rescues `PaymentGateway::ChargeError`. `Timeout::Error`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, SocketError are not rescued — they bubble to a 500 and leak exception class names. Source-level gap; test must either lock current behavior (500) or drive a fix to graceful 422/503 and then pin.
- **stub:** REQUIRED

### GOUT-013 — Malformed upstream response: nil object / missing .success? method [MEDIUM]

- **priority:** MEDIUM
- **field:** `outbound response field: PaymentGateway.charge.success?` (malformed)
- **type:** Outbound API
- **description:** No test for `PaymentGateway.charge` returning `nil` or an object without `.success?`. Current source calls `.success?` unconditionally — would raise `NoMethodError`, 500, leak class name. Test must drive graceful handling.
- **stub:** Not required (MEDIUM)

### GOUT-014 — Partial / missing upstream reference (reconciliation risk) [MEDIUM]

- **priority:** MEDIUM
- **field:** `outbound response field: PaymentGateway.charge` (no external reference parsed)
- **type:** Outbound API
- **description:** Source does not parse a gateway `transaction_id`/reference from the response. Reconciliation between internal transaction and upstream charge is impossible. Source-level gap — add a reference field on transactions, persist it after successful charge, test that happy path persists a non-nil reference.
- **stub:** Not required (MEDIUM)

### GOUT-015 — Amount/currency tampering in upstream response (mismatch) [MEDIUM]

- **priority:** MEDIUM
- **field:** `outbound response field: PaymentGateway.charge` (amount/currency mismatch)
- **type:** Outbound API
- **description:** Source does not parse/compare returned amount/currency. A gateway that reports a different amount than requested is silently accepted. Source-level gap.
- **stub:** Not required (MEDIUM)

### GOUT-016 — Non-boolean truthy from success? (type correctness) [LOW]

- **priority:** LOW
- **field:** `outbound response field: PaymentGateway.charge.success?` (non-boolean)
- **type:** Outbound API
- **description:** If `success?` returns `"yes"` or `1`, Ruby truthiness would accept it as completed. Test should pin expected types.
- **stub:** Not required (LOW)

---

## Test Stubs

All stubs use RSpec pseudocode inside `spec/requests/api/v1/transactions_spec.rb` (or the split-out `post_transactions_spec.rb`) with the standard foundation (`subject(:run_test)`, `let(:params)`, `let!(:db_wallet)`, `let(:user)`, `let(:headers) { auth_headers(user) }`).

### Stub for GOUT-001 — exactly once per payment transaction [FINTECH CRITICAL]

```ruby
context 'outbound PaymentGateway.charge call count (category=payment)' do
  let(:category) { 'payment' }
  let(:params)   { base_params.merge(category: category) }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'invokes PaymentGateway.charge exactly once per request' do
    run_test
    expect(PaymentGateway).to have_received(:charge).once
    # Regression guard: dual call paths (service#charge_payment_gateway + model after_create)
    # would cause this to fail with .twice.
  end
end
```

### Stub for GOUT-002 — success?=true happy path

```ruby
context 'when PaymentGateway.charge returns success?=true (category=payment)' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'returns 201 and marks transaction completed' do
    run_test
    expect(response).to have_http_status(:created)

    body = JSON.parse(response.body)
    expect(body['transaction']['status']).to eq('completed')

    db_txn = Transaction.last
    expect(db_txn.status).to eq('completed')
    expect(db_txn.category).to eq('payment')

    expect(db_wallet.reload.balance).to eq(initial_balance - BigDecimal(params[:amount]))
  end
end
```

### Stub for GOUT-003 — success?=false failure path

```ruby
context 'when PaymentGateway.charge returns success?=false (category=payment)' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
  end

  it 'marks transaction failed and does not leak gateway internals' do
    run_test
    db_txn = Transaction.last
    expect(db_txn.status).to eq('failed')

    # No gateway internals leaked
    body = JSON.parse(response.body)
    expect(body.to_s).not_to match(/PaymentGateway|stacktrace|ruby/i)
  end
end
```

### Stub for GOUT-004 — ChargeError rescued

```ruby
context 'when PaymentGateway.charge raises ChargeError (category=payment)' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge)
      .and_raise(PaymentGateway::ChargeError.new('upstream declined'))
  end

  it 'returns 422 with generic error and does not mark completed' do
    run_test
    expect(response).to have_http_status(:unprocessable_entity)

    body = JSON.parse(response.body)
    expect(body['error']).to eq('Payment processing failed')
    expect(body.to_s).not_to include('upstream declined') # no leak of gateway detail

    expect(Transaction.last.status).not_to eq('completed')
  end
end
```

### Stub for GOUT-005 — outbound amount sent correctly

```ruby
context 'outbound request field: amount' do
  let(:params) { base_params.merge(category: 'payment', amount: '100.00') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends amount as BigDecimal matching transaction.amount' do
    run_test
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(amount: BigDecimal('100.00')))
  end

  context 'with fractional scale (8 decimals)' do
    let(:params) { base_params.merge(category: 'payment', amount: '10.12345678') }

    it 'preserves full decimal precision' do
      run_test
      expect(PaymentGateway).to have_received(:charge)
        .with(hash_including(amount: BigDecimal('10.12345678')))
    end
  end
end
```

### Stub for GOUT-006 — outbound currency sent correctly

```ruby
context 'outbound request field: currency' do
  let(:params) { base_params.merge(category: 'payment', currency: 'USD') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends currency matching transaction.currency' do
    run_test
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(currency: 'USD'))
  end
end
```

### Stub for GOUT-007 — outbound user_id sent correctly

```ruby
context 'outbound request field: user_id' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends user_id from current_user.id (not forgeable via params)' do
    run_test
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(user_id: user.id))
  end
end
```

### Stub for GOUT-008 — outbound transaction_id sent correctly

```ruby
context 'outbound request field: transaction_id' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends transaction_id referring to the persisted Transaction row' do
    run_test
    created = Transaction.last
    expect(created.id).not_to be_nil
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(transaction_id: created.id))
  end
end
```

### Stub for GOUT-009 — zero calls on non-payment categories

```ruby
%w[transfer deposit withdrawal].each do |non_payment_category|
  context "outbound call-count: zero when category=#{non_payment_category}" do
    let(:params) { base_params.merge(category: non_payment_category) }

    before { allow(PaymentGateway).to receive(:charge) }

    it 'does not call PaymentGateway.charge' do
      run_test
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end
end

context 'outbound call-count: zero when category omitted (defaults to transfer)' do
  let(:params) { base_params.except(:category) }

  before { allow(PaymentGateway).to receive(:charge) }

  it 'does not call PaymentGateway.charge' do
    run_test
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### Stub for GOUT-010 — zero calls on validation failure

```ruby
shared_examples 'does not call PaymentGateway' do
  before { allow(PaymentGateway).to receive(:charge) }

  it 'does not invoke the outbound gateway' do
    run_test
    expect(PaymentGateway).not_to have_received(:charge)
  end
end

context 'when amount is nil (422)' do
  let(:params) { base_params.merge(category: 'payment', amount: nil) }
  include_examples 'does not call PaymentGateway'
end

context 'when currency is invalid (422)' do
  let(:params) { base_params.merge(category: 'payment', currency: 'ZZZ') }
  include_examples 'does not call PaymentGateway'
end

context 'when wallet is not owned by user (422)' do
  let(:other_user_wallet) { create(:wallet) }
  let(:params) { base_params.merge(category: 'payment', wallet_id: other_user_wallet.id) }
  include_examples 'does not call PaymentGateway'
end

context 'when wallet.status is suspended (422)' do
  before { db_wallet.update!(status: 'suspended') }
  let(:params) { base_params.merge(category: 'payment') }
  include_examples 'does not call PaymentGateway'
end

context 'when wallet.balance is insufficient (422)' do
  before { db_wallet.update!(balance: 0) }
  let(:params) { base_params.merge(category: 'payment', amount: '100') }
  include_examples 'does not call PaymentGateway'
end

context 'when Authorization header is missing (401)' do
  let(:headers) { {} }
  let(:params)  { base_params.merge(category: 'payment') }
  include_examples 'does not call PaymentGateway'
end
```

### Stub for GOUT-011 — idempotency key on outbound charge [FINTECH HIGH]

```ruby
context 'outbound idempotency key' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'passes a stable idempotency_key derived from transaction.id' do
    run_test
    created = Transaction.last
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(idempotency_key: created.id.to_s))
    # NOTE: currently failing — source does not pass idempotency_key.
    # Fix the source (TransactionService#charge_payment_gateway), then this test locks the contract.
  end
end
```

### Stub for GOUT-012 — timeout / network error handling [FINTECH HIGH]

```ruby
context 'when PaymentGateway.charge raises Timeout::Error' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_raise(Timeout::Error)
  end

  it 'returns a controlled error, not a 500 leaking internals' do
    run_test
    # Current behavior: unhandled -> 500. Fix source to rescue and map to 422/503.
    expect(response.status).to be_in([422, 503])
    body = JSON.parse(response.body)
    expect(body.to_s).not_to match(/Timeout::Error|backtrace|\/gems\//)
    expect(Transaction.last.status).not_to eq('completed')
  end
end

context 'when PaymentGateway.charge raises Errno::ECONNREFUSED' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_raise(Errno::ECONNREFUSED)
  end

  it 'returns a controlled error, not a 500 leaking internals' do
    run_test
    expect(response.status).to be_in([422, 503])
    expect(Transaction.last.status).not_to eq('completed')
  end
end
```

---

## Summary

- **Total gaps:** 16 (1 CRITICAL, 10 HIGH, 4 MEDIUM, 1 LOW)
- **Stubs provided:** 12 (for CRITICAL + all HIGH)
- **Source-level defects surfaced by this analysis:**
  - Dual call paths to `PaymentGateway.charge` (double-charge) — **GOUT-001 CRITICAL**
  - No idempotency key sent upstream — **GOUT-011 FINTECH HIGH**
  - No timeout / network error handling — **GOUT-012 FINTECH HIGH**
  - No external reference parsed for reconciliation — **GOUT-014 MEDIUM**
  - No upstream amount/currency mismatch detection — **GOUT-015 MEDIUM**
- **Existing outbound coverage in `spec/requests/api/v1/transactions_spec.rb`:** 0 scenarios. The only `PaymentGateway` stub in the codebase lives in the non-boundary `spec/services/transaction_service_spec.rb` and asserts an internal method dispatch, not the outbound contract.
