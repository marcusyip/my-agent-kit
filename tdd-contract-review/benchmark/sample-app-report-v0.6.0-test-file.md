Now I have everything needed. Here's the full report.

---

## TDD Contract Review Report

**Scope:** `benchmark/sample-app/spec/requests/api/v1/transactions_spec.rb`
**Framework:** Rails / RSpec (request specs)
**Test files analyzed:** 1
**Source files in scope:** 4 (`transactions_controller.rb`, `transaction.rb`, `wallet.rb`, `transaction_service.rb`)

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

### Overall Score: 3.7 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 4/10 | 10% | 0.40 |
| **Overall** | | | **3.70** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb
        app/models/wallet.rb
Framework: Rails / RSpec

API Contract (inbound):

  POST /api/v1/transactions
    Request params:
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max: 500) [HIGH confidence]
      - category (string, optional, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    Response fields (serialize_transaction):
      - id (integer) [HIGH confidence]
      - amount (string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
      - updated_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422
    Authentication: before_action :authenticate_user!

  GET /api/v1/transactions/:id
    Request params:
      - id (integer, required, path param) [HIGH confidence]
    Response fields: same 9-field serialize_transaction shape [HIGH confidence]
    Status codes: 200, 404
    Authorization: scoped to current_user.transactions [HIGH confidence]

  GET /api/v1/transactions (index)
    Request params:
      - page (integer, optional) [HIGH confidence]
      - per_page (integer, optional, default: 25) [HIGH confidence]
    Response fields:
      - transactions (array of serialized transactions) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200
    Ordering: created_at DESC [HIGH confidence]

DB Contract (Transaction model):
  - user_id (integer, NOT NULL, FK) [HIGH confidence]
  - wallet_id (integer, NOT NULL, FK) [HIGH confidence]
  - amount (decimal(20,8), NOT NULL, > 0, <= 1_000_000) [HIGH confidence]
  - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
  - status (string, NOT NULL, default: 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
  - description (string, nullable, max: 500) [HIGH confidence]
  - category (string, NOT NULL, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]

Business Rules (TransactionService):
  - Wallet must be active (WalletInactiveError → 422) [HIGH confidence]
  - Currency must match wallet currency (CurrencyMismatchError → 422) [HIGH confidence]
  - PaymentGateway.charge called when category == 'payment' [HIGH confidence]

Outbound API (PaymentGateway.charge):
  - amount (decimal) [HIGH confidence]
  - currency (string) [HIGH confidence]
  - user_id (integer) [HIGH confidence]
  - transaction_id (integer) [HIGH confidence]
  - Expected: response with success? method
  - On success: transaction status → 'completed'
  - On failure: transaction status → 'failed'
  - On ChargeError: → 422 error response
============================
```

---

### Test Structure Tree

```
POST /api/v1/transactions
├── test foundation
│   ├── ✗ missing subject(:run_test) — action repeated in every test
│   ├── ✓ let blocks for amount, currency (partial foundation)
│   └── ✗ no DEFAULT_* constants
├── happy path
│   ├── ✓ returns 201 (status only)
│   ├── ✗ response body — should assert all 9 fields (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
│   ├── ✗ DB assertions — should assert Transaction created with correct values
│   └── ✗ side effects — should verify no PaymentGateway call for default category
├── field: amount (request param)
│   ├── ✓ nil → 422 (status only, no DB/side-effect assertion)
│   ├── ✓ negative → 422 (status only, no DB/side-effect assertion)
│   ├── ✗ zero (boundary) → 422
│   ├── ✗ max (1_000_000) → should succeed
│   ├── ✗ over max (1_000_001) → 422
│   └── ✗ non-numeric string → 422
├── field: currency (request param)
│   ├── ✓ nil → 422 (status only)
│   ├── ✓ invalid → 422 (status only)
│   ├── ✗ empty string → 422
│   └── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
├── field: wallet_id (request param)
│   ├── ✓ not found → 422 (status only)
│   ├── ✗ another user's wallet → 422
│   └── ✗ wallet_id nil → 422
├── field: description — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ present → persisted correctly
│   ├── ✗ max length (500) → should succeed
│   └── ✗ over max length (501) → 422
├── field: category — NO TESTS
│   ├── ✗ nil → defaults to 'transfer'
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal)
│   └── ✗ invalid value → 422
├── business: wallet must be active — NO TESTS
│   ├── ✗ suspended wallet → 422
│   └── ✗ closed wallet → 422
├── business: currency must match wallet — NO TESTS
│   └── ✗ mismatch (e.g., send EUR to USD wallet) → 422
├── external: PaymentGateway.charge — NO TESTS
│   ├── ✗ success (category: payment) → transaction status 'completed'
│   ├── ✗ failure → transaction status 'failed'
│   └── ✗ ChargeError → 422
└── auth: unauthenticated request — NO TESTS
    └── ✗ no auth header → 401

GET /api/v1/transactions/:id
├── happy path
│   ├── ✓ returns 200 (status only)
│   └── ✗ response body — should assert all 9 fields
├── field: id (path param)
│   ├── ✓ not found → 404
│   └── ✗ another user's transaction → 404
└── auth: unauthenticated → NO TESTS

GET /api/v1/transactions (index)
├── happy path
│   ├── ✓ returns 200 (status only)
│   ├── ✗ response body — should assert transactions array shape
│   ├── ✗ meta fields (total, page, per_page) — NO ASSERTIONS
│   └── ✗ ordering (created_at DESC) — NO ASSERTIONS
├── field: page — NO TESTS
│   └── ✗ pagination (page 2, per_page override)
├── field: per_page — NO TESTS
│   └── ✗ custom per_page value
├── edge: empty list — NO TESTS
│   └── ✗ no transactions → returns empty array
└── auth: unauthenticated → NO TESTS
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | zero, max, over max, non-numeric |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid value |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | another user's wallet, nil |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (response) | all 9 fields | HIGH | No | -- | HIGH: no response body assertions |
| POST /transactions (DB) | Transaction record | HIGH | No | -- | HIGH: no DB state assertions |
| POST /transactions (business) | wallet active | HIGH | No | -- | HIGH: suspended/closed wallet untested |
| POST /transactions (business) | currency match | HIGH | No | -- | HIGH: currency mismatch untested |
| POST /transactions (external) | PaymentGateway | HIGH | No | -- | HIGH: all scenarios untested |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | HIGH: no response body assertions |
| GET /transactions/:id (auth) | another user's txn | HIGH | No | -- | MEDIUM: authorization gap |
| GET /transactions (response) | transactions + meta | HIGH | No | -- | HIGH: no response/meta assertions |
| GET /transactions (request) | page, per_page | HIGH | No | -- | MEDIUM: pagination untested |

---

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` response body — happy path only checks status code, never asserts any of the 9 response fields

  Suggested test:
  ```ruby
  context 'happy path' do
    subject(:run_test) do
      post '/api/v1/transactions', params: params, headers: headers
    end

    it 'returns 201 with correct response body' do
      run_test
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

    it 'creates a Transaction with correct DB values' do
      expect { run_test }.to change(Transaction, :count).by(1)
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

- [ ] `POST /api/v1/transactions` request field `description` — no test verifies this field

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
    let(:description) { 'Monthly rent payment' }

    context 'when description is present' do
      it 'persists the description' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(Transaction.last.description).to eq('Monthly rent payment')
      end
    end

    context 'when description is nil' do
      let(:description) { nil }

      it 'succeeds with nil description' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when description exceeds max length (500)' do
      let(:description) { 'a' * 501 }

      it 'returns 422 and does not create a transaction' do
        expect { post '/api/v1/transactions', params: params, headers: headers }
          .not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `category` — no test verifies this field

  Suggested test:
  ```ruby
  context 'field: category' do
    let(:params) do
      {
        transaction: {
          amount: amount,
          currency: currency,
          wallet_id: wallet.id,
          category: category_value
        }
      }
    end

    context 'when category is nil' do
      let(:category_value) { nil }

      it 'defaults to transfer' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.category).to eq('transfer')
      end
    end

    %w[transfer payment deposit withdrawal].each do |valid_category|
      context "when category is #{valid_category}" do
        let(:category_value) { valid_category }

        it "creates transaction with category #{valid_category}" do
          post '/api/v1/transactions', params: params, headers: headers
          expect(response).to have_http_status(:created)
          expect(Transaction.last.category).to eq(valid_category)
        end
      end
    end

    context 'when category is invalid' do
      let(:category_value) { 'refund' }

      it 'returns 422 and does not create a transaction' do
        expect { post '/api/v1/transactions', params: params, headers: headers }
          .not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: wallet must be active — suspended/closed wallets untested

  Suggested test:
  ```ruby
  context 'field: wallet status (DB data state)' do
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
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: currency must match wallet — mismatch untested

  Suggested test:
  ```ruby
  context 'field: currency match with wallet' do
    context 'when currency does not match wallet currency' do
      let(:currency) { 'EUR' } # wallet is USD

      it 'returns 422 and does not create a transaction' do
        expect { post '/api/v1/transactions', params: params, headers: headers }
          .not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['details']).to include('Currency must match wallet currency')
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external: PaymentGateway.charge — all scenarios untested

  Suggested test:
  ```ruby
  context 'field: PaymentGateway.charge (external API, category: payment)' do
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
          .and_return(OpenStruct.new(success?: true))
      end

      it 'creates transaction with status completed' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('completed')
      end

      it 'sends correct params to gateway' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(PaymentGateway).to have_received(:charge).with(
          hash_including(amount: 100.50, currency: 'USD')
        )
      end
    end

    context 'when gateway returns failure' do
      before do
        allow(PaymentGateway).to receive(:charge)
          .and_return(OpenStruct.new(success?: false))
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

      it 'returns 422 and does not complete transaction' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Payment processing failed')
      end
    end
  end
  ```

- [ ] `GET /api/v1/transactions` response body — no assertions on transactions array or meta fields

  Suggested test:
  ```ruby
  describe 'GET /api/v1/transactions' do
    it 'returns transactions with correct response shape and meta' do
      create_list(:transaction, 3, user: user, wallet: wallet)
      get '/api/v1/transactions', headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['transactions'].length).to eq(3)
      expect(body['transactions'].first.keys).to match_array(
        %w[id amount currency status description category wallet_id created_at updated_at]
      )
      expect(body['meta']).to include('total' => 3, 'page' => 1, 'per_page' => 25)
    end
  end
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` field `amount` — missing zero boundary, max (1_000_000), over max (1_000_001), non-numeric
- [ ] `POST /api/v1/transactions` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/transactions` field `wallet_id` — missing another user's wallet → 422
- [ ] `POST /api/v1/transactions` error tests — all assert status only, none verify `Transaction.count` unchanged or no side effects
- [ ] `GET /api/v1/transactions/:id` — no response body assertions, missing another user's transaction → 404
- [ ] `GET /api/v1/transactions` — no pagination tests (page, per_page), no empty list, no ordering assertion

**LOW** (rare corner cases)

- [ ] `POST /api/v1/transactions` — unauthenticated request → 401
- [ ] `GET /api/v1/transactions/:id` — unauthenticated request → 401
- [ ] `GET /api/v1/transactions` — unauthenticated request → 401
- [ ] `Transaction` status enum value `reversed` — no scenario exercises this state

---

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `transactions_spec.rb` (POST, GET/:id, GET index) | HIGH | Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb` |
| Status-code-only assertions | `transactions_spec.rb:32-88` (all 7 test cases) | HIGH | Add response body, DB state, and side-effect assertions to every test |
| No test foundation | `transactions_spec.rb:17` | MEDIUM | Add `subject(:run_test)`, `DEFAULT_*` constants, so each test overrides one field |
| Repeated action in every test | `transactions_spec.rb:33,42,50,59,68,85` | MEDIUM | Extract to `subject(:run_test)` |
| Error tests don't verify no-side-effects | `transactions_spec.rb:38-88` | HIGH | Assert `Transaction.count` unchanged, no PaymentGateway calls on error paths |

---

### Top 5 Priority Actions

1. **Add response body + DB assertions to POST happy path** — Without these, any change to the serializer or service silently breaks the contract. Currently the most impactful gap: 9 response fields and 7 DB fields are completely unverified.

2. **Add PaymentGateway.charge tests (success/failure/ChargeError)** — The entire payment flow is untested. A broken gateway integration would ship with no test failures. Mock only this external boundary.

3. **Add description and category field scenarios** — Two permitted params with validations (max length 500, enum with 4 values, default behavior) have zero test coverage. Changes to these fields break silently.

4. **Add wallet business rule tests (suspended/closed wallet, currency mismatch)** — Three distinct error paths in TransactionService are completely untested. These protect against billing users with frozen wallets.

5. **Split into one-endpoint-per-file and add test foundation** — The current structure hides gaps. Splitting into 3 files with `subject(:run_test)` and `DEFAULT_*` constants makes every missing scenario immediately visible in the file tree.
