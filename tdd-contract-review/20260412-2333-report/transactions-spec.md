## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/models/transaction.rb, app/services/transaction_service.rb, db/migrate/003_create_transactions.rb
**Framework:** Rails 7.1 / RSpec (request spec)

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every API endpoint, job, and message consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `+` = scenario is tested
- `x` = scenario is missing (potential silent breakage)
- Each entry point (endpoint, job, consumer) gets its own section
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**One endpoint per file:** Each API endpoint, job, or consumer should have its own test file. This makes gaps immediately visible -- if a file doesn't exist, the entire contract is untested.

**Contract boundary:** Tests should verify behavior at the contract boundary (API endpoint, job entry point), not internal implementation. Testing that a service method is called is implementation testing -- testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have. A codebase with 100 tests that only check status codes scores lower than one with 20 tests that verify response fields, DB state, and error paths.

### Overall Score: 3.2 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 2/10 | 20% | 0.40 |
| Test Case Quality | 3/10 | 15% | 0.45 |
| Isolation & Flakiness | 5/10 | 15% | 0.75 |
| Anti-Patterns | 2/10 | 10% | 0.20 |
| **Overall** | | | **3.15** |

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
      - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max 500) [HIGH confidence]
      - category (string, optional, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string, decimal-as-string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
      - updated_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401

  GET /api/v1/transactions/:id
    Request params:
      - id (integer, path param, required) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
      - updated_at (string, ISO8601) [HIGH confidence]
    Status codes: 200, 404, 401

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [HIGH confidence]
      - per_page (integer, optional, default: 25) [HIGH confidence]
    Response fields:
      - transactions (array of transaction objects) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200, 401

DB Contract:
  Transaction model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK to wallets) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - status (string, NOT NULL, default: 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, NOT NULL, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (called when category == 'payment'):
    Request:
      - amount (decimal) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - user_id (integer) [HIGH confidence]
      - transaction_id (integer) [HIGH confidence]
    Expected response: { success?: boolean } [HIGH confidence]
    Error: PaymentGateway::ChargeError [HIGH confidence]

Business Rules:
  - Wallet must be active (not suspended/closed) [HIGH confidence]
  - Currency must match wallet currency [HIGH confidence]
  - Amount must be > 0 and <= 1,000,000 [HIGH confidence]
  - Description max length: 500 [HIGH confidence]
  - Currency must be one of: USD, EUR, GBP, BTC, ETH [HIGH confidence]
  - Payment category triggers PaymentGateway.charge [HIGH confidence]
  - Gateway success -> status: completed; failure -> status: failed [HIGH confidence]
============================
Total contract fields extracted: 48
```

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | amount (decimal(20,8)), currency (string) | 3 HIGH, 2 MEDIUM |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | status enum: pending/completed/failed/reversed | 3 HIGH |
| 4 | Balance & Ledger Integrity | Not detected -- flagged | -- | Infrastructure gap |
| 5 | External Payment Integrations | Extracted | PaymentGateway.charge | 3 HIGH |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Not detected -- flagged | -- | Infrastructure gap |
| 8 | Security & Access Control | Extracted | before_action :authenticate_user!, wallet ownership via current_user.wallets | 4 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/transactions
|-- field: amount (request param)
|   |-- + nil -> 422
|   |-- + negative -> 422
|   |-- x zero (boundary) -> should reject (greater_than: 0)
|   |-- x at max (1,000,000) -> should succeed
|   |-- x over max (1,000,001) -> 422
|   |-- x non-numeric string -> 422
|   |-- x precision overflow (too many decimals for decimal(20,8))
|-- field: currency (request param)
|   |-- + nil -> 422
|   |-- + invalid value ('INVALID') -> 422
|   |-- x empty string -> 422
|   |-- x each valid value (USD, EUR, GBP, BTC, ETH) verified
|-- field: wallet_id (request param)
|   |-- + wallet not found -> 422
|   |-- x another user's wallet -> 422/403
|-- field: description (request param) -- NO TESTS
|   |-- x nil (optional, should succeed)
|   |-- x max length (500) -> should succeed
|   |-- x over max length (501) -> 422
|-- field: category (request param) -- NO TESTS
|   |-- x each valid value (transfer/payment/deposit/withdrawal)
|   |-- x invalid value -> 422
|   |-- x nil (defaults to 'transfer')
|-- response body -- NO ASSERTIONS
|   |-- x happy path should assert all 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
|-- DB assertions -- NO ASSERTIONS
|   |-- x happy path should assert Transaction created with correct field values
|   |-- x error paths should assert no Transaction created
|-- business: wallet must be active
|   |-- x suspended wallet -> 422
|   |-- x closed wallet -> 422
|-- business: currency must match wallet
|   |-- x mismatch -> 422
|-- external: PaymentGateway.charge (when category=payment) -- NO TESTS
|   |-- x gateway success -> status: completed
|   |-- x gateway failure -> status: failed
|   |-- x PaymentGateway::ChargeError -> 422
|   |-- x gateway timeout -> appropriate error
|-- [FINTECH] status enum transitions -- NO TESTS
|   |-- x pending -> completed (valid)
|   |-- x pending -> failed (valid)
|   |-- x completed -> reversed (valid if applicable)
|   |-- x completed -> pending (INVALID, must reject)
|   |-- x terminal state: no transition from reversed
|-- [FINTECH] idempotency -- NOT IMPLEMENTED
|   |-- x no idempotency key on mutating POST endpoint
|-- [FINTECH] authentication
|   |-- x missing/expired auth token -> 401
|-- [FINTECH] IDOR
|   |-- x another user's wallet_id -> 403/422

GET /api/v1/transactions/:id
|-- field: id (path param)
|   |-- + valid transaction -> 200
|   |-- + not found -> 404
|   |-- x another user's transaction -> 404/403
|-- response body -- NO ASSERTIONS
|   |-- x should assert all 9 response fields
|-- [FINTECH] authentication
|   |-- x missing auth token -> 401

GET /api/v1/transactions
|-- + returns 200
|-- response body -- NO ASSERTIONS
|   |-- x should assert transactions array shape
|   |-- x should assert meta.total, meta.page, meta.per_page
|   |-- x should verify ordering (created_at desc)
|-- pagination -- NO TESTS
|   |-- x custom page param
|   |-- x custom per_page param
|   |-- x empty result set
|-- [FINTECH] authentication
|   |-- x missing auth token -> 401
|-- [FINTECH] data isolation
|   |-- x only returns authenticated user's transactions
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | HIGH: zero, at max, over max, non-numeric, precision overflow |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | HIGH: another user's wallet (IDOR) |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: untested (nil, max length, over max) |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: untested (valid values, invalid, nil/default) |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: untested |
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
| PaymentGateway.charge (outbound) | amount | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | currency | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | user_id | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | transaction_id | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (response) | success? | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (error) | ChargeError | HIGH | No | -- | HIGH: untested |
| Business rule | wallet active check | HIGH | No | -- | HIGH: suspended/closed wallet untested |
| Business rule | currency match check | HIGH | No | -- | HIGH: currency mismatch untested |
| GET /transactions/:id (request) | id | HIGH | Yes | valid, not found | HIGH: another user's transaction (IDOR) |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | HIGH: no response body assertions |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: no response shape assertions |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: untested |
| GET /transactions (request) | page | HIGH | No | -- | MEDIUM: pagination untested |
| GET /transactions (request) | per_page | HIGH | No | -- | MEDIUM: pagination untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` response body -- no test asserts any of the 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)

