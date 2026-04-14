## TDD Contract Review: transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/models/transaction.rb, app/services/transaction_service.rb, app/models/wallet.rb
**Framework:** Rails 7.1 / RSpec (request spec)

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every API endpoint, job, and message consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `✓` = scenario is tested
- `✗` = scenario is missing (potential silent breakage)
- Each entry point (endpoint, job, consumer) gets its own section
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**One endpoint per file:** Each API endpoint, job, or consumer should have its own test file. This makes gaps immediately visible -- if a file doesn't exist, the entire contract is untested.

**Contract boundary:** Tests should verify behavior at the contract boundary (API endpoint, job entry point), not internal implementation. Testing that a service method is called is implementation testing -- testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have. A codebase with 100 tests that only check status codes scores lower than one with 20 tests that verify response fields, DB state, and error paths.

### Overall Score: 2.9 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 2/10 | 25% | 0.50 |
| Test Grouping | 3/10 | 15% | 0.45 |
| Scenario Depth | 2/10 | 20% | 0.40 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 2/10 | 10% | 0.20 |
| **Overall** | | | **2.90** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):
  POST /api/v1/transactions
    Request params:
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max: 500) [HIGH confidence]
      - category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string, decimal-as-string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string, nullable) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (datetime, ISO8601) [HIGH confidence]
      - updated_at (datetime, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401
    Auth: before_action :authenticate_user!

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [MEDIUM confidence]
      - per_page (integer, optional, default: 25) [MEDIUM confidence]
      - start_date (string, optional, date filter) [HIGH confidence]
      - end_date (string, optional, date filter) [HIGH confidence]
      - status (string, optional, filter) [HIGH confidence]
    Response fields:
      - transactions (array of transaction objects) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200, 401

  GET /api/v1/transactions/:id
    Request params:
      - id (integer, required) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string, nullable) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (datetime, ISO8601) [HIGH confidence]
      - updated_at (datetime, ISO8601) [HIGH confidence]
    Status codes: 200, 404, 401

DB Contract:
  Transaction model:
    - id (integer, PK, auto-increment) [HIGH confidence]
    - user_id (integer, NOT NULL, FK → users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK → wallets) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - status (string, NOT NULL, default: 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, NOT NULL, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]

  Business rules:
    - amount must be > 0 and <= 1_000_000 [HIGH confidence]
    - currency must be in USD/EUR/GBP/BTC/ETH [HIGH confidence]
    - currency must match wallet currency [HIGH confidence]
    - wallet must be active [HIGH confidence]
    - wallet balance >= amount (for non-deposit categories) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (when category == 'payment'):
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
    - Expected response: { success?: boolean } [HIGH confidence]
    - On success: status → completed [HIGH confidence]
    - On failure: status → failed [HIGH confidence]
    - On ChargeError: returns 422 [HIGH confidence]
