## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/services/transaction_service.rb, app/models/transaction.rb
**Framework:** Rails 7.1 / RSpec (request spec)
**Fintech mode:** Enabled (money/amount/balance fields, payment gateway, decimal types, wallet/transaction models)

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every API endpoint, job, and message consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `✓` = scenario is tested
- `✗` = scenario is missing (potential silent breakage)
- Each entry point (endpoint, job, consumer) gets its own section
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**One endpoint per file:** Each API endpoint, job, or consumer should have its own test file. This makes gaps immediately visible — if a file doesn't exist, the entire contract is untested.

**Contract boundary:** Tests should verify behavior at the contract boundary (API endpoint, job entry point), not internal implementation. Testing that a service method is called is implementation testing — testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have. A codebase with 100 tests that only check status codes scores lower than one with 20 tests that verify response fields, DB state, and error paths.

### Overall Score: 4.0 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 8/10 | 15% | 1.20 |
| Anti-Patterns | 4/10 | 10% | 0.40 |
| **Overall** | | | **4.00** |

### Verdict: NEEDS IMPROVEMENT

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb
        db/migrate/003_create_transactions.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):
  POST /api/v1/transactions
    Request params:
      - amount (decimal, required) [HIGH confidence]
      - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max 500 chars) [HIGH confidence]
      - category (string, optional, defaults to 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string — decimal.to_s) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
      - updated_at (string, ISO8601) [HIGH confidence]
    Error response fields:
      - error (string) [HIGH confidence]
      - details (array of strings) [HIGH confidence]
    Status codes: 201, 422, 401

  GET /api/v1/transactions/:id
    Request params:
      - id (integer, path param, required) [HIGH confidence]
    Response fields:
      - transaction (object, same shape as POST response) [HIGH confidence]
    Error response: { error: 'Transaction not found' }
    Status codes: 200, 404, 401

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [HIGH confidence]
      - per_page (integer, optional, default 25) [HIGH confidence]
    Response fields:
      - transactions (array of transaction objects) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200, 401

