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

### Overall Score: 3.0 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 3/10 | 15% | 0.45 |
| Scenario Depth | 2/10 | 20% | 0.40 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 6/10 | 15% | 0.90 |
| Anti-Patterns | 2/10 | 10% | 0.20 |
| **Overall** | | | **3.00** |

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
      - category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string, decimal as string) [HIGH confidence]
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
      - transaction object (same shape as POST response) [HIGH confidence]
    Status codes: 200, 404, 401

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

DB Contract:
  Transaction model:
    - id (integer, PK, auto) [HIGH confidence]
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK to wallets) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL, >0, <=1_000_000) [HIGH confidence]
    - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - status (string, NOT NULL, default: pending, enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable, max 500) [HIGH confidence]
    - category (string, NOT NULL, default: transfer, enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (triggered on payment category after_create and via TransactionService):
    Request:
      - amount (decimal) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - user_id (integer) [HIGH confidence]
      - transaction_id (integer) [HIGH confidence]
    Expected response: { success?: boolean } [MEDIUM confidence]
    Error: PaymentGateway::ChargeError [HIGH confidence]

Business rules:
  - Wallet must be active (TransactionService validates) [HIGH confidence]
  - Currency must match wallet currency (TransactionService validates) [HIGH confidence]
  - set_wallet scopes to current_user.wallets (ownership check) [HIGH confidence]
============================
```

**Fintech Dimension Template:**

| # | Dimension | Status | Fields Found | Notes |
|---|-----------|--------|-------------|-------|
| 1 | Money & Precision | Extracted | amount (decimal(20,8)), currency (USD/EUR/GBP/BTC/ETH), balance (decimal(20,8)) | Amount uses exact decimal type — good |
| 2 | Idempotency | Not detected | — | No idempotency key on POST /api/v1/transactions — will be flagged in gap analysis |
| 3 | Transaction State Machine | Extracted | status enum: pending/completed/failed/reversed; category enum: transfer/payment/deposit/withdrawal | Transitions in TransactionService (pending->completed, pending->failed) |
| 4 | Balance & Ledger Integrity | Extracted | wallet.balance, Wallet#deposit!, Wallet#withdraw!, with_lock | Balance updated via with_lock, but POST /transactions does not debit wallet |
| 5 | External Payment Integrations | Extracted | PaymentGateway.charge, PaymentGateway::ChargeError | Charge triggered for payment category |
| 6 | Regulatory & Compliance | Not detected | — | No KYC/AML fields, transaction limits (only model validation), or audit trail — will be flagged in gap analysis |
| 7 | Concurrency & Data Integrity | Extracted | Wallet#with_lock (pessimistic locking on deposit!/withdraw!) | No locking on transaction creation path |
| 8 | Security & Access Control | Extracted | before_action :authenticate_user!, current_user.wallets scoping, current_user.transactions scoping | Ownership enforced via scoping |

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | 3 fields (amount, currency, balance) | 2 HIGH, 2 MEDIUM |
| 2 | Idempotency | Not detected — flagged | — | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | 2 fields (status, category) | 3 HIGH, 1 MEDIUM |
| 4 | Balance & Ledger Integrity | Extracted | 2 fields (balance, with_lock) | 1 HIGH, 1 MEDIUM |
| 5 | External Payment Integrations | Extracted | 2 fields (PaymentGateway.charge, ChargeError) | 3 HIGH |
| 6 | Regulatory & Compliance | Not detected — flagged | — | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | 1 field (with_lock) | 2 HIGH |
| 8 | Security & Access Control | Extracted | 3 fields (authenticate_user!, user scoping) | 3 HIGH |

**Fintech mode:** Active — all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/transactions
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero (boundary) → 422 (greater_than: 0)
│   ├── ✗ exactly 1_000_000 (max boundary) → 201
│   ├── ✗ over 1_000_000 → 422
│   ├── ✗ non-numeric string → 422
│   └── ✗ precision overflow (more than 8 decimal places) → round/truncate/reject? [FINTECH]
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ currency mismatch with wallet → 422 [FINTECH]
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   ├── ✗ another user's wallet → 422 (IDOR) [FINTECH]
│   ├── ✗ suspended wallet → 422 [FINTECH]
│   └── ✗ closed wallet → 422 [FINTECH]
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ at max length (500) → 201
│   └── ✗ over max length (501) → 422
├── field: category (request param) — NO TESTS
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal) → 201
│   ├── ✗ invalid value → 422
│   └── ✗ nil → defaults to transfer
├── response body — NO ASSERTIONS
│   └── ✗ happy path should assert all 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
├── DB assertions — NO ASSERTIONS
│   └── ✗ happy path should assert Transaction created with correct values
├── status transitions — NO TESTS [FINTECH]
│   ├── ✗ pending → completed (payment gateway success)
│   ├── ✗ pending → failed (payment gateway failure)
│   └── ✗ invalid transition (completed → pending) → rejected
├── external: PaymentGateway.charge — NO TESTS [FINTECH]
│   ├── ✗ payment category → gateway called with correct params
│   ├── ✗ gateway success → status completed
│   ├── ✗ gateway failure → status failed
│   ├── ✗ gateway ChargeError → 422
│   └── ✗ non-payment category → gateway NOT called
├── auth — NO TESTS [FINTECH]
│   ├── ✗ unauthenticated → 401
│   └── ✗ missing/expired token → 401
└── idempotency — NO TESTS [FINTECH]
    └── ✗ duplicate POST → infrastructure gap (no idempotency key)

GET /api/v1/transactions/:id
├── ✓ returns 200 for own transaction
├── ✓ returns 404 for non-existent transaction
├── response body — NO ASSERTIONS
│   └── ✗ should assert all response fields
├── ✗ another user's transaction → 404 (IDOR) [FINTECH]
└── ✗ unauthenticated → 401

GET /api/v1/transactions
├── ✓ returns 200
├── response body — NO ASSERTIONS
│   ├── ✗ should assert transactions array shape
│   ├── ✗ should assert meta (total, page, per_page)
│   └── ✗ should assert ordering (created_at desc)
├── ✗ pagination (page, per_page params)
├── ✗ only returns current user's transactions (IDOR) [FINTECH]
└── ✗ unauthenticated → 401
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | missing: zero, max boundary, over max, non-numeric, precision overflow |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | missing: empty string, each valid value, currency mismatch |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | missing: another user's wallet, suspended wallet, closed wallet |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | currency | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | status | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | category | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | wallet_id | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | created_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (response) | updated_at | HIGH | No | -- | HIGH: untested |
| POST /transactions (status codes) | 201 | HIGH | Yes | happy path | missing: response body assertion |
| POST /transactions (status codes) | 422 | HIGH | Yes | amount nil, negative; currency nil, invalid; wallet not found | -- |
| POST /transactions (status codes) | 401 | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | user_id | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | wallet_id | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | amount | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | currency | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | status | HIGH | No | -- | HIGH: no DB assertion, missing enum values |
| Transaction (DB) | status enum: pending | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | status enum: completed | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | status enum: failed | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | status enum: reversed | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | description | HIGH | No | -- | HIGH: no DB assertion |
| Transaction (DB) | category | HIGH | No | -- | HIGH: no DB assertion, missing enum values |
| Transaction (DB) | category enum: transfer | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | category enum: payment | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | category enum: deposit | HIGH | No | -- | HIGH: untested |
| Transaction (DB) | category enum: withdrawal | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | amount | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | currency | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | user_id | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | transaction_id | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | success response | MEDIUM | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | ChargeError | HIGH | No | -- | HIGH: untested |
| GET /transactions/:id (request) | id | HIGH | Yes | exists, not found | missing: another user's transaction |
| GET /transactions/:id (response) | transaction object | HIGH | No | -- | HIGH: response body not verified |
| GET /transactions/:id (status codes) | 401 | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: response shape not verified |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: untested |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: untested |
| GET /transactions (request) | page | MEDIUM | No | -- | MEDIUM: untested |
| GET /transactions (request) | per_page | MEDIUM | No | -- | MEDIUM: untested |
| GET /transactions (status codes) | 401 | HIGH | No | -- | HIGH: untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` response body — no test asserts any of the 9 response fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)

  Suggested test:
  ```ruby
  context 'with valid params' do
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

- [ ] `POST /api/v1/transactions` DB assertions — no test verifies Transaction record persisted with correct values

  Suggested test:
  ```ruby
  context 'with valid params' do
    it 'persists correct data in DB' do
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