Suggested test:
```ruby
context 'happy path' do
  it 'returns 201 with all response fields' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    txn = body['transaction']
    expect(txn['id']).to be_a(Integer)
    expect(txn['amount']).to eq('100.5')
    expect(txn['currency']).to eq('USD')
    expect(txn['status']).to eq('pending')
    expect(txn['description']).to be_nil
    expect(txn['category']).to eq('transfer')
    expect(txn['wallet_id']).to eq(wallet.id)
    expect(txn['created_at']).to be_present
    expect(txn['updated_at']).to be_present
  end
end
```

- [ ] `POST /api/v1/transactions` DB state -- no test asserts Transaction record is created with correct field values

Suggested test:
```ruby
context 'happy path' do
  it 'persists transaction with correct data' do
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

- [ ] `POST /api/v1/transactions` request field `description` -- no test verifies this field at all

Suggested test:
```ruby
context 'when description is provided' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        description: 'Monthly rent payment'
      }
    }
  end

  it 'persists the description' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(Transaction.last.description).to eq('Monthly rent payment')
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

- [ ] `POST /api/v1/transactions` request field `category` -- no test verifies this field at all

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

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'creates a transaction with payment category and triggers gateway' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    expect(Transaction.last.category).to eq('payment')
    expect(PaymentGateway).to have_received(:charge)
  end