DB Contract:
  Transaction model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - status (string, NOT NULL, default 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable, max 500) [HIGH confidence]
    - category (string, NOT NULL, default 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (triggered when category=payment):
    Request:
      - amount (decimal) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - user_id (integer) [HIGH confidence]
      - transaction_id (integer) [HIGH confidence]
    Expected response: object with success? method [MEDIUM confidence]
    Error: PaymentGateway::ChargeError [HIGH confidence]
    Side effects:
      - On success: transaction.status → 'completed' [HIGH confidence]
      - On failure: transaction.status → 'failed' [HIGH confidence]

Business Rules:
  - Wallet must exist and belong to current_user [HIGH confidence]
  - Wallet must be active (not suspended/closed) [HIGH confidence]
  - Currency must match wallet currency [HIGH confidence]
  - Amount must be > 0 and <= 1,000,000 [HIGH confidence]
  - authenticate_user! on all endpoints [HIGH confidence]

Fintech Dimensions:
  Money & Precision:
    - amount: decimal(20,8), exact type ✓ [HIGH confidence]
    - Validation: greater_than: 0, less_than_or_equal_to: 1_000_000 [HIGH confidence]
    - Currency pairing: amount always paired with currency field [HIGH confidence]
  Idempotency:
    - No idempotency key on POST /api/v1/transactions [HIGH confidence — MISSING]
  Transaction State Machine:
    - Enum values: pending, completed, failed, reversed [HIGH confidence]
    - Transitions: pending → completed (on gateway success), pending → failed (on gateway failure) [HIGH confidence]
    - Terminal states: completed, failed, reversed (inferred, no explicit guard) [MEDIUM confidence]
    - No explicit state machine gem or transition guards [HIGH confidence]
  Concurrency:
    - No locking in TransactionService on transaction creation [HIGH confidence]
    - No duplicate transaction prevention [HIGH confidence]
  Security:
    - authenticate_user! before all actions [HIGH confidence]
    - Wallet scoped to current_user.wallets (IDOR protection on wallet) [HIGH confidence]
    - Transaction scoped to current_user.transactions (IDOR protection on show) [HIGH confidence]
============================
```

### Test Structure Tree

```
POST /api/v1/transactions
├── happy path
│   └── ✓ returns 201 (status only — NO response body assertions, NO DB assertions)
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero (boundary) → should be 422 (greater_than: 0)
│   ├── ✗ exactly 1,000,000 (max boundary) → should be 201
│   ├── ✗ over 1,000,000 → 422
│   ├── ✗ non-numeric string → 422
│   └── ✗ precision overflow (e.g. 100.123456789) → behavior? [FINTECH]
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ currency mismatch with wallet → 422
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   ├── ✗ belongs to another user → 422 [FINTECH: IDOR]
│   ├── ✗ wallet suspended → 422
│   └── ✗ wallet closed → 422
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length 500 → should succeed
│   └── ✗ over max length 501 → 422
├── field: category (request param) — NO TESTS
│   ├── ✗ nil (defaults to 'transfer')
│   ├── ✗ each valid value (transfer, payment, deposit, withdrawal)
│   └── ✗ invalid value → 422
├── response body — NO ASSERTIONS
│   └── ✗ happy path should assert all 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
├── DB assertions — NO ASSERTIONS
│   └── ✗ happy path should assert Transaction created with correct field values
├── external: PaymentGateway.charge — NO TESTS
│   ├── ✗ category=payment, gateway success → transaction status 'completed'
│   ├── ✗ category=payment, gateway failure → transaction status 'failed'
│   ├── ✗ category=payment, ChargeError → 422
│   └── ✗ category=payment, gateway timeout → 422
├── [FINTECH] state machine — NO TESTS
│   ├── ✗ new transaction starts as 'pending'
│   ├── ✗ pending → completed (valid transition)
│   ├── ✗ pending → failed (valid transition)
│   ├── ✗ completed → pending (invalid, must reject)
│   └── ✗ reversed state behavior
├── [FINTECH] idempotency — MISSING INFRASTRUCTURE
│   └── ✗ no idempotency key on mutating financial endpoint
├── [FINTECH] security
│   ├── ✗ unauthenticated request → 401
│   └── ✗ accessing another user's wallet → 422/403
└── [FINTECH] concurrency — NO TESTS
    └── ✗ double-submit prevention (two rapid identical POSTs)

GET /api/v1/transactions/:id
├── ✓ returns 200 (status only — NO response body assertions)
├── ✓ not found → 404
├── response body — NO ASSERTIONS
│   └── ✗ should assert all transaction fields
├── [FINTECH] security
│   ├── ✗ unauthenticated → 401
│   └── ✗ another user's transaction → 404 (IDOR test)
└── field: id
    └── ✗ non-numeric id → behavior?

GET /api/v1/transactions
├── ✓ returns 200 (status only)
├── response body — NO ASSERTIONS
│   ├── ✗ should assert transactions array shape
│   ├── ✗ should assert meta.total, meta.page, meta.per_page
│   └── ✗ should assert ordering (created_at desc)
├── pagination — NO TESTS
│   ├── ✗ page param → correct page returned
│   ├── ✗ per_page param → correct limit
│   └── ✗ default per_page = 25
├── [FINTECH] security
│   ├── ✗ unauthenticated → 401
│   └── ✗ only returns current user's transactions (not other users')
└── filtering
    └── ✗ scoped to current_user only
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | HIGH: zero, max boundary, over-max, non-numeric, precision overflow |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value, wallet mismatch |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | HIGH: another user's wallet (IDOR), suspended wallet, closed wallet |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: untested (nil, max length, over-max) |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: untested (nil/default, each valid value, invalid) |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | currency | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | status | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | category | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | wallet_id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | created_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | updated_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (error) | error | HIGH | No | -- | HIGH: untested (error message content) |
| POST /transactions (error) | details | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | user_id | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | wallet_id | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | amount | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | currency | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | status | HIGH | No | -- | HIGH: no DB assertion, no state transitions tested |
| Transaction (DB) | description | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | category | HIGH | No | -- | HIGH: no DB assertion, default 'transfer' untested |
| PaymentGateway.charge (outbound) | amount | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | currency | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | success response | MEDIUM | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | failure response | MEDIUM | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | ChargeError | HIGH | No | -- | HIGH: untested |
| GET /transactions/:id (response) | transaction object | HIGH | No | -- | HIGH: no body assertions |
| GET /transactions/:id (error) | error message | HIGH | Partial | 404 status only | MEDIUM: error body content untested |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: no shape assertion |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: untested |
| GET /transactions (request) | page | HIGH | No | -- | HIGH: untested |
| GET /transactions (request) | per_page | HIGH | No | -- | HIGH: untested |
| [FINTECH] Idempotency | idempotency key | HIGH | No | -- | HIGH: no idempotency key exists |
| [FINTECH] State Machine | pending→completed | HIGH | No | -- | HIGH: untested transition |
| [FINTECH] State Machine | pending→failed | HIGH | No | -- | HIGH: untested transition |
| [FINTECH] State Machine | invalid transitions | HIGH | No | -- | HIGH: untested |
| [FINTECH] Concurrency | double-submit | HIGH | No | -- | HIGH: untested |
| [FINTECH] Security | auth required | HIGH | No | -- | HIGH: no 401 test on any endpoint |
| [FINTECH] Security | IDOR (wallet) | HIGH | No | -- | HIGH: no ownership test |
| [FINTECH] Security | IDOR (transaction show) | HIGH | No | -- | HIGH: no ownership test |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 28 gaps)

