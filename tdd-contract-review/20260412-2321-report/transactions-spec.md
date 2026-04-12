## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/models/transaction.rb, app/services/transaction_service.rb, db/migrate/003_create_transactions.rb
**Framework:** Rails 7.1 / RSpec (request spec)

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

### Overall Score: 3.3 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 5/10 | 15% | 0.75 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.30** |

### Verdict: WEAK

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/models/transaction.rb
        app/services/transaction_service.rb
        db/migrate/003_create_transactions.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):

  POST /api/v1/transactions
    Request params:
      - amount (decimal, required) [HIGH confidence]
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
      - created_at (string, ISO8601) [HIGH confidence]
      - updated_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401
    Auth: before_action :authenticate_user!

  GET /api/v1/transactions/:id
    Request params:
      - id (integer, path param, required) [HIGH confidence]
    Response fields:
      - transaction (object, same shape as POST response) [HIGH confidence]
    Status codes: 200, 404, 401
    Auth: before_action :authenticate_user!

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [MEDIUM confidence]
      - per_page (integer, optional, default: 25) [MEDIUM confidence]
    Response fields:
      - transactions (array of transaction objects) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200, 401
    Auth: before_action :authenticate_user!

DB Contract:
  Transaction model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK to wallets) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - status (string, NOT NULL, default: 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, NOT NULL, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]

  Business rules:
    - amount: numericality > 0, <= 1_000_000 [HIGH confidence]
    - currency must match wallet currency (validated in TransactionService) [HIGH confidence]
    - wallet must be active (validated in TransactionService) [HIGH confidence]
    - wallet must belong to current_user (controller: current_user.wallets.find_by) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (triggered when category == 'payment'):
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
    - Expected response: { success?: boolean } [HIGH confidence]
    - On success: transaction status → completed [HIGH confidence]
    - On failure: transaction status → failed [HIGH confidence]
    - On ChargeError: returns 422 with error message [HIGH confidence]
