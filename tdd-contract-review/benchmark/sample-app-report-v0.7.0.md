Now I have all source and test files. Let me produce the complete report.

---

## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** `spec/requests/api/v1/transactions_spec.rb`
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** `app/controllers/api/v1/transactions_controller.rb`, `app/services/transaction_service.rb`, `app/models/transaction.rb`
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

### Overall Score: 3.5 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 2.5/10 | 20% | 0.50 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.50** |

### Verdict: WEAK

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb
Framework: Rails 7.1 / RSpec

API Contract — POST /api/v1/transactions (inbound):
  Request params:
    - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - wallet_id (integer, required) [HIGH confidence]
    - description (string, optional, max 500) [HIGH confidence]
    - category (string, optional, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
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
  Status codes: 201, 422, 401

  Business rules:
    - Wallet must be active (WalletInactiveError → 422) [HIGH confidence]
    - Currency must match wallet currency (CurrencyMismatchError → 422) [HIGH confidence]
    - Transaction status defaults to 'pending' [HIGH confidence]

  DB state:
    - Transaction created with user_id, wallet_id, amount, currency, status, description, category [HIGH confidence]

  External API — PaymentGateway.charge (when category = 'payment'):
    - Request: amount, currency, user_id, transaction_id [HIGH confidence]
    - Success → transaction status updated to 'completed' [HIGH confidence]
    - Failure → transaction status updated to 'failed' [HIGH confidence]
    - ChargeError → 422 with 'Payment processing failed' [HIGH confidence]

API Contract — GET /api/v1/transactions/:id (inbound):
  Request params:
    - id (integer, required, path param) [HIGH confidence]
  Response fields:
    - transaction (object with same 9 fields as POST response) [HIGH confidence]
  Status codes: 200, 404
  Scoping: only returns transactions belonging to current_user [HIGH confidence]

API Contract — GET /api/v1/transactions (inbound):
  Request params:
    - page (integer, optional) [HIGH confidence]
    - per_page (integer, optional, default 25) [HIGH confidence]
  Response fields:
    - transactions (array of serialized transactions) [HIGH confidence]
    - meta.total (integer) [HIGH confidence]
    - meta.page (integer) [HIGH confidence]
    - meta.per_page (integer) [HIGH confidence]
  Ordering: created_at DESC [HIGH confidence]
  Scoping: only returns transactions belonging to current_user [HIGH confidence]
============================
```

### Anti-Pattern: Multiple Endpoints in One File

This test file covers **3 endpoints** (POST, GET/:id, GET index). Each should have its own file:
- `spec/requests/api/v1/post_transactions_spec.rb`
- `spec/requests/api/v1/get_transaction_spec.rb`
- `spec/requests/api/v1/get_transactions_spec.rb`

### Anti-Pattern: Missing Test Foundation

No `subject(:run_test)` helper, no `DEFAULT_` constants. Each test repeats `post '/api/v1/transactions', params: params, headers: headers` inline. This obscures the single-override-per-test pattern and makes it harder to spot which field each test is varying.

### Test Structure Tree

```
POST /api/v1/transactions
├── happy path
│   ├── ✓ returns 201
│   ├── ✗ response body — none of 9 fields asserted (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
│   ├── ✗ DB state — no assertion that Transaction record created with correct values
│   └── ✗ DB count — no change(Transaction, :count).by(1)
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero (boundary) → 422 (must be > 0)
│   ├── ✗ max (1_000_000) → should succeed
│   ├── ✗ over max (1_000_001) → 422
│   └── ✗ non-numeric string → 422
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value → 422
│   ├── ✗ empty string → 422
│   └── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → success
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   ├── ✗ belongs to another user → 422
│   └── ✗ nil/missing → 422
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed with no description)
│   ├── ✗ max length (500) → should succeed
│   ├── ✗ over max length (501) → 422
│   └── ✗ empty string → should succeed
├── field: category (request param) — NO TESTS
│   ├── ✗ nil (defaults to 'transfer') → 201 with category='transfer'
│   ├── ✗ each valid value (transfer, payment, deposit, withdrawal) → success
│   └── ✗ invalid value → 422
├── business: wallet must be active — NO TESTS
│   ├── ✗ suspended wallet → 422
│   └── ✗ closed wallet → 422
├── business: currency must match wallet — NO TESTS
│   └── ✗ currency mismatch → 422
├── external: PaymentGateway.charge (when category=payment) — NO TESTS
│   ├── ✗ success → transaction status updated to 'completed'
│   ├── ✗ failure response → transaction status updated to 'failed'
│   └── ✗ ChargeError → 422 with 'Payment processing failed'
└── error assertions completeness
    └── ✗ all error scenarios only assert status code — no DB unchanged or no-side-effect assertions

GET /api/v1/transactions/:id
├── happy path
│   ├── ✓ returns 200
│   └── ✗ response body — no field assertions (should verify all 9 fields)
├── field: id (path param)
│   ├── ✓ not found → 404
│   └── ✗ belongs to another user → 404 (scoped to current_user)
└── ✗ authentication — no test for unauthenticated request

GET /api/v1/transactions (index)
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response body — no transactions array shape assertion
│   └── ✗ meta fields — no total, page, per_page assertions
├── field: page (query param) — NO TESTS
│   ├── ✗ page=1 returns first page
│   ├── ✗ page=2 returns second page
│   └── ✗ page beyond range → empty transactions
├── field: per_page (query param) — NO TESTS
│   ├── ✗ custom per_page → limits results
│   └── ✗ default (25) used when omitted
├── ordering — NO TESTS
│   └── ✗ ordered by created_at DESC
├── scoping — NO TESTS
│   └── ✗ does not return other user's transactions
└── empty state — NO TESTS
    └── ✗ returns empty array when no transactions
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | zero, max, over-max, non-numeric |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid value |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | another user's, nil |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (response) | all 9 fields | HIGH | No | -- | HIGH: no response body assertions |
| POST /transactions (DB) | Transaction record | HIGH | No | -- | HIGH: no DB state assertions |
| POST /transactions (business) | wallet active | HIGH | No | -- | HIGH: suspended/closed untested |
| POST /transactions (business) | currency match | HIGH | No | -- | HIGH: mismatch untested |
| POST /transactions (external) | PaymentGateway | HIGH | No | -- | HIGH: success/failure/error untested |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | HIGH: no field assertions |
| GET /transactions/:id (scoping) | other user | HIGH | No | -- | MEDIUM: untested |
| GET /transactions (response) | meta fields | HIGH | No | -- | HIGH: pagination untested |
| GET /transactions (ordering) | created_at DESC | HIGH | No | -- | MEDIUM: untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` happy path — no response body assertions on any of 9 fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)

  Suggested test:
  ```ruby
  context 'happy path' do
    it 'returns 201 with correct response body' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)['transaction']
      expect(body['id']).to be_present
      expect(body['amount']).to eq('100.5')
      expect(body['currency']).to eq('USD')
      expect(body['status']).to eq('pending')
      expect(body['description']).to be_nil
      expect(body['category']).to eq('transfer')
      expect(body['wallet_id']).to eq(wallet.id)
      expect(body['created_at']).to be_present
      expect(body['updated_at']).to be_present
    end

    it 'persists correct data in DB' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.to change(Transaction, :count).by(1)

      txn = Transaction.last
      expect(txn.user_id).to eq(user.id)
      expect(txn.wallet_id).to eq(wallet.id)
      expect(txn.amount).to eq(100.50)
      expect(txn.currency).to eq('USD')
      expect(txn.status).to eq('pending')
      expect(txn.category).to eq('transfer')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `description` — no test verifies this field (`transactions_controller.rb:66`)

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
    let(:description) { 'Monthly rent payment' }

    context 'when description is nil' do
      let(:description) { nil }

      it 'succeeds (description is optional)' do
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

      it 'returns 422 and does not create transaction' do
        expect {
          post '/api/v1/transactions', params: params, headers: headers
        }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `category` — no test verifies this field (`transaction.rb:8-13`)

  Suggested test:
  ```ruby
  context 'field: category' do
    let(:params) do
      {
        transaction: {
          amount: amount, currency: currency, wallet_id: wallet.id,
          category: category
        }
      }
    end

    context 'when category is nil (defaults to transfer)' do
      let(:category) { nil }

      it 'creates transaction with category=transfer' do
        post '/api/v1/transactions', params: { transaction: { amount: amount, currency: currency, wallet_id: wallet.id } }, headers: headers
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)['transaction']
        expect(body['category']).to eq('transfer')
      end
    end

    %w[transfer payment deposit withdrawal].each do |valid_category|
      context "when category is '#{valid_category}'" do
        let(:category) { valid_category }

        it 'succeeds' do
          allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) if valid_category == 'payment'
          post '/api/v1/transactions', params: params, headers: headers
          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)['transaction']
          expect(body['category']).to eq(valid_category)
        end
      end
    end

    context 'when category is invalid' do
      let(:category) { 'refund' }

      it 'returns 422' do
        expect {
          post '/api/v1/transactions', params: params, headers: headers
        }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule — wallet must be active (`transaction_service.rb:36-38`)

  Suggested test:
  ```ruby
  context 'when wallet is suspended' do
    before { wallet.update!(status: 'suspended') }

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Wallet is not active')
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
  ```

- [ ] `POST /api/v1/transactions` business rule — currency must match wallet (`transaction_service.rb:40-43`)

  Suggested test:
  ```ruby
  context 'when currency does not match wallet' do
    let(:currency) { 'EUR' } # wallet.currency is 'USD'

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Currency does not match wallet')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external API — PaymentGateway.charge scenarios (`transaction_service.rb:57-69`)

  Suggested test:
  ```ruby
  context 'field: PaymentGateway (when category=payment)' do
    let(:params) do
      {
        transaction: {
          amount: amount, currency: currency, wallet_id: wallet.id,
          category: 'payment'
        }
      }
    end

    context 'when gateway returns success' do
      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

      it 'creates transaction with status=completed' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        txn = Transaction.last
        expect(txn.status).to eq('completed')
      end

      it 'sends correct params to gateway' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(PaymentGateway).to have_received(:charge).with(
          hash_including(amount: 100.50, currency: 'USD')
        )
      end
    end

    context 'when gateway returns failure' do
      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: false)) }

      it 'creates transaction with status=failed' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        txn = Transaction.last
        expect(txn.status).to eq('failed')
      end
    end

    context 'when gateway raises ChargeError' do
      before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError, 'Card declined') }

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Payment processing failed')
      end
    end
  end
  ```