- [ ] `POST /api/v1/transactions` happy path — no response body assertions. The happy path only checks status 201. All 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at) are unverified.

Suggested test:
```ruby
context 'happy path' do
  it 'returns 201 with correct response fields' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    txn = body['transaction']
    expect(txn['amount']).to eq('100.5')
    expect(txn['currency']).to eq('USD')
    expect(txn['status']).to eq('pending')
    expect(txn['description']).to be_nil
    expect(txn['category']).to eq('transfer')
    expect(txn['wallet_id']).to eq(wallet.id)
    expect(txn).to have_key('id')
    expect(txn).to have_key('created_at')
    expect(txn).to have_key('updated_at')
  end
end
```

- [ ] `POST /api/v1/transactions` happy path — no DB state assertions. No test verifies that a Transaction record is created with correct field values.

Suggested test:
```ruby
context 'happy path' do
  it 'creates a Transaction with correct attributes' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.to change(Transaction, :count).by(1)

    txn = Transaction.last
    expect(txn.user_id).to eq(user.id)
    expect(txn.wallet_id).to eq(wallet.id)
    expect(txn.amount).to eq(BigDecimal('100.50'))
    expect(txn.currency).to eq('USD')
    expect(txn.status).to eq('pending')
    expect(txn.category).to eq('transfer')
  end
end
```

- [ ] `POST /api/v1/transactions` request field `description` — no tests at all for this optional field

Suggested test:
```ruby
context 'when description is provided' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        description: 'Test payment'
      }
    }
  end

  it 'persists description' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    expect(Transaction.last.description).to eq('Test payment')
  end
end

context 'when description exceeds 500 characters' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        description: 'a' * 501
      }
    }
  end

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `POST /api/v1/transactions` request field `category` — no tests at all for this field (defaults to 'transfer', enum: transfer/payment/deposit/withdrawal)

Suggested test:
```ruby
context 'when category is nil' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        category: nil
      }
    }
  end

  it 'defaults to transfer' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    expect(Transaction.last.category).to eq('transfer')
  end
end