end

context 'when category is invalid' do
  let(:params) do
    {
      transaction: {
        amount: amount,
        currency: currency,
        wallet_id: wallet.id,
        category: 'invalid_category'
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

context 'when category is nil (defaults to transfer)' do
  it 'creates a transaction with transfer category' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(Transaction.last.category).to eq('transfer')
  end
end
```

- [ ] `POST /api/v1/transactions` business rule -- wallet must be active, no test for suspended or closed wallet

Suggested test:
```ruby
context 'when wallet is suspended' do
  before { wallet.update!(status: 'suspended') }

  it 'returns 422 and does not create a transaction' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['error']).to include('not active')
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

- [ ] `POST /api/v1/transactions` business rule -- currency must match wallet, no test for mismatch

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
    expect(body['error']).to include('Currency does not match')
  end
end
```

- [ ] `POST /api/v1/transactions` external API -- PaymentGateway.charge entirely untested (success, failure, ChargeError paths)

Suggested test:
```ruby
context 'when category is payment and gateway succeeds' do
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

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'creates transaction with completed status' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
    expect(Transaction.last.status).to eq('completed')
    expect(PaymentGateway).to have_received(:charge).with(
      amount: BigDecimal('100.50'),
      currency: 'USD',
      user_id: user.id,
      transaction_id: Transaction.last.id
    )
  end
end

context 'when category is payment and gateway fails' do
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

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
  end

  it 'creates transaction with failed status' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(Transaction.last.status).to eq('failed')
  end
end

context 'when category is payment and gateway raises ChargeError' do
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

  before do
    allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError, 'Gateway unavailable')
  end

  it 'returns 422 with payment processing error' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['error']).to eq('Payment processing failed')
  end
end
```

- [ ] `POST /api/v1/transactions` request field `amount` -- missing zero (boundary), at max (1,000,000), over max scenarios

Suggested test:
```ruby
context 'when amount is zero' do
  let(:amount) { '0' }

  it 'returns 422 (must be greater than 0)' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'when amount is at max (1,000,000)' do
  let(:amount) { '1000000' }

  it 'returns 201' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
  end
end

context 'when amount exceeds max (1,000,001)' do
  let(:amount) { '1000001' }

  it 'returns 422' do
    expect {
      post '/api/v1/transactions', params: params, headers: headers
    }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `POST /api/v1/transactions` [FINTECH] -- wallet_id accepts another user's wallet (IDOR vulnerability)

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

- [ ] `POST /api/v1/transactions` [FINTECH] authentication -- no test for missing/expired auth token

Suggested test:
```ruby
context 'when auth token is missing' do
  it 'returns 401' do
    post '/api/v1/transactions', params: params
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] `GET /api/v1/transactions/:id` response body -- no test asserts response fields

Suggested test:
```ruby
it 'returns transaction with all fields' do
  get "/api/v1/transactions/#{transaction.id}", headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  txn = body['transaction']
  expect(txn['id']).to eq(transaction.id)
  expect(txn['amount']).to eq(transaction.amount.to_s)
  expect(txn['currency']).to eq(transaction.currency)
  expect(txn['status']).to eq(transaction.status)
  expect(txn['wallet_id']).to eq(transaction.wallet_id)
  expect(txn['created_at']).to be_present
  expect(txn['updated_at']).to be_present