- [ ] `GET /api/v1/transactions` — pagination and meta fields entirely untested (`transactions_controller.rb:11-25`)

  Suggested test:
  ```ruby
  describe 'GET /api/v1/transactions' do
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

    it 'paginates with custom per_page' do
      create_list(:transaction, 5, user: user, wallet: wallet)
      get '/api/v1/transactions', params: { per_page: 2, page: 1 }, headers: headers

      body = JSON.parse(response.body)
      expect(body['transactions'].length).to eq(2)
      expect(body['meta']['total']).to eq(5)
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
  end
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` field `amount` — missing zero boundary, max (1_000_000), over-max (1_000_001), non-numeric string
- [ ] `POST /api/v1/transactions` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/transactions` field `wallet_id` — missing another user's wallet → 422
- [ ] `GET /api/v1/transactions/:id` — response body fields not asserted
- [ ] `GET /api/v1/transactions/:id` — missing test for another user's transaction → 404
- [ ] `GET /api/v1/transactions` — ordering (created_at DESC) not verified
- [ ] All error scenarios — only assert status code, no DB-unchanged or no-side-effect assertions

**LOW** (rare corner cases)

- [ ] `GET /api/v1/transactions` — empty state (no transactions) response
- [ ] Authentication — no test for unauthenticated requests on any endpoint

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `transactions_spec.rb` (3 endpoints) | HIGH | Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb` |
| Status-only assertions | `transactions_spec.rb:33,42,50,59,69,86` | HIGH | Add response body, DB state, and side-effect assertions |
| Missing test foundation | `transactions_spec.rb` | MEDIUM | Add `subject(:run_test)`, `DEFAULT_` constants |
| No DB assertions in happy path | `transactions_spec.rb:31-35` | HIGH | Assert Transaction created with correct field values |
| No response body assertions | `transactions_spec.rb:31-35` | HIGH | Assert all 9 response fields |

