## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/services/transaction_service.rb, app/models/transaction.rb
**Framework:** Rails / RSpec (request spec)

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

### Overall Score: 3.6 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.60** |

### Verdict: WEAK

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb
Framework: Rails / RSpec

API Contract -- POST /api/v1/transactions:
  Request params (from transaction_params + TransactionService):
    - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - wallet_id (integer, required) [HIGH confidence]
    - description (string, optional, max 500 chars) [HIGH confidence]
    - category (string, optional, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
  Response fields (serialize_transaction):
    - id (integer) [HIGH confidence]
    - amount (string) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - description (string) [HIGH confidence]
    - category (string) [HIGH confidence]
    - wallet_id (integer) [HIGH confidence]
    - created_at (string, iso8601) [HIGH confidence]
    - updated_at (string, iso8601) [HIGH confidence]
  Status codes: 201, 422, 401
  Business rules:
    - Wallet must exist and belong to current_user (set_wallet before_action) [HIGH confidence]
    - Wallet must be active -- not suspended/closed (TransactionService#validate_wallet_active!) [HIGH confidence]
    - Currency must match wallet currency (TransactionService#validate_currency_match!) [HIGH confidence]
    - Category 'payment' triggers PaymentGateway.charge [HIGH confidence]
    - Transaction created with initial status 'pending' [HIGH confidence]

API Contract -- GET /api/v1/transactions/:id:
  Request params:
    - id (integer, required, path param) [HIGH confidence]
  Response fields: same as serialize_transaction (9 fields) [HIGH confidence]
  Status codes: 200, 404, 401
  Business rules:
    - Only returns current_user's transactions (scoped find) [HIGH confidence]

API Contract -- GET /api/v1/transactions (index):
  Request params:
    - page (integer, optional) [HIGH confidence]
    - per_page (integer, optional, default: 25) [HIGH confidence]
  Response fields:
    - transactions (array of serialize_transaction objects) [HIGH confidence]
    - meta.total (integer) [HIGH confidence]
    - meta.page (integer) [HIGH confidence]
    - meta.per_page (integer) [HIGH confidence]
  Status codes: 200, 401
  Business rules:
    - Only returns current_user's transactions [HIGH confidence]
    - Ordered by created_at desc [HIGH confidence]

DB Contract -- Transaction model:
  - user_id (integer, NOT NULL, FK) [HIGH confidence]
  - wallet_id (integer, NOT NULL, FK) [HIGH confidence]
  - amount (decimal(20,8), NOT NULL, > 0, <= 1_000_000) [HIGH confidence]
  - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
  - status (string, NOT NULL, default: 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
  - description (string, nullable, max 500) [HIGH confidence]
  - category (string, NOT NULL, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]

Outbound API -- PaymentGateway.charge (triggered when category == 'payment'):
  Request:
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
  Behavior:
    - success? true -> transaction status updated to 'completed' [HIGH confidence]
    - success? false -> transaction status updated to 'failed' [HIGH confidence]
    - ChargeError raised -> returns 422 with error details [HIGH confidence]
============================
```

### Test Structure Tree

```
POST /api/v1/transactions
├── test foundation -- MISSING
│   ├── ✗ no DEFAULT constants
│   ├── ✗ no subject(:run_test) -- post call repeated in every test
│   └── ✗ params do not include description or category
├── happy path
│   ├── ✓ returns 201 (status only)
│   ├── ✗ response body: id
│   ├── ✗ response body: amount
│   ├── ✗ response body: currency
│   ├── ✗ response body: status
│   ├── ✗ response body: description
│   ├── ✗ response body: category
│   ├── ✗ response body: wallet_id
│   ├── ✗ response body: created_at
│   ├── ✗ response body: updated_at
│   ├── ✗ DB: Transaction.count increases by 1
│   ├── ✗ DB: Transaction created with correct user_id
│   ├── ✗ DB: Transaction created with correct wallet_id
│   ├── ✗ DB: Transaction created with correct amount
│   ├── ✗ DB: Transaction created with correct currency
│   └── ✗ DB: Transaction created with correct status (pending)
├── field: amount (request param, required, > 0, <= 1_000_000)
│   ├── ✓ nil -> 422
│   ├── ✓ negative -> 422
│   ├── ✗ zero (boundary) -> 422
│   ├── ✗ at max (1_000_000) -> 201
│   ├── ✗ over max (1_000_001) -> 422
│   ├── ✗ non-numeric string -> 422
│   └── ✗ error paths: no DB write assertions
├── field: currency (request param, required, in: USD/EUR/GBP/BTC/ETH)
│   ├── ✓ nil -> 422
│   ├── ✓ invalid value -> 422
│   ├── ✗ empty string -> 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ error paths: no DB write assertions
├── field: wallet_id (request param, required)
│   ├── ✓ not found -> 422
│   ├── ✗ belongs to another user -> 422
│   └── ✗ error paths: no DB write assertions
├── field: description -- NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ present value appears in response
│   ├── ✗ at max length (500) -> 201
│   ├── ✗ over max length (501) -> 422
│   └── ✗ empty string -> 201
├── field: category -- NO TESTS
│   ├── ✗ omitted (defaults to 'transfer')
│   ├── ✗ each valid value (transfer, payment, deposit, withdrawal)
│   ├── ✗ invalid value -> 422
│   └── ✗ nil -> defaults to 'transfer'
├── business: wallet must be active -- NO TESTS
│   ├── ✗ suspended wallet -> 422, no DB write
│   └── ✗ closed wallet -> 422, no DB write
├── business: currency must match wallet -- NO TESTS
│   └── ✗ mismatch -> 422, no DB write
└── external: PaymentGateway.charge -- NO TESTS
    ├── ✗ payment category + success -> transaction status 'completed'
    ├── ✗ payment category + failure -> transaction status 'failed'
    ├── ✗ payment category + ChargeError -> 422
    └── ✗ non-payment category -> PaymentGateway not called

GET /api/v1/transactions/:id
├── happy path
│   ├── ✓ returns 200 (status only)
│   └── ✗ response body: all 9 fields verified
├── field: id (path param)
│   ├── ✓ not found -> 404
│   └── ✗ belongs to another user -> 404
└── response body -- NO ASSERTIONS
    └── ✗ happy path should assert all 9 response fields

GET /api/v1/transactions (index)
├── happy path
│   ├── ✓ returns 200 (status only)
│   ├── ✗ response: transactions array shape
│   ├── ✗ response: meta.total
│   ├── ✗ response: meta.page
│   └── ✗ response: meta.per_page
├── field: page (query param) -- NO TESTS
│   └── ✗ pagination behavior
├── field: per_page (query param) -- NO TESTS
│   ├── ✗ default value (25)
│   └── ✗ custom value
├── business: ordering -- NO TESTS
│   └── ✗ ordered by created_at desc
└── business: scoping -- NO TESTS
    └── ✗ only returns current user's transactions
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | zero, max, over-max, non-numeric |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid value |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | another user's wallet |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (response) | all 9 fields | HIGH | No | -- | HIGH: no response body assertions |
| POST /transactions (DB) | all fields | HIGH | No | -- | HIGH: no DB state assertions |
| POST /transactions (business) | wallet active | HIGH | No | -- | HIGH: suspended/closed untested |
| POST /transactions (business) | currency match | HIGH | No | -- | HIGH: mismatch untested |
| POST /transactions (external) | PaymentGateway | HIGH | No | -- | HIGH: all scenarios untested |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | MEDIUM: status only |
| GET /transactions/:id (request) | id | HIGH | Partial | not found | another user's |
| GET /transactions (response) | transactions + meta | HIGH | No | -- | MEDIUM: no shape assertions |
| GET /transactions (request) | page, per_page | HIGH | No | -- | MEDIUM: pagination untested |
| GET /transactions (business) | ordering | HIGH | No | -- | MEDIUM: ordering untested |
| GET /transactions (business) | user scoping | HIGH | No | -- | MEDIUM: scoping untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` response body -- no test asserts any of the 9 response fields

  Suggested test:
  ```ruby
  context 'happy path' do
    it 'returns transaction with all fields' do
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

    it 'persists transaction with correct DB values' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.to change(Transaction, :count).by(1)

      txn = Transaction.last
      expect(txn.user_id).to eq(user.id)
      expect(txn.wallet_id).to eq(wallet.id)
      expect(txn.amount).to eq(100.50.to_d)
      expect(txn.currency).to eq('USD')
      expect(txn.status).to eq('pending')
      expect(txn.category).to eq('transfer')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `description` -- entirely untested

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

    context 'when present' do
      it 'returns 201 with description in response' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['transaction']['description']).to eq('Monthly rent payment')
      end
    end

    context 'when nil' do
      let(:description) { nil }

      it 'returns 201 (description is optional)' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.description).to be_nil
      end
    end

    context 'when at max length (500 chars)' do
      let(:description) { 'a' * 500 }

      it 'succeeds' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when over max length (501 chars)' do
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

- [ ] `POST /api/v1/transactions` request field `category` -- entirely untested

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

    context 'when omitted (defaults to transfer)' do
      let(:params) do
        { transaction: { amount: amount, currency: currency, wallet_id: wallet.id } }
      end

      it 'creates transaction with category transfer' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['transaction']['category']).to eq('transfer')
      end
    end

    %w[transfer payment deposit withdrawal].each do |valid_category|
      context "when #{valid_category}" do
        let(:category) { valid_category }

        it 'returns 201 with correct category' do
          allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) if valid_category == 'payment'
          post '/api/v1/transactions', params: params, headers: headers
          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)
          expect(body['transaction']['category']).to eq(valid_category)
        end
      end
    end

    context 'when invalid value' do
      let(:category) { 'refund' }

      it 'returns 422 and does not create transaction' do
        expect {
          post '/api/v1/transactions', params: params, headers: headers
        }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: wallet must be active -- suspended/closed untested

  Suggested test:
  ```ruby
  context 'field: wallet status (DB state)' do
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

- [ ] `POST /api/v1/transactions` business rule: currency must match wallet -- mismatch untested

  Suggested test:
  ```ruby
  context 'field: currency mismatch with wallet' do
    let(:currency) { 'EUR' }  # wallet is USD

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to include('Currency does not match wallet')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external API: PaymentGateway.charge -- all scenarios untested

  Suggested test:
  ```ruby
  context 'external: PaymentGateway.charge (when category is payment)' do
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

      it 'creates transaction with status completed' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('completed')
      end

      it 'calls PaymentGateway with correct params' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(PaymentGateway).to have_received(:charge).with(
          hash_including(amount: 100.50.to_d, currency: 'USD')
        )
      end
    end

    context 'when gateway returns failure' do
      before do
        allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
      end

      it 'creates transaction with status failed' do
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

    context 'when category is not payment' do
      let(:params) do
        {
          transaction: {
            amount: amount, currency: currency, wallet_id: wallet.id,
            category: 'transfer'
          }
        }
      end

      it 'does not call PaymentGateway' do
        allow(PaymentGateway).to receive(:charge)
        post '/api/v1/transactions', params: params, headers: headers
        expect(PaymentGateway).not_to have_received(:charge)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` wallet belongs to another user -- untested

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

    it 'returns 422 and does not create transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `GET /api/v1/transactions/:id` response body -- no assertions on any field

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

