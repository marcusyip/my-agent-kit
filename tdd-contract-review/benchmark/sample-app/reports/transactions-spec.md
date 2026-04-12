## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/services/transaction_service.rb, app/models/transaction.rb
**Framework:** Rails 7.1 / RSpec (request spec)
**Fintech mode:** Enabled (money/amount/balance fields, payment gateway, transaction state machine)

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

### Overall Score: 2.9 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 2/10 | 25% | 0.50 |
| Test Grouping | 3/10 | 15% | 0.45 |
| Scenario Depth | 2/10 | 20% | 0.40 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 6/10 | 15% | 0.90 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **2.85** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb
        db/migrate/003_create_transactions.rb
Framework: Rails 7.1 / RSpec

API Contract — POST /api/v1/transactions (inbound):
  Request params:
    - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - wallet_id (integer, required, must belong to current_user) [HIGH confidence]
    - description (string, optional, max length: 500) [HIGH confidence]
    - category (string, optional, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
  Response fields (9 fields):
    - id (integer) [HIGH confidence]
    - amount (string, decimal as string) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - description (string) [HIGH confidence]
    - category (string) [HIGH confidence]
    - wallet_id (integer) [HIGH confidence]
    - created_at (string, ISO8601) [HIGH confidence]
    - updated_at (string, ISO8601) [HIGH confidence]
  Error response shape:
    - error (string) [HIGH confidence]
    - details (array of strings) [HIGH confidence]
  Status codes: 201, 422, 401

  Business rules:
    - Wallet must belong to current_user (set_wallet before_action) [HIGH confidence]
    - Wallet must be active (TransactionService#validate_wallet_active!) [HIGH confidence]
    - Currency must match wallet currency (TransactionService#validate_currency_match!) [HIGH confidence]
    - Status always set to 'pending' on creation [HIGH confidence]
    - Category defaults to 'transfer' when nil [HIGH confidence]
    - If category is 'payment', calls PaymentGateway.charge [HIGH confidence]
    - If gateway succeeds → status 'completed'; fails → status 'failed' [HIGH confidence]

API Contract — GET /api/v1/transactions/:id (inbound):
  Request params:
    - id (integer, required, path param) [HIGH confidence]
  Response fields: same 9 fields as POST response [HIGH confidence]
  Status codes: 200, 404, 401
  Business rules:
    - Scoped to current_user.transactions (IDOR protection) [HIGH confidence]

API Contract — GET /api/v1/transactions (inbound):
  Request params:
    - page (integer, optional) [MEDIUM confidence]
    - per_page (integer, optional, default: 25) [MEDIUM confidence]
  Response fields:
    - transactions (array of transaction objects) [HIGH confidence]
    - meta.total (integer) [HIGH confidence]
    - meta.page (integer) [HIGH confidence]
    - meta.per_page (integer) [HIGH confidence]
  Status codes: 200, 401
  Business rules:
    - Scoped to current_user.transactions [HIGH confidence]
    - Ordered by created_at desc [HIGH confidence]
    - Includes wallet association [MEDIUM confidence]

DB Contract — Transaction model:
  Fields:
    - user_id (integer, NOT NULL, FK → users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK → wallets) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - status (string, NOT NULL, default: 'pending') [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, NOT NULL, default: 'transfer') [HIGH confidence]
  Enum values:
    - status: pending, completed, failed, reversed [HIGH confidence]
    - category: transfer, payment, deposit, withdrawal [HIGH confidence]
  Indexes:
    - [user_id, created_at] [HIGH confidence]
    - [status] [HIGH confidence]

Outbound API — PaymentGateway.charge:
  Request params:
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
  Expected response: object responding to .success? [HIGH confidence]
  Error: PaymentGateway::ChargeError [HIGH confidence]

Fintech Dimensions:
  Money & Precision:
    - amount uses decimal(20,8) — exact type, good [HIGH confidence]
    - currency paired with amount [HIGH confidence]
    - No rounding rules detected [MEDIUM confidence]
  Idempotency:
    - NO idempotency key field on POST endpoint [HIGH confidence — absence confirmed]
  Transaction State Machine:
    - States: pending, completed, failed, reversed [HIGH confidence]
    - Transitions detected: pending → completed (gateway success), pending → failed (gateway failure) [HIGH confidence]
    - Terminal states: not explicitly defined [MEDIUM confidence]
    - reversed state: no transition path found in code [MEDIUM confidence]
  Balance & Ledger:
    - Transaction creation does NOT update wallet balance [HIGH confidence]
    - No double-entry pattern detected [HIGH confidence]
  Concurrency:
    - TransactionService does not wrap operations in DB transaction [HIGH confidence]
    - No locking on transaction creation [HIGH confidence]
  Security:
    - before_action :authenticate_user! on all actions [HIGH confidence]
    - Wallet scoped to current_user (IDOR protection on create) [HIGH confidence]
    - Transactions scoped to current_user (IDOR protection on show/index) [HIGH confidence]
    - No rate limiting detected [HIGH confidence — absence confirmed]

Total contract fields extracted: 52
============================
```

---

### Test Structure Tree

```
POST /api/v1/transactions
├── happy path
│   ├── ✓ returns 201
│   ├── ✗ response body: all 9 fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
│   ├── ✗ DB: Transaction created with correct user_id, wallet_id, amount, currency, status, category
│   ├── ✗ DB: Transaction.count increased by 1
│   └── ✗ status is 'pending' on creation
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero → 422 (boundary: > 0 required)
│   ├── ✗ exactly 1_000_000 (max boundary) → 201
│   ├── ✗ 1_000_001 (over max) → 422
│   ├── ✗ non-numeric string → 422
│   ├── ✗ [FINTECH] precision overflow (e.g. 0.123456789) — more decimals than decimal(20,8)
│   ├── ✗ [FINTECH] very small amount 0.00000001 (min for scale 8)
│   ├── ✗ no DB write assertion on nil case
│   └── ✗ no DB write assertion on negative case
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → 201
│   ├── ✗ no DB write assertion on nil case
│   └── ✗ no DB write assertion on invalid case
├── field: wallet_id (request param)
│   ├── ✓ not found (999_999) → 422
│   ├── ✗ belongs to another user → 422 (IDOR)
│   └── ✗ no DB write assertion on not-found case
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length (500 chars) → 201
│   ├── ✗ over max length (501 chars) → 422
│   └── ✗ empty string → should succeed
├── field: category (request param) — NO TESTS
│   ├── ✗ nil (defaults to 'transfer') → 201, verify default in DB
│   ├── ✗ each valid value (transfer, payment, deposit, withdrawal) → 201
│   ├── ✗ invalid value → 422
│   └── ✗ 'payment' triggers PaymentGateway.charge
├── business: wallet must be active — NO TESTS
│   ├── ✗ suspended wallet → 422, no DB write
│   └── ✗ closed wallet → 422, no DB write
├── business: currency must match wallet — NO TESTS
│   └── ✗ currency mismatch (e.g. EUR with USD wallet) → 422, no DB write
├── external: PaymentGateway.charge — NO TESTS
│   ├── ✗ gateway success → transaction status 'completed'
│   ├── ✗ gateway failure → transaction status 'failed'
│   ├── ✗ PaymentGateway::ChargeError → 422
│   ├── ✗ gateway timeout → error response
│   └── ✗ gateway NOT called for non-payment categories
├── [FINTECH] state machine — NO TESTS
│   ├── ✗ pending → completed (gateway success)
│   ├── ✗ pending → failed (gateway failure)
│   ├── ✗ invalid transition: completed → pending (must reject)
│   ├── ✗ terminal state: completed cannot transition further
│   └── ✗ reversed state: no transition path exists in code
├── [FINTECH] idempotency — MISSING INFRASTRUCTURE
│   └── ✗ no idempotency key on POST endpoint
├── [FINTECH] concurrency — NO TESTS
│   ├── ✗ double-submit: two rapid identical POSTs must not create duplicates
│   └── ✗ no DB transaction wrapping in TransactionService
├── [FINTECH] security — NO TESTS
│   ├── ✗ missing auth token → 401
│   ├── ✗ expired auth token → 401
│   └── ✗ error response does not leak sensitive data
└── response body assertions — NO TESTS
    ├── ✗ error shape: { error: string, details: [string] }
    └── ✗ success shape: { transaction: { ...9 fields } }

GET /api/v1/transactions/:id
├── happy path
│   ├── ✓ returns 200
│   └── ✗ response body: all 9 transaction fields
├── field: id (path param)
│   ├── ✓ not found → 404
│   └── ✗ another user's transaction → 404 (IDOR)
├── [FINTECH] security — NO TESTS
│   ├── ✗ missing auth token → 401
│   └── ✗ IDOR: access another user's transaction → 404
└── response body assertions — NO TESTS
    └── ✗ verify all 9 fields in response

GET /api/v1/transactions (index)
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response body: transactions array shape
│   ├── ✗ response body: meta (total, page, per_page)
│   └── ✗ ordering: created_at desc
├── field: page (query param) — NO TESTS
│   ├── ✗ page 1 vs page 2 returns different results
│   └── ✗ invalid page value
├── field: per_page (query param) — NO TESTS
│   ├── ✗ custom per_page value
│   └── ✗ default per_page is 25
├── business: only current_user's transactions — NO TESTS
│   └── ✗ does not return other users' transactions
├── empty state — NO TESTS
│   └── ✗ no transactions → empty array, meta.total = 0
└── [FINTECH] security — NO TESTS
    ├── ✗ missing auth token → 401
    └── ✗ does not leak other users' transactions
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | zero, max boundary, over max, non-numeric, precision overflow |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid value |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | another user's wallet (IDOR) |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | currency | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | status | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | category | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | wallet_id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | created_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | updated_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (business) | wallet active | HIGH | No | -- | HIGH: untested |
| POST /transactions (business) | currency match | HIGH | No | -- | HIGH: untested |
| POST /transactions (business) | default category | HIGH | No | -- | HIGH: untested |
| POST /transactions (business) | default status | HIGH | No | -- | HIGH: untested |
| POST /transactions (external) | PaymentGateway.charge | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (DB) | Transaction created | HIGH | No | -- | HIGH: no DB assertions |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | HIGH: no body assertions |
| GET /transactions/:id (param) | id not found | HIGH | Yes | 404 | IDOR: another user's |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: no body assertions |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: untested |
| GET /transactions (params) | page, per_page | MEDIUM | No | -- | MEDIUM: untested pagination |
| [FINTECH] state machine | transitions | HIGH | No | -- | HIGH: no transition tests |
| [FINTECH] idempotency | idempotency_key | HIGH | No | -- | HIGH: missing infrastructure |
| [FINTECH] concurrency | double-submit | HIGH | No | -- | HIGH: no concurrency tests |
| [FINTECH] security | auth (all endpoints) | HIGH | No | -- | HIGH: no auth tests |
| [FINTECH] security | IDOR (show, index) | HIGH | No | -- | HIGH: no IDOR tests |

---

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 23 gaps)

- [ ] `POST /api/v1/transactions` — happy path has NO response body assertions (9 fields untested)

  Suggested test:
  ```ruby
  context 'happy path' do
    it 'returns 201 with correct response body' do
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
      expect(txn['id']).to be_a(Integer)
      expect(txn['created_at']).to be_present
      expect(txn['updated_at']).to be_present
    end

    it 'persists correct data in DB' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .to change(Transaction, :count).by(1)
      db_txn = Transaction.last
      expect(db_txn.user_id).to eq(user.id)
      expect(db_txn.wallet_id).to eq(wallet.id)
      expect(db_txn.amount).to eq(100.50.to_d)
      expect(db_txn.currency).to eq('USD')
      expect(db_txn.status).to eq('pending')
      expect(db_txn.category).to eq('transfer')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `description` — no tests at all

  Suggested test:
  ```ruby
  context 'field: description' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, description: description } }
    end

    context 'when description is nil' do
      let(:description) { nil }

      it 'succeeds (optional field)' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when description is at max length (500)' do
      let(:description) { 'a' * 500 }

      it 'succeeds' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when description exceeds max length (501)' do
      let(:description) { 'a' * 501 }

      it 'returns 422 and does not create a transaction' do
        expect { post '/api/v1/transactions', params: params, headers: headers }
          .not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `category` — no tests at all

  Suggested test:
  ```ruby
  context 'field: category' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: category } }
    end

    context 'when category is nil' do
      let(:category) { nil }

      it 'defaults to transfer' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.category).to eq('transfer')
      end
    end

    context 'when category is payment' do
      let(:category) { 'payment' }

      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

      it 'creates transaction and charges gateway' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(PaymentGateway).to have_received(:charge)
      end
    end

    context 'when category is invalid' do
      let(:category) { 'invalid_category' }

      it 'returns 422 and does not create a transaction' do
        expect { post '/api/v1/transactions', params: params, headers: headers }
          .not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule — wallet must be active (suspended/closed)

  Suggested test:
  ```ruby
  context 'when wallet is suspended' do
    before { wallet.update!(status: 'suspended') }

    it 'returns 422 and does not create a transaction' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('Wallet is not active')
    end
  end

  context 'when wallet is closed' do
    before { wallet.update!(status: 'closed') }

    it 'returns 422 and does not create a transaction' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule — currency must match wallet

  Suggested test:
  ```ruby
  context 'when currency does not match wallet' do
    let(:currency) { 'EUR' }  # wallet is USD

    it 'returns 422 and does not create a transaction' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('Currency does not match wallet')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external API — PaymentGateway.charge scenarios

  Suggested test:
  ```ruby
  context 'external: PaymentGateway.charge' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }
    end

    context 'when gateway returns success' do
      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

      it 'creates transaction with status completed' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('completed')
      end
    end

    context 'when gateway returns failure' do
      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: false)) }

      it 'creates transaction with status failed' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('failed')
      end
    end

    context 'when gateway raises ChargeError' do
      before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError.new('declined')) }

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to eq('Payment processing failed')
      end
    end

    context 'when category is not payment' do
      let(:params) do
        { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'transfer' } }
      end

      it 'does not call PaymentGateway' do
        expect(PaymentGateway).not_to receive(:charge)
        post '/api/v1/transactions', params: params, headers: headers
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `wallet_id` — IDOR: another user's wallet

  Suggested test:
  ```ruby
  context 'when wallet belongs to another user' do
    let(:other_user) { create(:user) }
    let(:other_wallet) { create(:wallet, user: other_user, currency: 'USD') }
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: other_wallet.id } }
    end

    it 'returns 422 (wallet not found for current user)' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `GET /api/v1/transactions/:id` — no response body assertions

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
    expect(txn['created_at']).to be_present
    expect(txn['updated_at']).to be_present
  end
  ```