- [ ] `POST /api/v1/transactions` request field `description` — no test verifies this field

  Suggested test:
  ```ruby
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
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `category` — no test verifies this field

  Suggested test:
  ```ruby
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
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

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
  ```

- [ ] `POST /api/v1/transactions` wallet belonging to another user — IDOR vulnerability [FINTECH]

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
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` suspended/closed wallet — no test [FINTECH]

  Suggested test:
  ```ruby
  context 'when wallet is suspended' do
    before { wallet.update!(status: 'suspended') }

    it 'returns 422 and does not create a transaction' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
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

- [ ] `POST /api/v1/transactions` currency mismatch with wallet — no test [FINTECH]

  Suggested test:
  ```ruby
  context 'when currency does not match wallet currency' do
    let(:currency) { 'EUR' }

    it 'returns 422 and does not create a transaction' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` PaymentGateway.charge — no test for external API scenarios [FINTECH]

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

      it 'calls gateway with correct params' do
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
        allow(PaymentGateway).to receive(:charge)
          .and_raise(PaymentGateway::ChargeError, 'Gateway timeout')
      end

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` authentication — no test for unauthenticated access [FINTECH]

  Suggested test:
  ```ruby
  context 'when not authenticated' do
    it 'returns 401' do
      post '/api/v1/transactions', params: params
      expect(response).to have_http_status(:unauthorized)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` transaction status transitions — no tests verify state machine [FINTECH]

  Suggested test:
  ```ruby
  # Test that status transitions follow the state machine
  context 'status transitions' do
    let(:transaction) { create(:transaction, user: user, wallet: wallet, status: 'completed') }

    it 'does not allow completed → pending transition' do
      expect { transaction.update!(status: 'pending') }.to raise_error(ActiveRecord::RecordInvalid)
      # Note: requires explicit state machine guards in source code
    end
  end
  ```