context 'when category is invalid' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        category: 'invalid'
      }
    }
  end

  it 'returns 422' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `POST /api/v1/transactions` request field `wallet_id` — no test for another user's wallet (IDOR vulnerability)

Suggested test:
```ruby
context 'when wallet belongs to another user' do
  let(:other_user) { create(:user) }
  let(:other_wallet) { create(:wallet, user: other_user, currency: 'USD') }
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: other_wallet.id
      }
    }
  end

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `POST /api/v1/transactions` business rule — wallet must be active. No tests for suspended or closed wallet.

Suggested test:
```ruby
context 'when wallet is suspended' do
  before { wallet.update!(status: 'suspended') }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'when wallet is closed' do
  before { wallet.update!(status: 'closed') }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `POST /api/v1/transactions` business rule — currency must match wallet currency

Suggested test:
```ruby
context 'when currency does not match wallet currency' do
  let(:currency) { 'EUR' }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['details']).to include('Currency must match wallet currency')
  end
end
```

- [ ] `POST /api/v1/transactions` request field `amount` — missing boundary tests (zero, max 1,000,000, over max)

Suggested test:
```ruby
context 'when amount is zero' do
  let(:amount) { '0' }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'when amount is exactly 1,000,000 (max boundary)' do
  let(:amount) { '1000000' }

  it 'returns 201' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
  end
end

context 'when amount exceeds 1,000,000' do
  let(:amount) { '1000001' }

  it 'returns 422' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `POST /api/v1/transactions` external API — PaymentGateway.charge not tested at all. No tests verify behavior when category=payment triggers the gateway call.

Suggested test:
```ruby
context 'when category is payment' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        category: 'payment'
      }
    }
  end

  context 'when gateway returns success' do
    before do
      allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
    end

    it 'creates transaction with completed status' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(Transaction.last.status).to eq('completed')
    end

    it 'calls PaymentGateway with correct params' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(PaymentGateway).to have_received(:charge).with(
        amount: BigDecimal('100.50'),
        currency: 'USD',
        user_id: user.id,
        transaction_id: Transaction.last.id
      )
    end
  end

  context 'when gateway returns failure' do
    before do
      allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
    end

    it 'creates transaction with failed status' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(Transaction.last.status).to eq('failed')
    end
  end

  context 'when gateway raises ChargeError' do
    before do
      allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError.new('Gateway timeout'))
    end

    it 'returns 422 with error details' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Payment processing failed')
    end
  end
end
```

- [ ] `GET /api/v1/transactions/:id` — no response body assertions. Test only checks status 200.

Suggested test:
```ruby
it 'returns the transaction with all fields' do
  get "/api/v1/transactions/#{transaction.id}", headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  txn = body['transaction']
  expect(txn['id']).to eq(transaction.id)
  expect(txn['amount']).to eq(transaction.amount.to_s)
  expect(txn['currency']).to eq(transaction.currency)
  expect(txn['status']).to eq(transaction.status)
  expect(txn['wallet_id']).to eq(transaction.wallet_id)
  expect(txn).to have_key('created_at')
  expect(txn).to have_key('updated_at')
end
```

- [ ] `GET /api/v1/transactions/:id` — no IDOR test. No test verifies that accessing another user's transaction returns 404.

Suggested test:
```ruby
context 'when transaction belongs to another user' do
  let(:other_user) { create(:user) }
  let(:other_wallet) { create(:wallet, user: other_user) }
  let(:other_transaction) { create(:transaction, user: other_user, wallet: other_wallet) }

  it 'returns 404' do
    get "/api/v1/transactions/#{other_transaction.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] `GET /api/v1/transactions` — no response shape assertions. No test verifies the transactions array, meta object, pagination, or ordering.

Suggested test:
```ruby
it 'returns transactions with correct shape and pagination meta' do
  create_list(:transaction, 3, user: user, wallet: wallet)
  get '/api/v1/transactions', headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  expect(body['transactions']).to be_an(Array)
  expect(body['transactions'].length).to eq(3)
  expect(body['meta']['total']).to eq(3)
  expect(body['meta']['page']).to eq(1)
  expect(body['meta']['per_page']).to eq(25)
end
```