============================
```

**Total contract fields extracted: 42** (14 request params across 3 endpoints + 9 response fields + 4 status codes + 10 DB columns + 5 outbound API fields). Extraction complete.

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | amount (decimal(20,8)), currency, balance | 4 HIGH, 2 MEDIUM |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | status enum: pending/completed/failed/reversed | 3 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | wallet.balance, deposit!, withdraw! | 2 HIGH, 1 MEDIUM |
| 5 | External Payment Integrations | Extracted | PaymentGateway.charge | 3 HIGH |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Not detected -- flagged | -- | Infrastructure gap |
| 8 | Security & Access Control | Extracted | authenticate_user!, current_user scoping | 4 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/transactions
├── happy path
│   ├── ✓ returns 201 (status only)
│   ├── ✗ response body asserts all 9 fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
│   ├── ✗ DB record created with correct values
│   └── ✗ no PaymentGateway call for non-payment category
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero → 422 (boundary)
│   ├── ✗ exactly 1_000_000 → 201 (boundary max)
│   ├── ✗ 1_000_001 → 422 (over max)
│   ├── ✗ precision overflow (e.g. 0.123456789) → round/truncate/reject?
│   ├── ✗ very small (0.00000001) → success
│   ├── ✗ non-numeric string → 422
│   └── ✗ no DB write on error, no external API call on error
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → success
│   └── ✗ currency mismatch with wallet → 422
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   ├── ✗ belongs to another user → 422 (IDOR)
│   └── ✗ no DB write on error
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length (500) → success
│   ├── ✗ over max length (501) → 422
│   └── ✗ empty string → success
├── field: category (request param) — NO TESTS
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal)
│   ├── ✗ invalid value → 422
│   ├── ✗ nil → defaults to 'transfer'
│   └── ✗ 'payment' triggers PaymentGateway.charge
├── business: wallet must be active
│   ├── ✗ suspended wallet → 422
│   └── ✗ closed wallet → 422
├── external: PaymentGateway.charge — NO TESTS
│   ├── ✗ success response → transaction status completed
│   ├── ✗ failure response → transaction status failed
│   ├── ✗ ChargeError → 422
│   └── ✗ timeout/unavailable → 503 or error
├── [FINTECH] idempotency — NO TESTS (no idempotency key exists)
│   └── ✗ duplicate POST creates duplicate record (infrastructure gap)
├── [FINTECH] state machine transitions — NO TESTS
│   ├── ✗ pending → completed (via gateway success)
│   ├── ✗ pending → failed (via gateway failure)
│   ├── ✗ completed → reversed (if supported)
│   ├── ✗ invalid: completed → pending (must reject)
│   └── ✗ terminal states: no further transition from reversed
├── [FINTECH] concurrency — NO TESTS
│   └── ✗ two concurrent POSTs both passing balance check
├── [FINTECH] security: auth
│   ├── ✗ missing auth token → 401
│   └── ✗ expired token → 401
└── [FINTECH] security: IDOR
    └── ✗ access another user's wallet_id → 422/403

GET /api/v1/transactions/:id
├── happy path
│   ├── ✓ returns 200 (status only)
│   └── ✗ response body asserts all 9 fields
├── field: id (path param)
│   ├── ✓ not found → 404
│   └── ✗ another user's transaction → 404 (IDOR)
├── [FINTECH] security: auth
│   └── ✗ missing auth token → 401
└── [FINTECH] security: IDOR
    └── ✗ another user's transaction ID → 404

GET /api/v1/transactions
├── happy path
│   ├── ✓ returns 200 (status only)
│   ├── ✗ response body asserts transactions array
│   ├── ✗ response body asserts meta (total, page, per_page)
│   └── ✗ ordering (descending by created_at)
├── field: page (query param) — NO TESTS
│   ├── ✗ page 1 vs page 2 returns different results
│   └── ✗ invalid page → 200 with empty array or error
├── field: per_page (query param) — NO TESTS
│   ├── ✗ custom per_page → correct count
│   └── ✗ default 25
├── [FINTECH] security: auth
│   └── ✗ missing auth token → 401
└── [FINTECH] security: data leakage
    └── ✗ only returns current user's transactions (not all)
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | HIGH: zero, max boundary, over-max, precision overflow, non-numeric |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value, mismatch with wallet |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | HIGH: another user's wallet (IDOR) |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: untested (nil, max length, over-max) |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: untested (each value, invalid, nil default, payment trigger) |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: untested (decimal-as-string format) |
| POST /transactions (response) | currency | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | status | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | category | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | wallet_id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | created_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | updated_at | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | user_id | HIGH | No | -- | HIGH: not asserted in happy path |
| Transaction (DB) | wallet_id | HIGH | No | -- | HIGH: not asserted in happy path |
| Transaction (DB) | amount | HIGH | No | -- | HIGH: not asserted in happy path |
| Transaction (DB) | currency | HIGH | No | -- | HIGH: not asserted in happy path |
| Transaction (DB) | status | HIGH | No | -- | HIGH: enum values pending/completed/failed/reversed untested |
| Transaction (DB) | description | HIGH | No | -- | HIGH: not asserted |
| Transaction (DB) | category | HIGH | No | -- | HIGH: enum values transfer/payment/deposit/withdrawal untested |
| Business rule | wallet active | HIGH | No | -- | HIGH: suspended, closed untested |
| Business rule | currency match | HIGH | No | -- | HIGH: mismatch untested |
| PaymentGateway.charge (outbound) | amount | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | currency | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | success response | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | failure response | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | ChargeError | HIGH | No | -- | HIGH: untested |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | HIGH: not asserted |
| GET /transactions/:id (param) | id (another user) | HIGH | No | -- | HIGH: IDOR untested |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: not asserted |
| GET /transactions (param) | page | MEDIUM | No | -- | MEDIUM: untested |
| GET /transactions (param) | per_page | MEDIUM | No | -- | MEDIUM: untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` happy path -- no response body assertions. The test only checks status 201, never verifying the 9 response fields.

Suggested test:
```ruby
context 'happy path' do
  it 'returns 201 with correct response body' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    txn = body['transaction']
    expect(txn['amount']).to eq('100.50')
    expect(txn['currency']).to eq('USD')
    expect(txn['status']).to eq('pending')
    expect(txn['wallet_id']).to eq(wallet.id)
    expect(txn['description']).to be_nil
    expect(txn['category']).to eq('transfer')
    expect(txn).to have_key('id')
    expect(txn).to have_key('created_at')
    expect(txn).to have_key('updated_at')
  end

  it 'persists correct data in DB' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.to change(Transaction, :count).by(1)
    db_txn = Transaction.last
    expect(db_txn.user_id).to eq(user.id)
    expect(db_txn.wallet_id).to eq(wallet.id)
    expect(db_txn.amount).to eq(BigDecimal('100.50'))
    expect(db_txn.currency).to eq('USD')
    expect(db_txn.status).to eq('pending')
    expect(db_txn.category).to eq('transfer')
  end
end
```

