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