============================
```

### Checkpoint 1 -- Contract Type Verification

| # | Contract Type | Status | Fields Found | Source Files Read |
|---|---------------|--------|-------------|-------------------|
| 1 | API (inbound) | Extracted | 30 | transactions_controller.rb |
| 2 | DB (models/schema) | Extracted | 10 | transaction.rb, 003_create_transactions.rb |
| 3 | Outbound API calls | Extracted | 4 | transaction_service.rb, transaction.rb |
| 4 | Jobs/consumers | Not applicable | -- | No job files in project |
| 5 | UI props | Not applicable | -- | Backend-only API project |

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | amount (decimal(20,8)), balance (decimal(20,8)), BigDecimal in service | 5 HIGH, 1 MEDIUM |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | status enum: pending/completed/failed/reversed | 2 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | wallet.balance, with_lock, balance >= amount check | 2 HIGH, 1 MEDIUM |
| 5 | External Payment Integrations | Extracted | PaymentGateway.charge | 3 HIGH |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | with_lock in wallet, TOCTOU in service | 2 HIGH |
| 8 | Security & Access Control | Extracted | authenticate_user!, current_user scoping | 4 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

---

### Test Structure Tree

```
POST /api/v1/transactions
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero (boundary) → 422 or success?
│   ├── ✗ max (1_000_000) → should succeed
│   ├── ✗ over max (1_000_001) → 422
│   ├── ✗ non-numeric string → 422
│   ├── ✗ exceeds available balance → 422 (balance-constrained)
│   ├── ✗ exactly equals balance → success, balance becomes zero
│   └── ✗ precision overflow (0.123456789 when schema is decimal(20,8))
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ mismatch with wallet currency → 422
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   └── ✗ another user's wallet → 422 (IDOR)
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length (500) → should succeed
│   └── ✗ over max length (501) → 422
├── field: category (request param) — NO TESTS
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal)
│   ├── ✗ invalid value → 422
│   └── ✗ nil (defaults to 'transfer')
├── response body — NO ASSERTIONS
│   └── ✗ happy path should assert all 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
├── DB assertions — NO ASSERTIONS
│   └── ✗ happy path should assert Transaction created with correct field values
├── business: wallet must be active — NO TESTS
│   ├── ✗ suspended wallet → 422
│   └── ✗ closed wallet → 422
├── business: currency must match wallet — NO TESTS
│   └── ✗ currency mismatch → 422
├── external: PaymentGateway.charge — NO TESTS
│   ├── ✗ category=payment, gateway success → status becomes completed
│   ├── ✗ category=payment, gateway failure → status becomes failed
│   └── ✗ category=payment, ChargeError → 422
├── fintech: balance validation — NO TESTS
│   ├── ✗ amount > wallet balance → 422
│   └── ✗ amount == wallet balance → success, balance becomes zero
├── fintech: state machine transitions — NO TESTS
│   ├── ✗ pending → completed (on payment gateway success)
│   ├── ✗ pending → failed (on payment gateway failure)
│   └── ✗ invalid transition (completed → pending) → rejected
├── fintech: error response data leak
│   └── ✗ InsufficientBalanceError details leak wallet balance ("Current balance: X, requested: Y")
├── security: authentication — NO TESTS
│   ├── ✗ missing auth token → 401
│   └── ✗ expired auth token → 401
├── security: IDOR — NO TESTS
│   └── ✗ wallet_id belonging to another user → 422/403
└── security: error response data — NO TESTS
    └── ✗ 422 response does not leak balance, internal IDs, or stack trace

GET /api/v1/transactions/:id
├── happy path
│   ├── ✓ returns 200
│   └── ✗ response body not asserted (should verify all 9 fields)
├── not found
│   └── ✓ returns 404
├── security: IDOR — NO TESTS
│   └── ✗ another user's transaction → 404
└── security: authentication — NO TESTS
    └── ✗ missing auth token → 401