- [ ] `GET /api/v1/transactions/:id` another user's transaction — IDOR vulnerability [FINTECH]

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

- [ ] `GET /api/v1/transactions/:id` response body — no assertion on response shape

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
  end
  ```

- [ ] `GET /api/v1/transactions` response body — no assertion on response shape, pagination meta, or ordering

  Suggested test:
  ```ruby
  it 'returns transactions with meta' do
    create_list(:transaction, 3, user: user, wallet: wallet)
    get '/api/v1/transactions', headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['transactions']).to be_an(Array)
    expect(body['transactions'].size).to eq(3)
    expect(body['meta']['total']).to eq(3)
    expect(body['meta']['page']).to eq(1)
    expect(body['meta']['per_page']).to eq(25)
  end
  ```

- [ ] `GET /api/v1/transactions` only returns current user's transactions — IDOR [FINTECH]

  Suggested test:
  ```ruby
  it 'does not return other users transactions' do
    other_user = create(:user)
    other_wallet = create(:wallet, user: other_user)
    create(:transaction, user: other_user, wallet: other_wallet)
    create(:transaction, user: user, wallet: wallet)

    get '/api/v1/transactions', headers: headers
    body = JSON.parse(response.body)
    expect(body['transactions'].size).to eq(1)
  end
  ```

- [ ] All endpoints: unauthenticated access — no test for 401 status code [FINTECH]

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` request field `amount` — missing zero boundary and max boundary (1_000_000) [FINTECH]
- [ ] `POST /api/v1/transactions` request field `currency` — missing empty string edge case
- [ ] `POST /api/v1/transactions` request field `amount` — missing precision overflow test (>8 decimal places) [FINTECH]
- [ ] `GET /api/v1/transactions` — missing pagination params (page, per_page)
- [ ] No balance deduction on transaction creation — POST /transactions creates a transaction but does not debit the wallet [FINTECH]