- [ ] `POST /api/v1/transactions` request field `description` -- no tests verify this field at all.

Suggested test:
```ruby
context 'field: description' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        description: description
      }
    }
  end
  let(:description) { 'Test payment' }

  context 'when description is nil' do
    let(:description) { nil }

    it 'creates transaction without description' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(Transaction.last.description).to be_nil
    end
  end

  context 'when description is at max length (500)' do
    let(:description) { 'a' * 500 }

    it 'creates transaction' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
    end
  end

  context 'when description exceeds max length (501)' do
    let(:description) { 'a' * 501 }

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] `POST /api/v1/transactions` request field `category` -- no tests verify this field at all. Four enum values (transfer/payment/deposit/withdrawal) are completely untested. The `payment` category triggers `PaymentGateway.charge` -- this critical branching behavior has zero coverage.

Suggested test:
```ruby
context 'field: category' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        category: category
      }
    }
  end

  context 'when category is nil (defaults to transfer)' do
    let(:category) { nil }

    it 'creates transaction with transfer category' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(Transaction.last.category).to eq('transfer')
    end
  end

  context 'when category is payment' do
    let(:category) { 'payment' }

    before do
      allow(PaymentGateway).to receive(:charge)
        .and_return(double(success?: true))
    end

    it 'creates transaction and calls PaymentGateway' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(PaymentGateway).to have_received(:charge).with(
        amount: BigDecimal('100.50'),
        currency: 'USD',
        user_id: user.id,
        transaction_id: Transaction.last.id
      )
    end
  end

  context 'when category is invalid' do
    let(:category) { 'invalid_category' }

    it 'returns 422' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] `POST /api/v1/transactions` external API `PaymentGateway.charge` -- no tests for success, failure, ChargeError, or timeout scenarios.

Suggested test:
```ruby
context 'external: PaymentGateway.charge' do
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
      allow(PaymentGateway).to receive(:charge)
        .and_return(double(success?: true))
    end

    it 'creates transaction with completed status' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(Transaction.last.status).to eq('completed')
    end
  end

  context 'when gateway returns failure' do
    before do
      allow(PaymentGateway).to receive(:charge)
        .and_return(double(success?: false))
    end

    it 'creates transaction with failed status' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(Transaction.last.status).to eq('failed')
    end
  end

  context 'when gateway raises ChargeError' do
    before do
      allow(PaymentGateway).to receive(:charge)
        .and_raise(PaymentGateway::ChargeError, 'Card declined')
    end

    it 'returns 422 with error message' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Payment processing failed')
    end
  end
end
```

- [ ] `POST /api/v1/transactions` business rule: wallet must be active -- no test for suspended or closed wallet.

Suggested test:
```ruby
context 'business: wallet must be active' do
  context 'when wallet is suspended' do
    before { wallet.update!(status: 'suspended') }

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'when wallet is closed' do
    before { wallet.update!(status: 'closed') }

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] `POST /api/v1/transactions` business rule: currency must match wallet -- no test for mismatch.

Suggested test:
```ruby
context 'business: currency must match wallet' do
  let(:currency) { 'EUR' }  # wallet is USD

  it 'returns 422 and does not create transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['details']).to include('Currency must match wallet currency')
  end
end
```

- [ ] `POST /api/v1/transactions` field `wallet_id` -- IDOR: no test for wallet belonging to another user.

Suggested test:
```ruby
context 'when wallet belongs to another user (IDOR)' do
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

  it 'returns 422 and does not create transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `GET /api/v1/transactions/:id` -- IDOR: no test for accessing another user's transaction.

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

- [ ] `GET /api/v1/transactions/:id` -- response body not asserted. Only checks status 200.

Suggested test:
```ruby
it 'returns the transaction with correct fields' do
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

- [ ] `GET /api/v1/transactions` -- response body and pagination meta not asserted.

Suggested test:
```ruby
it 'returns transactions with correct pagination meta' do
  create_list(:transaction, 3, user: user, wallet: wallet)
  get '/api/v1/transactions', headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  expect(body['transactions'].length).to eq(3)
  expect(body['meta']['total']).to eq(3)
  expect(body['meta']['page']).to eq(1)
  expect(body['meta']['per_page']).to eq(25)