- [ ] `GET /api/v1/transactions` response shape -- no assertions on array or meta

  Suggested test:
  ```ruby
  it 'returns transactions with pagination meta' do
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

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` field `amount` -- missing zero boundary, max (1_000_000), over-max (1_000_001), non-numeric string
- [ ] `POST /api/v1/transactions` field `currency` -- missing empty string edge case
- [ ] `POST /api/v1/transactions` field `wallet_id` -- missing: belongs to another user
- [ ] `POST /api/v1/transactions` error paths -- none assert no DB write (`.not_to change(Transaction, :count)`)
- [ ] `GET /api/v1/transactions/:id` -- missing: transaction belongs to another user -> 404
- [ ] `GET /api/v1/transactions` -- missing: pagination params, ordering verification, user scoping

**LOW** (rare corner cases)

- [ ] `POST /api/v1/transactions` field `amount` -- non-numeric string, extremely large value
- [ ] `GET /api/v1/transactions` -- empty state (no transactions returns empty array)
- [ ] Transaction status enum value `reversed` -- never exercised in any test

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | transactions_spec.rb (POST, GET/:id, GET index) | HIGH | Split into post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb |
| Status-only assertions | transactions_spec.rb:33,42,49,59,68,86,101,108,119 | HIGH | Assert response body, DB state, and side effects |
| No test foundation | transactions_spec.rb:17-94 | HIGH | Add DEFAULT constants, subject(:run_test), include description/category in params |
| Missing DB write assertions in error paths | transactions_spec.rb:38-89 | MEDIUM | Add `.not_to change(Transaction, :count)` in error contexts |
| `post` call repeated in every test | transactions_spec.rb:33,42,49,59,68,86 | MEDIUM | Extract to `subject(:run_test)` |

### Top 5 Priority Actions

1. **Add response body + DB assertions to POST happy path** -- the core transaction creation endpoint only checks status 201. All 9 response fields and DB state are unverified. Highest breakage risk.
2. **Add PaymentGateway external API scenarios** -- the payment flow triggers an external API that changes transaction status (pending -> completed/failed). Zero test coverage on this critical integration.
3. **Add description and category field test groups** -- two entirely untested request params with validation rules (max length 500, enum with 4 values, default value) that can break silently.
4. **Add wallet business rule tests** (suspended/closed wallet, currency mismatch, another user's wallet) -- four business rules enforced in TransactionService and the controller have zero test coverage.
5. **Split into one endpoint per file** -- the multi-endpoint file structure hides gaps; splitting makes missing coverage immediately visible in the file tree.