GET /api/v1/transactions (index)
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response shape not asserted (transactions array, meta object)
│   └── ✗ ordering not verified (created_at desc)
├── field: page (pagination) — NO TESTS
│   ├── ✗ page=0 → rejected or default
│   ├── ✗ page=-1 → rejected
│   └── ✗ beyond last page → empty array
├── field: per_page (pagination) — NO TESTS
│   ├── ✗ per_page=0 → rejected or default
│   ├── ✗ very large (999999) → capped or rejected
│   └── ✗ default 25 when omitted
├── field: start_date (filter) — NO TESTS
│   ├── ✗ valid date → filters correctly
│   ├── ✗ invalid format → rejected or ignored
│   └── ✗ future date → empty results
├── field: end_date (filter) — NO TESTS
│   ├── ✗ valid date → filters correctly
│   └── ✗ invalid format → rejected or ignored
├── field: status (filter) — NO TESTS
│   ├── ✗ valid status → filters correctly
│   └── ✗ invalid status → rejected or all results
├── security: authentication — NO TESTS
│   └── ✗ missing auth token → 401
└── security: data isolation — NO TESTS
    └── ✗ only returns current user's transactions
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | HIGH: zero, max, over-max, non-numeric, exceeds balance, equals balance, precision overflow |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value, mismatch with wallet |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | HIGH: another user's wallet (IDOR) |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: untested (nil, max length, over-max) |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: untested (each value, invalid, nil default) |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | currency | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | status | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | description | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | category | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | wallet_id | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | created_at | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (response) | updated_at | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /transactions (DB) | Transaction created | HIGH | No | -- | HIGH: no DB assertion in happy path |
| POST /transactions (DB) | status enum | HIGH | No | -- | HIGH: pending/completed/failed/reversed transitions untested |
| POST /transactions (DB) | category enum | HIGH | No | -- | HIGH: transfer/payment/deposit/withdrawal untested |
| POST /transactions (business) | wallet active | HIGH | No | -- | HIGH: suspended/closed wallet untested |
| POST /transactions (business) | currency match | HIGH | No | -- | HIGH: mismatch untested |
| POST /transactions (business) | balance >= amount | HIGH | No | -- | HIGH: insufficient balance untested |
| PaymentGateway.charge (outbound) | amount | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | currency | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | user_id | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | response handling | HIGH | No | -- | HIGH: success/failure/error paths untested |
| GET /transactions/:id (response) | all fields | HIGH | No | -- | HIGH: response body not asserted |
| GET /transactions/:id (security) | IDOR | HIGH | No | -- | HIGH: another user's transaction not tested |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: response shape not asserted |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (request) | page | MEDIUM | No | -- | MEDIUM: pagination untested |
| GET /transactions (request) | per_page | MEDIUM | No | -- | MEDIUM: pagination untested |
| GET /transactions (request) | start_date | HIGH | No | -- | HIGH: date filter untested |
| GET /transactions (request) | end_date | HIGH | No | -- | HIGH: date filter untested |
| GET /transactions (request) | status | HIGH | No | -- | HIGH: status filter untested |
| Security | auth (all 3 endpoints) | HIGH | No | -- | HIGH: no auth tests at all |

### Checkpoint 2 -- Gap Analysis Verification

| # | Contract Type | Gaps Checked? | HIGH Gaps | MEDIUM Gaps | LOW Gaps |
|---|---------------|---------------|-----------|-------------|----------|
| 1 | API (inbound) | Yes | 21 | 4 | 0 |
| 2 | DB (models/schema) | Yes | 3 | 0 | 0 |
| 3 | Outbound API calls | Yes | 4 | 0 | 0 |

---

### Gap Analysis

#### HIGH Priority Gaps

**H1: POST /api/v1/transactions -- happy path does not assert response body**
No response field is verified. All 9 fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at) could return wrong values and tests would still pass.

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
    expect(txn['created_at']).to be_present
    expect(txn['updated_at']).to be_present
    expect(txn['id']).to be_a(Integer)
  end
end
```

**H2: POST /api/v1/transactions -- happy path does not assert DB state**
No assertion that a Transaction record is created with correct field values.

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

**H3: POST /api/v1/transactions -- `description` field completely untested**

Suggested test:
```ruby
context 'field: description' do
  let(:params) do
    {
      transaction: {
        amount: amount, currency: currency, wallet_id: wallet.id,
        description: description
      }
    }
  end
  let(:description) { nil }

  context 'when nil (optional)' do
    it 'succeeds with nil description' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
    end
  end

  context 'when at max length (500)' do
    let(:description) { 'a' * 500 }

    it 'succeeds' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
    end
  end

  context 'when over max length (501)' do
    let(:description) { 'a' * 501 }

    it 'returns 422 and does not create a transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

**H4: POST /api/v1/transactions -- `category` field completely untested**