### Top 5 Priority Actions

1. **Add response body + DB assertions to POST happy path** — without these, any change to serialization or transaction creation breaks silently
2. **Add `description` and `category` field test groups** — these are permitted params with validations and enum values that are completely unprotected
3. **Add PaymentGateway external API scenarios** — the payment flow (success/failure/ChargeError) has zero test coverage, yet it mutates transaction status
4. **Add wallet-must-be-active and currency-mismatch tests** — two business rules in TransactionService with no API-level verification
5. **Split into one endpoint per file** — the current structure obscures per-endpoint gap visibility

---

## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** `spec/requests/api/v1/wallets_spec.rb`
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets
**Source files:** `app/controllers/api/v1/wallets_controller.rb`, `app/models/wallet.rb`
**Framework:** Rails 7.1 / RSpec (request spec)

### Overall Score: 4.3 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 5/10 | 15% | 0.75 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **4.30** |

### Verdict: NEEDS IMPROVEMENT

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/wallets_controller.rb
        app/models/wallet.rb
Framework: Rails 7.1 / RSpec

API Contract — POST /api/v1/wallets (inbound):
  Request params:
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, required, max 100) [HIGH confidence]
  Response fields:
    - id (integer) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - name (string) [HIGH confidence]
    - balance (string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - created_at (string, ISO8601) [HIGH confidence]
  Status codes: 201, 422
  Business rules:
    - currency unique per user [HIGH confidence]
    - balance defaults to 0 [HIGH confidence]
    - status defaults to 'active' [HIGH confidence]

API Contract — GET /api/v1/wallets (inbound):
  Response fields:
    - wallets (array of serialized wallets) [HIGH confidence]
  Ordering: by currency [HIGH confidence]
  Scoping: current_user.wallets [HIGH confidence]

API Contract — PATCH /api/v1/wallets/:id (inbound):
  Request params:
    - currency (string, optional) [HIGH confidence]
    - name (string, optional) [HIGH confidence]
    - status (string, optional) [HIGH confidence]
  Response fields: same 6 fields as POST response [HIGH confidence]
  Status codes: 200, 404, 422 [HIGH confidence]
  Scoping: current_user.wallets [HIGH confidence]

DB Contract — Wallet model:
  - user_id (integer, NOT NULL, FK) [HIGH confidence]
  - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
  - name (string, NOT NULL, max 100) [HIGH confidence]
  - balance (decimal, NOT NULL, >= 0, default 0) [HIGH confidence]
  - status (string, NOT NULL, default 'active', enum: active/suspended/closed) [HIGH confidence]
============================
```

### Anti-Pattern: Multiple Endpoints in One File + Missing Endpoint

This file covers 2 endpoints (POST, GET index) in one file. PATCH /api/v1/wallets/:id has **no test file at all**. Should be split into:
- `spec/requests/api/v1/post_wallets_spec.rb`
- `spec/requests/api/v1/get_wallets_spec.rb`
- `spec/requests/api/v1/patch_wallet_spec.rb` (does not exist)

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ DB count change(Wallet, :count).by(1)
│   ├── ✓ response: currency = 'USD'
│   ├── ✓ response: name = 'My USD Wallet'
│   ├── ✓ response: balance = '0.0'
│   ├── ✓ response: status = 'active'
│   ├── ✗ response: id — not asserted
│   └── ✗ response: created_at — not asserted
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value ('XYZ') → 422
│   ├── ✗ empty string → 422
│   └── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → success
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100) → should succeed
│   └── ✗ over max length (101) → 422
├── business: currency unique per user — NO TESTS
│   └── ✗ duplicate currency for same user → 422
└── error assertions completeness
    └── ✗ error scenarios only assert status code — no DB-unchanged assertions

GET /api/v1/wallets
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response body — no wallets array shape or count assertion
│   └── ✗ response fields — no individual wallet field assertions
├── ordering — NO TESTS
│   └── ✗ ordered by currency
├── scoping — NO TESTS
│   └── ✗ does not return other user's wallets
└── empty state — NO TESTS
    └── ✗ returns empty array when no wallets

PATCH /api/v1/wallets/:id — NO TEST FILE EXISTS
├── ✗ happy path — update name → 200 with updated fields
├── ✗ field: currency — update currency → success or 422
├── ✗ field: name — update name → success
├── ✗ field: status — update to suspended, closed, back to active
├── ✗ not found → 404
├── ✗ belongs to another user → 404
├── ✗ invalid params → 422
└── ✗ name too long → 422
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid, duplicate |
| POST /wallets (request) | name | HIGH | Yes | nil | empty string, max, over-max |
| POST /wallets (response) | currency, name, balance, status | HIGH | In happy path | checked | missing: id, created_at |
| POST /wallets (business) | unique currency/user | HIGH | No | -- | HIGH: untested |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: no shape assertions |
| PATCH /wallets/:id | all fields | HIGH | No | -- | HIGH: entire endpoint untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint has zero test coverage (`wallets_controller.rb:30-39`)

  Suggested test (new file `spec/requests/api/v1/patch_wallet_spec.rb`):
  ```ruby
  # Generated tests follow your project's patterns. Review before committing.
  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    DEFAULT_NAME = 'My USD Wallet'
    DEFAULT_CURRENCY = 'USD'

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet.id}", params: { wallet: update_params }, headers: headers
    end

    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
    let(:update_params) { { name: new_name } }
    let(:new_name) { 'Updated Wallet Name' }

    context 'happy path' do
      it 'returns 200 with updated wallet' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)['wallet']
        expect(body['name']).to eq('Updated Wallet Name')
        expect(body['currency']).to eq(DEFAULT_CURRENCY)
        expect(body['id']).to eq(wallet.id)
      end

      it 'persists updated data in DB' do
        run_test
        expect(wallet.reload.name).to eq('Updated Wallet Name')
      end
    end

    context 'when wallet does not exist' do
      it 'returns 404' do
        patch '/api/v1/wallets/999999', params: { wallet: update_params }, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when wallet belongs to another user' do
      let(:other_user) { create(:user) }
      let(:wallet) { create(:wallet, user: other_user) }

      it 'returns 404' do
        run_test
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when name exceeds max length' do
      let(:new_name) { 'a' * 101 }

      it 'returns 422' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when updating status to suspended' do
      let(:update_params) { { status: 'suspended' } }

      it 'returns 200 with updated status' do
        run_test
        expect(response).to have_http_status(:ok)
        expect(wallet.reload.status).to eq('suspended')
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` business rule — duplicate currency per user (`wallet.rb:10`)

  Suggested test:
  ```ruby
  context 'when user already has a wallet with same currency' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422 and does not create wallet' do
      expect {
        post '/api/v1/wallets', params: params, headers: headers
      }.not_to change(Wallet, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/wallets` field `name` — missing empty string, max length (100), over max length (101)
- [ ] `POST /api/v1/wallets` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/wallets` happy path — missing `id` and `created_at` response field assertions
- [ ] `POST /api/v1/wallets` error scenarios — status-only assertions, no DB-unchanged checks
- [ ] `GET /api/v1/wallets` — no response shape, ordering, scoping, or empty state tests

**LOW** (rare corner cases)

- [ ] `POST /api/v1/wallets` — each valid currency value individually verified

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `wallets_spec.rb` (POST + GET index) | HIGH | Split into separate files |
| Missing entire endpoint test file | PATCH /wallets/:id | HIGH | Create `patch_wallet_spec.rb` |
| Status-only error assertions | `wallets_spec.rb:44,55,63` | MEDIUM | Add DB-unchanged assertions |
| Missing test foundation | `wallets_spec.rb` | MEDIUM | Add `subject(:run_test)`, `DEFAULT_` constants |

### Top 5 Priority Actions

1. **Create test file for PATCH /api/v1/wallets/:id** — entire endpoint is unprotected
2. **Add duplicate currency per user test** — this is a uniqueness constraint that can silently break
3. **Add `name` field edge cases** — max length boundary (100/101) is unverified
4. **Add response shape and ordering tests for GET index** — response contract is unverified
5. **Split into one endpoint per file** for gap visibility

---

## TDD Contract Review: spec/models/wallet_spec.rb

**Test file:** `spec/models/wallet_spec.rb`
**Contract boundary:** `Wallet#deposit!` and `Wallet#withdraw!` (model public API methods)
**Source files:** `app/models/wallet.rb`
**Framework:** Rails 7.1 / RSpec (model spec)

### Overall Score: 6.5 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 6/10 | 25% | 1.50 |
| Test Grouping | 7/10 | 15% | 1.05 |
| Scenario Depth | 5/10 | 20% | 1.00 |
| Test Case Quality | 7/10 | 15% | 1.05 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 8/10 | 10% | 0.80 |
| **Overall** | | | **6.45** |

### Verdict: ADEQUATE

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/models/wallet.rb
Framework: Rails 7.1 / RSpec

Wallet#deposit!(amount):
  - amount must be positive (raises ArgumentError) [HIGH confidence]
  - wallet must be active (raises 'Wallet is not active') [HIGH confidence]
  - increases balance by amount (with_lock) [HIGH confidence]

Wallet#withdraw!(amount):
  - amount must be positive (raises ArgumentError) [HIGH confidence]
  - wallet must be active (raises 'Wallet is not active') [HIGH confidence]
  - balance must be >= amount (raises 'Insufficient balance') [HIGH confidence]
  - decreases balance by amount (with_lock) [HIGH confidence]

Wallet status enum: active, suspended, closed [HIGH confidence]
============================
```

### Test Structure Tree

```
Wallet#deposit!
├── ✓ positive amount → increases balance
├── ✓ negative amount → raises ArgumentError
├── ✓ zero amount → raises ArgumentError
├── field: wallet status
│   ├── ✓ suspended → raises 'Wallet is not active'
│   └── ✗ closed → raises 'Wallet is not active'
└── ✗ concurrent deposits (with_lock behavior)

Wallet#withdraw!
├── ✓ positive amount → decreases balance
├── ✓ negative amount → raises ArgumentError
├── ✗ zero amount → raises ArgumentError
├── ✓ insufficient balance → raises 'Insufficient balance'
├── ✗ exact balance (boundary) → should succeed, balance = 0
├── field: wallet status — NO TESTS
│   ├── ✗ suspended → raises 'Wallet is not active'
│   └── ✗ closed → raises 'Wallet is not active'
└── ✗ concurrent withdrawals (with_lock behavior)
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| deposit! | amount (positive) | HIGH | Yes | positive, negative, zero | -- |
| deposit! | wallet status | HIGH | Yes | suspended | missing: closed |
| withdraw! | amount (positive) | HIGH | Yes | positive, negative | missing: zero |
| withdraw! | balance check | HIGH | Yes | insufficient | missing: exact boundary |
| withdraw! | wallet status | HIGH | No | -- | HIGH: no status tests |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `Wallet#withdraw!` wallet status — no test for suspended or closed wallet (`wallet.rb:27`)

  Suggested test:
  ```ruby
  describe '#withdraw!' do
    context 'when wallet is suspended' do
      before { wallet.update!(status: 'suspended') }

      it 'raises error' do
        expect { wallet.withdraw!(100) }.to raise_error('Wallet is not active')
      end
    end

    context 'when wallet is closed' do
      before { wallet.update!(status: 'closed') }

      it 'raises error' do
        expect { wallet.withdraw!(100) }.to raise_error('Wallet is not active')
      end
    end
  end
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `Wallet#deposit!` — missing closed wallet scenario (only suspended tested)

  Suggested test:
  ```ruby
  context 'when wallet is closed' do
    before { wallet.update!(status: 'closed') }

    it 'raises error' do
      expect { wallet.deposit!(100) }.to raise_error('Wallet is not active')
    end
  end
  ```

- [ ] `Wallet#withdraw!` — missing zero amount and exact balance boundary

  Suggested test:
  ```ruby
  it 'raises on zero amount' do
    expect { wallet.withdraw!(0) }.to raise_error(ArgumentError)
  end

  it 'succeeds when withdrawing exact balance' do
    wallet.withdraw!(1000)
    expect(wallet.reload.balance).to eq(0)
  end
  ```

**LOW** (rare corner cases)

- [ ] Concurrent deposit/withdraw safety (requires integration-level test with threads)

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Incomplete enum coverage | `wallet_spec.rb` | MEDIUM | Test all 3 status values (active, suspended, closed) for both methods |

### Top 5 Priority Actions

1. **Add wallet status tests for `withdraw!`** — suspended and closed states completely untested
2. **Add closed wallet test for `deposit!`** — only suspended is tested, closed is missing
3. **Add zero amount test for `withdraw!`** — boundary case untested
4. **Add exact balance boundary test for `withdraw!`** — `balance == amount` path untested
5. **Consider adding concurrent access tests** — `with_lock` is used but never exercised under contention

---

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

## TDD Contract Review -- Summary

| Test File | Endpoint | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|
| `spec/requests/api/v1/transactions_spec.rb` | POST + GET/:id + GET /transactions | 3.5/10 | WEAK | 7 | 7 |
| `spec/requests/api/v1/wallets_spec.rb` | POST + GET /wallets | 4.3/10 | NEEDS IMPROVEMENT | 2 | 5 |
| `spec/models/wallet_spec.rb` | Wallet#deposit!, Wallet#withdraw! | 6.5/10 | ADEQUATE | 1 | 3 |
| `spec/services/transaction_service_spec.rb` | TransactionService#call | 3.1/10 | WEAK | 5 | 1 |

**Missing test files** (source exists but no test file):
- `PATCH /api/v1/wallets/:id` -- no test file exists (`wallets_controller.rb:30-39`)

**Structural anti-patterns across the suite:**
- 2 test files contain multiple endpoints (should be 1 endpoint per file)
- 1 test file tests the service layer instead of the API endpoint
- 4 tests use implementation testing (method call expectations)
- Status-only assertions are pervasive -- most error tests only check the HTTP status code

**Overall: 4 files reviewed, 15 HIGH gaps, 16 MEDIUM gaps**

**Top 5 global priority actions:**
1. **Add response body + DB assertions to POST /transactions happy path** -- the highest-traffic endpoint has zero output verification
2. **Create test file for PATCH /wallets/:id** -- entire endpoint is unprotected
3. **Add PaymentGateway external API scenarios to POST /transactions** -- payment flow has zero coverage
4. **Delete `transaction_service_spec.rb` and move all scenarios to endpoint-level tests** -- implementation testing provides false confidence
5. **Split multi-endpoint test files** into one file per endpoint for visible gap analysis