- [ ] [FINTECH] Authentication — no test on any of the 3 endpoints verifies that unauthenticated requests return 401

Suggested test:
```ruby
context 'without authentication' do
  it 'POST returns 401' do
    post '/api/v1/transactions', params: { transaction: { amount: '100', currency: 'USD', wallet_id: 1 } }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'GET index returns 401' do
    get '/api/v1/transactions'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'GET show returns 401' do
    get '/api/v1/transactions/1'
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] [FINTECH] State machine — no tests verify transaction status transitions (pending→completed, pending→failed, invalid transitions like completed→pending)

- [ ] [FINTECH] Concurrency — no double-submit prevention test. Two rapid identical POSTs could create duplicate financial records.

**MEDIUM** (tested but missing important scenarios — 4 gaps)

- [ ] `POST /api/v1/transactions` field `currency` — missing empty string scenario
- [ ] `POST /api/v1/transactions` field `currency` — no test verifying each valid value (USD, EUR, GBP, BTC, ETH) is accepted
- [ ] `POST /api/v1/transactions` field `amount` — no test for non-numeric string
- [ ] `GET /api/v1/transactions/:id` error response — 404 test checks status only, not error body content

**LOW** (rare corner cases — 2 gaps)

- [ ] [FINTECH] `POST /api/v1/transactions` field `amount` — precision overflow test (amount with more than 8 decimal places)
- [ ] `GET /api/v1/transactions/:id` field `id` — non-numeric id handling

### Missing infrastructure

| Finding | Severity | Description |
|---|---|---|
| [FINTECH] No idempotency key | HIGH | POST /api/v1/transactions is a mutating financial endpoint with no idempotency key. Duplicate requests can create duplicate transactions. Consider adding an `idempotency_key` param with a unique DB constraint. |
| [FINTECH] No rate limiting | MEDIUM | No rate limiting detected on financial mutation endpoints. Consider adding to prevent brute-force or card testing attacks. |
| [FINTECH] No audit trail | MEDIUM | No audit trail table/fields for financial mutations. Financial operations should be auditable with actor, action, timestamp, IP, old/new values. |

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | transactions_spec.rb | MEDIUM | Split into post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb |
| Status-only assertions | transactions_spec.rb:32-35 | HIGH | Happy path must assert response body fields AND DB state |
| Status-only assertions (errors) | transactions_spec.rb:42-53, 59-71 | MEDIUM | Error tests should also assert no DB record created and no side effects |
| No test foundation | transactions_spec.rb | MEDIUM | Add DEFAULT_AMOUNT, DEFAULT_CURRENCY constants, subject(:run_test) helper |
| Implementation testing (service spec) | spec/services/transaction_service_spec.rb | HIGH | Delete — test TransactionService behavior through POST /api/v1/transactions instead. Service spec tests internal method calls (build_transaction, validate_wallet_active!, charge_payment_gateway) which is implementation testing. |

### Top 5 Priority Actions

1. **Add response body + DB assertions to POST happy path** — Currently the test only checks status 201. Add assertions for all 9 response fields and verify the Transaction record is persisted with correct values. This single change protects against silent response/persistence regressions.
2. **Add PaymentGateway integration tests** — The entire payment gateway flow (success, failure, ChargeError) is untested through the API. Mock PaymentGateway.charge and verify status transitions and error responses.
3. **Add IDOR tests for wallet_id (POST) and transaction show (GET)** — No test verifies that users cannot access other users' wallets or transactions. These are critical security gaps for a financial application.
4. **Add wallet state tests** — Suspended and closed wallet scenarios are untested through the API. The TransactionService validates wallet.active? but no request spec exercises this path.
5. **Split into one endpoint per file and add test foundation** — Restructure to post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb with DEFAULT constants and subject(:run_test) helper for consistent gap visibility.