end
```

- [ ] [FINTECH] All 3 endpoints missing authentication tests -- no test for missing/expired auth token returning 401.

Suggested test:
```ruby
context 'when auth token is missing' do
  it 'returns 401' do
    post '/api/v1/transactions', params: params
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] [FINTECH] `POST /api/v1/transactions` amount field -- missing zero boundary (should reject), max boundary (1_000_000 should succeed), over-max (1_000_001 should reject), and precision overflow tests.

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

context 'when amount is exactly at max (1_000_000)' do
  let(:amount) { '1000000' }

  it 'returns 201' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
  end
end

context 'when amount exceeds max (1_000_001)' do
  let(:amount) { '1000001' }

  it 'returns 422' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` field `currency` -- missing empty string edge case
- [ ] `POST /api/v1/transactions` field `currency` -- missing test for each valid value (USD, EUR, GBP, BTC, ETH)
- [ ] `POST /api/v1/transactions` error scenarios -- existing error tests only assert status code 422, never assert no DB write (missing `expect { ... }.not_to change(Transaction, :count)`)
- [ ] `GET /api/v1/transactions` -- missing pagination tests (page param, per_page param, ordering)

**LOW** (rare corner cases)

- [ ] `POST /api/v1/transactions` field `amount` -- non-numeric string input
- [ ] `GET /api/v1/transactions` -- empty result set scenario

### Missing Infrastructure (Fintech)

- [ ] **[FINTECH] HIGH: No idempotency key on mutating endpoints** -- `POST /api/v1/transactions` has no idempotency key field. Duplicate requests can create duplicate financial records.
- [ ] **[FINTECH] HIGH: No concurrency protection on financial write paths** -- TransactionService creates transactions without database locking or atomic balance updates. Concurrent requests can cause double-debit or overdraw.
- [ ] **[FINTECH] MEDIUM: No rate limiting detected** on financial mutation endpoints -- consider adding to prevent brute-force/card testing attacks.
- [ ] **[FINTECH] MEDIUM: No audit trail detected** -- financial operations should be auditable (no `created_by`, `ip_address`, or audit log table).
- [ ] **[FINTECH] MEDIUM: No explicit state machine or transition guards detected** for Transaction status -- invalid state transitions (e.g. `completed → pending`) are not prevented at the model level.
- [ ] **[FINTECH] MEDIUM: No KYC/AML fields, transaction limits, or compliance validations detected** -- financial operations may lack regulatory safeguards.

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | transactions_spec.rb (POST + GET/:id + GET index) | HIGH | Split into post-transactions-spec.rb, get-transaction-spec.rb, get-transactions-spec.rb |
| Status-only assertions | transactions_spec.rb:32-35, :42-44, :50-52, :58-60, :67-69, :85-88, :100-103, :119 | HIGH | Assert response body, DB state, and side effects |
| No DB state assertions | transactions_spec.rb:32-35 (happy path) | HIGH | Add `expect { ... }.to change(Transaction, :count).by(1)` and DB field assertions |
| No test foundation (no subject/runTest) | transactions_spec.rb | MEDIUM | Add `subject(:run_test)` and default constants |
| No error-side-effect assertions | transactions_spec.rb:42, 50, 58, 67, 85 | MEDIUM | Assert `not_to change(Transaction, :count)` on error paths |

### Top 5 Priority Actions

1. **Add response body and DB assertions to POST happy path** -- the current test only checks status 201, leaving all 9 response fields and all DB columns unverified. Any serializer or persistence change breaks silently.
2. **Add PaymentGateway.charge scenarios for `payment` category** -- the critical external API integration (success → completed, failure → failed, ChargeError → 422) has zero test coverage. A gateway contract change or error handling regression is invisible.
3. **Add IDOR tests for wallet_id (POST) and transaction id (GET)** -- no test verifies that users cannot access other users' wallets or transactions. This is the #1 fintech security vulnerability.
4. **Add description and category field scenarios** -- two entire request params with validation rules (max length, enum values, default value) have zero coverage.
5. **Split into one-endpoint-per-file** -- three endpoints in one file obscures per-endpoint coverage. Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb`.