end
```

- [ ] `GET /api/v1/transactions/:id` [FINTECH] IDOR -- no test for accessing another user's transaction

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

- [ ] `GET /api/v1/transactions` response shape -- no test asserts response structure, meta, or ordering

Suggested test:
```ruby
it 'returns transactions with correct shape and meta' do
  create_list(:transaction, 3, user: user, wallet: wallet)
  get '/api/v1/transactions', headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  expect(body['transactions']).to be_an(Array)
  expect(body['transactions'].length).to eq(3)
  expect(body['meta']['total']).to eq(3)
  expect(body['meta']['page']).to eq(1)
  expect(body['meta']['per_page']).to eq(25)

  # Verify ordering (most recent first)
  timestamps = body['transactions'].map { |t| t['created_at'] }
  expect(timestamps).to eq(timestamps.sort.reverse)
end
```

- [ ] `GET /api/v1/transactions` [FINTECH] data isolation -- no test verifying only authenticated user's transactions returned

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
    expect(body['meta']['total']).to eq(1)
  end
end
```

- [ ] [FINTECH] `Transaction` status enum -- no tests verify state transitions (pending->completed, pending->failed, invalid transitions like completed->pending)

- [ ] [FINTECH] `POST /api/v1/transactions` amount precision -- no test for amounts with more decimal places than decimal(20,8) allows

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` request field `currency` -- missing empty string scenario
- [ ] `POST /api/v1/transactions` request field `currency` -- missing verification of each valid value (USD, EUR, GBP, BTC, ETH)
- [ ] `POST /api/v1/transactions` error paths -- no test asserts `no Transaction created` on error (only checks status code)
- [ ] `GET /api/v1/transactions` pagination -- no tests for custom page/per_page params or empty results

**Missing Infrastructure** [FINTECH]

- [ ] **HIGH: No idempotency key on mutating endpoint** -- POST /api/v1/transactions has no idempotency key. Duplicate requests can create duplicate financial records.
- [ ] **MEDIUM: No rate limiting on financial mutation endpoints** -- no rate limiting detected on POST /api/v1/transactions. Consider adding to prevent brute-force/card testing attacks.
- [ ] **MEDIUM: No audit trail table/fields for financial mutations** -- no audit trail detected. Financial operations should be auditable.
- [ ] **MEDIUM: No explicit state machine or transition guards** -- Transaction model defines status enum but no transition guards. Invalid state transitions (e.g. completed -> pending) can corrupt financial data.

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | transactions_spec.rb (POST + GET/:id + GET index) | HIGH | Split into post-transactions-spec.rb, get-transaction-spec.rb, get-transactions-spec.rb |
| Status-code-only assertions | transactions_spec.rb:32-35 (happy path), :42-44, :50-52, :58-60, :68-70, :85-88 | HIGH | Assert response body, DB state, and side effects |
| No DB state assertions | transactions_spec.rb (all tests) | HIGH | Add `change(Transaction, :count)` and field-level DB assertions |
| No response body assertions | transactions_spec.rb:100-103, :117-121 | HIGH | Parse response body and verify all fields |
| Missing test foundation | transactions_spec.rb (no subject/run_test, no DEFAULT constants) | MEDIUM | Add `subject(:run_test)` and DEFAULT_AMOUNT, DEFAULT_CURRENCY constants |
| No error-path side-effect assertions | transactions_spec.rb:38-45, :47-53, :56-61, :64-71, :74-89 | MEDIUM | Assert no Transaction created on 422 |

### Top 5 Priority Actions

1. **Add response body and DB assertions to happy path** -- the happy path test only checks status 201. Add assertions for all 9 response fields and verify the Transaction record was persisted with correct values. This single improvement covers 18+ contract fields.
2. **Add PaymentGateway.charge test scenarios** -- the external API integration (success, failure, ChargeError) is entirely untested. This is a financial payment path with zero coverage.
3. **Split into one endpoint per file** -- three endpoints in one file obscures gaps. Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb`.
4. **Add wallet business rule tests** -- suspended wallet, closed wallet, and currency mismatch are untested business rules that guard financial operations.
5. **Add IDOR tests for wallet_id and transaction/:id** -- no test verifies that users cannot access other users' wallets or transactions. This is the #1 fintech security vulnerability.