**LOW** (rare corner cases)

- [ ] `POST /api/v1/transactions` request field `amount` — non-numeric string
- [ ] `POST /api/v1/transactions` request field `wallet_id` — string instead of integer

#### Missing infrastructure [FINTECH]

- [ ] **HIGH: No idempotency key on mutating endpoints** — POST /api/v1/transactions has no idempotency key parameter or unique constraint. Duplicate requests can create duplicate financial records.
- [ ] **HIGH: No concurrency protection on transaction creation path** — TransactionService does not use database locking or atomic updates when creating transactions. Concurrent requests can cause double-debit or inconsistent state. (Note: Wallet#deposit!/withdraw! DO use `with_lock`, but the POST /transactions flow does not debit the wallet at all.)
- [ ] **MEDIUM: No rate limiting on financial mutation endpoints** — POST /api/v1/transactions has no rate limiting detected. Consider adding to prevent brute-force/card testing attacks.
- [ ] **MEDIUM: No audit trail table/fields for financial mutations** — No audit trail detected for transaction creation, status changes, or wallet operations. Financial operations should be auditable.
- [ ] **MEDIUM: No explicit state machine or transition guards** — Transaction model defines enum `status: { pending, completed, failed, reversed }` but has no explicit state machine gem (e.g., aasm, state_machines) or transition guards. Invalid state transitions (e.g., `completed → pending`) are not prevented at the model level.
- [ ] **MEDIUM: No KYC/AML fields, transaction limits, or compliance validations** — No KYC/AML fields on User, no server-side transaction limits beyond model validation (1_000_000 max), no daily/monthly aggregate limits. Financial operations may lack regulatory safeguards.

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | spec/requests/api/v1/transactions_spec.rb | HIGH | Split into post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb |
| Status-only assertions (no response body) | transactions_spec.rb:33 (happy path) | HIGH | Assert all 9 response fields |
| No DB state assertions | transactions_spec.rb:33 (happy path) | HIGH | Assert Transaction created with correct field values |
| No external API mock assertions | transactions_spec.rb (entire file) | HIGH | Add PaymentGateway.charge mock assertions for payment category |
| Missing test foundation defaults | transactions_spec.rb:18-28 | MEDIUM | Extract DEFAULT_AMOUNT, DEFAULT_CURRENCY constants; use subject(:run_test) |
| No authentication tests | transactions_spec.rb (entire file) | HIGH | Add unauthenticated request tests per endpoint |

### Top 5 Priority Actions

1. **Add response body and DB assertions to happy path** — POST /transactions happy path only checks status 201. Add assertions for all 9 response fields and verify Transaction DB record has correct values. This is the foundation that makes all other gaps visible.
2. **Add PaymentGateway.charge tests for payment category** — The external API integration is completely untested. Add success/failure/ChargeError scenarios with mock assertions on params sent to gateway. Financial payment processing without tests is a critical risk.
3. **Add IDOR tests for all three endpoints** — No test verifies that users cannot access other users' wallets or transactions. Add another-user's-wallet test for POST, another-user's-transaction test for GET/:id, and only-own-transactions test for GET index.
4. **Split into one endpoint per test file** — The single file covering 3 endpoints obscures gaps. Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb`.
5. **Add suspended/closed wallet and currency mismatch tests** — The TransactionService has explicit validation for wallet status and currency match, but no tests exercise these paths. These are financial safety checks that must be verified.