- [ ] `GET /api/v1/transactions/:id` — IDOR: another user's transaction

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

- [ ] `GET /api/v1/transactions` — no response body or pagination assertions

  Suggested test:
  ```ruby
  it 'returns transactions with meta' do
    create_list(:transaction, 3, user: user, wallet: wallet)
    get '/api/v1/transactions', headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['transactions'].length).to eq(3)
    expect(body['meta']['total']).to eq(3)
    expect(body['meta']['page']).to eq(1)
    expect(body['meta']['per_page']).to eq(25)
  end

  it 'returns transactions ordered by created_at desc' do
    old = create(:transaction, user: user, wallet: wallet, created_at: 2.days.ago)
    recent = create(:transaction, user: user, wallet: wallet, created_at: 1.day.ago)
    get '/api/v1/transactions', headers: headers
    body = JSON.parse(response.body)
    ids = body['transactions'].map { |t| t['id'] }
    expect(ids).to eq([recent.id, old.id])
  end

  it 'does not return other users transactions' do
    other_user = create(:user)
    other_wallet = create(:wallet, user: other_user)
    create(:transaction, user: other_user, wallet: other_wallet)
    create(:transaction, user: user, wallet: wallet)
    get '/api/v1/transactions', headers: headers
    body = JSON.parse(response.body)
    expect(body['transactions'].length).to eq(1)
  end
  ```