Suggested test:
```ruby
context 'field: category' do
  let(:params) do
    {
      transaction: {
        amount: amount, currency: currency, wallet_id: wallet.id,
        category: category_value
      }
    }
  end

  context 'when nil (defaults to transfer)' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id } }
    end

    it 'creates transaction with transfer category' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(Transaction.last.category).to eq('transfer')
    end
  end

  %w[transfer payment deposit withdrawal].each do |valid_category|
    context "when #{valid_category}" do
      let(:category_value) { valid_category }

      it 'succeeds' do
        allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) if valid_category == 'payment'
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.category).to eq(valid_category)
      end
    end
  end

  context 'when invalid' do
    let(:category_value) { 'invalid_category' }

    it 'returns 422' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

**H5: POST /api/v1/transactions -- wallet belonging to another user (IDOR)**

Suggested test:
```ruby
context 'when wallet belongs to another user' do
  let(:other_user) { create(:user) }
  let(:other_wallet) { create(:wallet, user: other_user, currency: 'USD') }
  let(:params) do
    {
      transaction: {
        amount: amount, currency: currency, wallet_id: other_wallet.id
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

**H6: POST /api/v1/transactions -- suspended/closed wallet not tested**

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

**H7: POST /api/v1/transactions -- currency mismatch with wallet not tested**

Suggested test:
```ruby
context 'when currency does not match wallet currency' do
  let(:currency) { 'EUR' }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

**H8: POST /api/v1/transactions -- insufficient balance not tested [FINTECH]**

Suggested test:
```ruby
context 'when amount exceeds wallet balance' do
  let(:amount) { (wallet.balance + 1).to_s }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'when amount exactly equals wallet balance' do
  let(:amount) { wallet.balance.to_s }

  it 'succeeds and wallet balance becomes zero' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    expect(wallet.reload.balance).to eq(0)
  end
end
```

**H9: POST /api/v1/transactions -- PaymentGateway.charge completely untested [FINTECH]**

Suggested test:
```ruby
context 'when category is payment' do
  let(:params) do
    {
      transaction: {
        amount: amount, currency: currency, wallet_id: wallet.id,
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
        hash_including(amount: BigDecimal('100.50'), currency: 'USD')
      )
    end
  end

  context 'when gateway returns failure' do
    before do
      allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
    end

    it 'creates transaction with failed status' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(Transaction.last.status).to eq('failed')
    end
  end

  context 'when gateway raises ChargeError' do
    before do
      allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError, 'Card declined')
    end

    it 'returns 422' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

**H10: POST /api/v1/transactions -- amount boundary tests missing [FINTECH]**

Suggested test:
```ruby
context 'when amount is zero' do
  let(:amount) { '0' }

  it 'returns 422' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'when amount is at max (1_000_000)' do
  let(:amount) { '1000000' }

  it 'succeeds' do
    wallet.update!(balance: 2_000_000)
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
  end
end

context 'when amount is over max (1_000_001)' do
  let(:amount) { '1000001' }

  it 'returns 422' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

**H11: Security -- no authentication tests for any endpoint**

Suggested test:
```ruby
context 'without authentication' do
  it 'returns 401 for POST' do
    post '/api/v1/transactions', params: params
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 for GET index' do
    get '/api/v1/transactions'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 for GET show' do
    get '/api/v1/transactions/1'
    expect(response).to have_http_status(:unauthorized)
  end
end
```

**H12: GET /api/v1/transactions/:id -- another user's transaction not tested (IDOR)**

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

**H13: GET /api/v1/transactions -- data isolation not tested**

Suggested test:
```ruby
context 'data isolation' do
  let(:other_user) { create(:user) }
  let(:other_wallet) { create(:wallet, user: other_user) }

  before do
    create(:transaction, user: user, wallet: wallet)
    create(:transaction, user: other_user, wallet: other_wallet)
  end

  it 'only returns current user transactions' do
    get '/api/v1/transactions', headers: headers
    body = JSON.parse(response.body)
    expect(body['transactions'].length).to eq(1)
    expect(body['transactions'].first['wallet_id']).to eq(wallet.id)
  end
end
```

**H14: GET /api/v1/transactions -- date filters (start_date, end_date) completely untested**

Suggested test:
```ruby
context 'date filters' do
  before do
    create(:transaction, user: user, wallet: wallet, created_at: 3.days.ago)
    create(:transaction, user: user, wallet: wallet, created_at: 1.day.ago)
    create(:transaction, user: user, wallet: wallet, created_at: 10.days.ago)
  end

  context 'with start_date' do
    it 'filters transactions after start_date' do
      get '/api/v1/transactions', params: { start_date: 5.days.ago.iso8601 }, headers: headers
      body = JSON.parse(response.body)
      expect(body['transactions'].length).to eq(2)
    end
  end

  context 'with end_date' do
    it 'filters transactions before end_date' do
      get '/api/v1/transactions', params: { end_date: 2.days.ago.iso8601 }, headers: headers
      body = JSON.parse(response.body)
      expect(body['transactions'].length).to eq(2)
    end
  end
end
```

**H15: POST /api/v1/transactions -- error response leaks wallet balance [FINTECH]**
The `InsufficientBalanceError` handler in `TransactionService` includes `"Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"` in the error details. This leaks the wallet balance in error responses.

Suggested test:
```ruby
context 'when amount exceeds balance' do
  let(:amount) { (wallet.balance + 1).to_s }

  it 'does not leak wallet balance in error response' do
    post '/api/v1/transactions', params: params, headers: headers
    body = JSON.parse(response.body)
    expect(body['details'].join).not_to match(/balance/i)
    expect(body['details'].join).not_to match(/\d+\.\d+/)
  end
end
```

#### MEDIUM Priority Gaps

**M1: POST /api/v1/transactions -- currency empty string not tested**
**M2: POST /api/v1/transactions -- each valid currency value not individually verified**
**M3: GET /api/v1/transactions -- pagination params (page, per_page) untested**
**M4: GET /api/v1/transactions -- status filter untested**

---

### Fintech Gap Analysis

#### Missing Infrastructure

| Priority | Finding |
|---|---|
| HIGH | **No idempotency key on mutating endpoints** -- duplicate requests can create duplicate financial records. POST /api/v1/transactions has no idempotency_key param or X-Idempotency-Key header |
| HIGH | **TOCTOU race in TransactionService** -- `validate_sufficient_balance!` reads balance, then `deduct_balance!` calls `withdraw!` in separate steps. Two concurrent requests can both pass balance check individually but together exceed balance. The `with_lock` in `Wallet#withdraw!` is too late -- the check happens outside the lock |
| MEDIUM | **No rate limiting on financial mutation endpoints** -- consider adding to prevent brute-force/card testing attacks |
| MEDIUM | **No audit trail table/fields** -- financial operations should be auditable |
| MEDIUM | **No explicit state machine or transition guards** -- Transaction status enum has no guard preventing invalid transitions (e.g. `completed → pending`) |
| MEDIUM | **No balance validation test** -- no balance validation or ledger consistency patterns tested |
| MEDIUM | **No KYC/AML fields, transaction limits, or compliance validations** -- financial operations may lack regulatory safeguards |

---

### Anti-Patterns

| # | Anti-Pattern | Severity | Details |
|---|---|---|---|
| 1 | Multiple endpoints in one test file | MAJOR | POST, GET /:id, and GET index are all in `transactions_spec.rb`. Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb` |
| 2 | No test foundation pattern | MAJOR | No DEFAULT constants, no `subject(:run_test)`, no shared let blocks. Each test repeats `post '/api/v1/transactions', params: params, headers: headers` inline |
| 3 | Status-only assertions | MAJOR | Every test only checks `have_http_status(...)`. No response body, DB state, or API call assertions |
| 4 | Error tests don't assert no-side-effects | MAJOR | Error scenario tests don't verify `not_to change(Transaction, :count)` or that no external API calls were made |
| 5 | Implementation testing in transaction_service_spec.rb | MEDIUM | `expect(service).to receive(:build_transaction)` tests internal method calls, not contract behavior. Delete and test through POST endpoint instead |