- [ ] `[FINTECH]` All 3 endpoints — no authentication tests (missing/expired token → 401)

  Suggested test:
  ```ruby
  context 'without authentication' do
    it 'returns 401' do
      post '/api/v1/transactions', params: params
      expect(response).to have_http_status(:unauthorized)
    end
  end
  ```

- [ ] `[FINTECH]` Transaction state machine — no transition tests exist

- [ ] `[FINTECH]` Concurrency — no double-submit prevention test, no DB transaction wrapping in TransactionService

**MEDIUM** (tested but missing scenarios — 8 gaps)

- [ ] `POST /api/v1/transactions` field `amount` — missing zero boundary (> 0 validation means zero should be rejected)
- [ ] `POST /api/v1/transactions` field `amount` — missing max boundary (1_000_000 should succeed, 1_000_001 should fail)
- [ ] `POST /api/v1/transactions` field `amount` — missing non-numeric string input
- [ ] `POST /api/v1/transactions` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/transactions` field `currency` — no test verifying each valid value (USD, EUR, GBP, BTC, ETH) works
- [ ] `POST /api/v1/transactions` all error tests — none assert that no DB record was created
- [ ] `GET /api/v1/transactions` — no pagination params tested (page, per_page)
- [ ] `GET /api/v1/transactions` — no empty state test

**LOW** (rare corner cases — 3 gaps)

- [ ] `POST /api/v1/transactions` field `amount` — precision overflow (more than 8 decimal places)
- [ ] `POST /api/v1/transactions` field `amount` — very small amount (0.00000001)
- [ ] `[FINTECH]` Transaction `reversed` status — no transition path exists in code (dead enum value?)

### Missing Infrastructure [FINTECH]

- [ ] **No idempotency key** on `POST /api/v1/transactions` — HIGH. Financial mutation endpoints must have idempotency handling to prevent duplicate transactions. Consider adding an `idempotency_key` parameter with a unique DB constraint.
- [ ] **No rate limiting** detected on any endpoint — MEDIUM. Financial mutation endpoints should be rate-limited to prevent brute-force and card testing attacks.
- [ ] **No audit trail** table or fields detected for financial mutations — MEDIUM. Financial operations should be auditable (actor, action, timestamp, IP, old/new value).

---

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `transactions_spec.rb` (POST + GET /:id + GET index) | HIGH | Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb` |
| Status-only assertions | `transactions_spec.rb:32-88` (all tests) | HIGH | Add response body, DB state, and side-effect assertions |
| No test foundation | `transactions_spec.rb` — no `subject(:run_test)`, no DEFAULT constants | MEDIUM | Add `subject(:run_test)` and default constants per the sessions pattern |
| No DB write assertions on error paths | `transactions_spec.rb:38-88` | HIGH | Add `expect { run_test }.not_to change(Transaction, :count)` to all error tests |
| PaymentGateway not mocked | `transactions_spec.rb:32` — happy path may hit real gateway | HIGH | Mock `PaymentGateway.charge` for non-payment tests, stub for payment tests |

---

### Top 5 Priority Actions

1. **Add response body + DB assertions to POST happy path** — protects all 9 response fields and DB state from silent regression. Highest single-test ROI.
2. **Add PaymentGateway.charge test scenarios** (success/failure/error) — the payment integration is untested; a gateway contract change would break silently.
3. **Add wallet-must-be-active and currency-mismatch tests** — core business rules with zero coverage; changes to TransactionService validation would go undetected.
4. **Add IDOR tests** for wallet_id (POST) and transaction show/index — security-critical; access control bugs are the #1 fintech vulnerability.
5. **Split into one-endpoint-per-file and add test foundation** (subject, defaults) — structural fix that makes all future gaps immediately visible.
