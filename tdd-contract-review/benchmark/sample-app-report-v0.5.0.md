## TDD Contract Review Report

**Scope:** `benchmark/sample-app/`
**Framework:** Rails 7.1 / RSpec (request + model specs)
**Test files analyzed:** 4
**Source files in scope:** 6 (3 controllers/services, 3 models)

### Overall Score: 3.6 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 3/10 | 15% | 0.45 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 3/10 | 15% | 0.45 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.60** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================

Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):

  POST /api/v1/transactions
    Request params:
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max 500) [HIGH confidence]
      - category (string, optional, default: transfer, enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
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
    Business rules:
      - Wallet must belong to current_user [HIGH confidence]
      - Wallet must be active (not suspended/closed) [HIGH confidence]
      - Currency must match wallet currency [HIGH confidence]
      - Payment category triggers PaymentGateway.charge [HIGH confidence]

  GET /api/v1/transactions/:id
    Request params:
      - id (integer, required) [HIGH confidence]
    Response fields: same 9-field transaction shape [HIGH confidence]
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

Source: app/controllers/api/v1/wallets_controller.rb

  POST /api/v1/wallets
    Request params:
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - name (string, required, max 100) [HIGH confidence]
      - status (string, optional) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string, decimal-as-string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401

  GET /api/v1/wallets
    Response fields:
      - wallets (array of wallet objects) [HIGH confidence]
    Status codes: 200, 401

  PATCH /api/v1/wallets/:id
    Request params:
      - currency (string, optional) [HIGH confidence]
      - name (string, optional) [HIGH confidence]
      - status (string, optional) [HIGH confidence]
    Response fields: same 6-field wallet shape [HIGH confidence]
    Status codes: 200, 404, 422, 401

DB Contract:

  Transaction model:
    - user_id (integer, NOT NULL, FK) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK) [HIGH confidence]
    - amount (decimal, NOT NULL, > 0, <= 1_000_000) [HIGH confidence]
    - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - status (string, NOT NULL, enum: pending/completed/failed/reversed, default: pending) [HIGH confidence]
    - description (string, nullable, max 500) [HIGH confidence]
    - category (string, NOT NULL, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]

  Wallet model:
    - user_id (integer, NOT NULL, FK) [HIGH confidence]
    - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
    - name (string, NOT NULL, max 100) [HIGH confidence]
    - balance (decimal, NOT NULL, >= 0, default: 0) [HIGH confidence]
    - status (string, NOT NULL, enum: active/suspended/closed, default: active) [HIGH confidence]

  User model:
    - email (string, NOT NULL, unique, email format) [HIGH confidence]
    - name (string, NOT NULL, max 255) [HIGH confidence]

Model Methods:
  Wallet#deposit!(amount):
    - amount must be positive [HIGH confidence]
    - wallet must be active [HIGH confidence]
    - increases balance by amount (with lock) [HIGH confidence]

  Wallet#withdraw!(amount):
    - amount must be positive [HIGH confidence]
    - wallet must be active [HIGH confidence]
    - balance must be >= amount [HIGH confidence]
    - decreases balance by amount (with lock) [HIGH confidence]

Outbound API:
  PaymentGateway.charge:
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
    - On success: transaction.status → completed [HIGH confidence]
    - On failure: transaction.status → failed [HIGH confidence]
    - Can raise PaymentGateway::ChargeError [HIGH confidence]
============================
```

---

### Test Structure Tree

```
POST /api/v1/transactions
├── test foundation
│   ├── ✗ no DEFAULT constants
│   ├── ✗ no subject(:run_test) — post call repeated in every test
│   └── ✗ description/category not in default params
├── happy path
│   ├── ✓ returns 201
│   ├── ✗ response body — 9 fields unasserted
│   ├── ✗ DB state — Transaction created with correct values
│   └── ✗ side effects — no assertion on PaymentGateway (if payment)
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero (boundary) → 422
│   ├── ✗ max (1_000_000) → should succeed
│   ├── ✗ over max (1_000_001) → 422
│   └── ✗ non-numeric string → 422
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string → 422
│   └── ✗ each valid value (USD/EUR/GBP/BTC/ETH) verified
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   ├── ✗ another user's wallet → 422
│   └── ✗ wallet not owned by current user (authorization)
├── field: description — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length (500) → should succeed
│   └── ✗ over max length (501) → 422
├── field: category — NO TESTS
│   ├── ✗ nil (defaults to transfer)
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal)
│   └── ✗ invalid value → 422
├── business: wallet must be active
│   ├── ✗ suspended wallet → 422
│   └── ✗ closed wallet → 422
├── business: currency must match wallet
│   └── ✗ mismatch → 422
├── response body — NO ASSERTIONS
│   └── ✗ happy path should assert all 9 response fields
├── DB assertions
│   └── ✗ happy path should assert Transaction created with correct field values
└── external: PaymentGateway.charge — NO TESTS
    ├── ✗ payment category + success → status completed
    ├── ✗ payment category + failure → status failed
    ├── ✗ PaymentGateway::ChargeError → 422
    └── ✗ non-payment category → no gateway call

GET /api/v1/transactions/:id
├── ✓ returns 200
├── ✗ response body — 9 fields unasserted
├── ✓ not found → 404
└── ✗ another user's transaction (authorization)

GET /api/v1/transactions
├── ✓ returns 200
├── ✗ response body shape (transactions array + meta)
├── ✗ pagination: page param
├── ✗ pagination: per_page param
├── ✗ ordering (created_at desc)
└── ✗ empty state (no transactions)

POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ DB count +1
│   ├── ✓ response: currency
│   ├── ✓ response: name
│   ├── ✓ response: balance (0.0)
│   ├── ✓ response: status (active)
│   ├── ✗ response: id — unasserted
│   └── ✗ response: created_at — unasserted
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value verified
│   └── ✗ duplicate currency per user → 422
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100) → should succeed
│   └── ✗ over max length (101) → 422
├── field: status (request param)
│   └── ✗ no tests at all
└── error cases
    └── ✗ no DB assertion on error (count unchanged)

GET /api/v1/wallets
├── ✓ returns 200
├── ✗ response body shape (wallets array)
├── ✗ ordering (by currency)
└── ✗ empty state

PATCH /api/v1/wallets/:id — NO TESTS
├── ✗ happy path (update name)
├── ✗ happy path (update status)
├── ✗ not found → 404
├── ✗ invalid params → 422
├── ✗ another user's wallet → 404
├── ✗ response body assertions
└── ✗ DB state assertions

Wallet#deposit!
├── ✓ positive amount → increases balance
├── ✓ negative amount → raises ArgumentError
├── ✓ zero amount → raises ArgumentError
├── ✓ suspended wallet → raises error
└── ✗ closed wallet → raises error

Wallet#withdraw!
├── ✓ positive amount → decreases balance
├── ✓ negative amount → raises ArgumentError
├── ✓ insufficient balance → raises error
├── ✗ zero amount → raises ArgumentError
├── ✗ exact balance (boundary) → should succeed
├── ✗ suspended wallet → raises error
└── ✗ closed wallet → raises error
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (req) | amount | HIGH | Yes | nil, negative | zero, max, over-max, non-numeric |
| POST /transactions (req) | currency | HIGH | Yes | nil, invalid | empty string, valid values |
| POST /transactions (req) | wallet_id | HIGH | Yes | not found | another user's wallet |
| POST /transactions (req) | description | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (req) | category | HIGH | No | -- | HIGH: entirely untested |
| POST /transactions (resp) | all 9 fields | HIGH | No | -- | HIGH: no response assertions |
| POST /transactions (DB) | all fields | HIGH | No | -- | HIGH: no DB state assertions |
| POST /transactions (biz) | wallet active | HIGH | No | -- | HIGH: suspended, closed |
| POST /transactions (biz) | currency match | HIGH | No | -- | HIGH: mismatch |
| POST /transactions (ext) | PaymentGateway | HIGH | No | -- | HIGH: success, failure, error |
| GET /transactions/:id (resp) | all 9 fields | HIGH | No | -- | HIGH: no response assertions |
| GET /transactions/:id (auth) | ownership | HIGH | No | -- | MEDIUM: another user's txn |
| GET /transactions (resp) | shape + meta | HIGH | No | -- | MEDIUM: no response/pagination assertions |
| POST /wallets (req) | currency | HIGH | Yes | nil, invalid | empty, duplicate per user |
| POST /wallets (req) | name | HIGH | Yes | nil | empty, max length |
| POST /wallets (req) | status | HIGH | No | -- | MEDIUM: not tested |
| POST /wallets (resp) | id, created_at | HIGH | No | -- | LOW: 2 fields unasserted |
| GET /wallets (resp) | shape | HIGH | No | -- | MEDIUM: no response assertions |
| PATCH /wallets/:id | entire endpoint | HIGH | No | -- | HIGH: zero tests |
| Wallet#deposit! | closed wallet | HIGH | No | -- | MEDIUM: missing enum value |
| Wallet#withdraw! | zero, boundary, status | HIGH | No | -- | MEDIUM: multiple gaps |

---

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `spec/requests/api/v1/transactions_spec.rb` (POST + GET + GET/:id) | HIGH | Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb` |
| Multiple endpoints in one file | `spec/requests/api/v1/wallets_spec.rb` (POST + GET) | HIGH | Split into `post_wallets_spec.rb`, `get_wallets_spec.rb` |
| Implementation testing | `spec/services/transaction_service_spec.rb:12-25` — expects `receive(:build_transaction)`, `receive(:validate_wallet_active!)`, `receive(:validate_currency_match!)` | HIGH | Delete service spec; test through POST /api/v1/transactions endpoint |
| Service layer tested separately | `spec/services/transaction_service_spec.rb` | HIGH | The API endpoint is the contract boundary, not the service |
| No test foundation | `spec/requests/api/v1/transactions_spec.rb` | MEDIUM | Add DEFAULT constants, `subject(:run_test)`, include description/category in default params |
| Status-code-only assertions | `spec/requests/api/v1/transactions_spec.rb:32-88` — 6 tests assert only HTTP status | MEDIUM | Add response body + DB state assertions |
| Assert-free test for response body | `spec/requests/api/v1/transactions_spec.rb:100` — "returns the transaction" checks only status | MEDIUM | Assert all 9 response fields |

---

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 8 gaps)

- [ ] `POST /api/v1/transactions` fields `description` and `category` — zero test coverage for two permitted params

  Suggested test:
  ```ruby
  # In post_transactions_spec.rb, add to params foundation:
  let(:description) { 'Test transaction' }
  let(:category) { 'transfer' }
  let(:params) do
    {
      transaction: {
        amount: amount, currency: currency, wallet_id: wallet.id,
        description: description, category: category
      }
    }
  end

  context 'field: description' do
    context 'when nil' do
      let(:description) { nil }

      it 'succeeds (optional field)' do
        run_test
        expect(response).to have_http_status(:created)
      end
    end

    context 'when at max length (500)' do
      let(:description) { 'a' * 500 }

      it 'succeeds' do
        run_test
        expect(response).to have_http_status(:created)
      end
    end

    context 'when over max length (501)' do
      let(:description) { 'a' * 501 }

      it 'returns 422 and does not create a transaction' do
        expect { run_test }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  context 'field: category' do
    context 'when nil (defaults to transfer)' do
      let(:category) { nil }

      it 'succeeds with default category' do
        run_test
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['transaction']['category']).to eq('transfer')
      end
    end

    %w[transfer payment deposit withdrawal].each do |valid_category|
      context "when #{valid_category}" do
        let(:category) { valid_category }

        it 'succeeds' do
          allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) if valid_category == 'payment'
          run_test
          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)
          expect(body['transaction']['category']).to eq(valid_category)
        end
      end
    end

    context 'when invalid' do
      let(:category) { 'invalid_category' }

      it 'returns 422 and does not create a transaction' do
        expect { run_test }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` happy path — no response body or DB state assertions (9 response fields, all DB fields unverified)

  Suggested test:
  ```ruby
  context 'happy path' do
    it 'returns 201 with correct response fields' do
      run_test
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)['transaction']
      expect(body['amount']).to eq(DEFAULT_AMOUNT)
      expect(body['currency']).to eq(DEFAULT_CURRENCY)
      expect(body['status']).to eq('pending')
      expect(body['description']).to eq('Test transaction')
      expect(body['category']).to eq('transfer')
      expect(body['wallet_id']).to eq(wallet.id)
      expect(body['id']).to be_present
      expect(body['created_at']).to be_present
      expect(body['updated_at']).to be_present
    end

    it 'persists correct data in DB' do
      expect { run_test }.to change(Transaction, :count).by(1)
      txn = Transaction.last
      expect(txn.user_id).to eq(user.id)
      expect(txn.wallet_id).to eq(wallet.id)
      expect(txn.amount).to eq(BigDecimal(DEFAULT_AMOUNT))
      expect(txn.currency).to eq(DEFAULT_CURRENCY)
      expect(txn.status).to eq('pending')
      expect(txn.category).to eq('transfer')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: wallet must be active — suspended and closed wallet states untested

  Suggested test:
  ```ruby
  context 'field: wallet status (DB state)' do
    context 'when wallet is suspended' do
      before { wallet.update!(status: 'suspended') }

      it 'returns 422 and does not create a transaction' do
        expect { run_test }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when wallet is closed' do
      before { wallet.update!(status: 'closed') }

      it 'returns 422 and does not create a transaction' do
        expect { run_test }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: currency must match wallet — mismatch scenario untested

  Suggested test:
  ```ruby
  context 'field: currency mismatch with wallet' do
    let(:currency) { 'EUR' }  # wallet is USD

    it 'returns 422 and does not create a transaction' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to include('Currency does not match wallet')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external API: `PaymentGateway.charge` — no tests for success, failure, or ChargeError

  Suggested test:
  ```ruby
  context 'field: PaymentGateway (external API, category: payment)' do
    let(:category) { 'payment' }

    context 'when gateway succeeds' do
      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

      it 'creates transaction with status completed' do
        run_test
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('completed')
      end
    end

    context 'when gateway fails' do
      before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: false)) }

      it 'creates transaction with status failed' do
        run_test
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('failed')
      end
    end

    context 'when gateway raises ChargeError' do
      before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError, 'Gateway down') }

      it 'returns 422 and includes error message' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Payment processing failed')
      end
    end
  end
  ```

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint has zero tests

  Suggested test:
  ```ruby
  # spec/requests/api/v1/patch_wallet_spec.rb
  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    DEFAULT_NAME = 'My USD Wallet'

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet_id}", params: { wallet: params }, headers: headers
    end

    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let!(:wallet) { create(:wallet, user: user, currency: 'USD', name: DEFAULT_NAME) }
    let(:wallet_id) { wallet.id }
    let(:params) { { name: new_name } }
    let(:new_name) { 'Updated Wallet' }

    context 'happy path' do
      it 'returns 200 with updated wallet' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)['wallet']
        expect(body['name']).to eq('Updated Wallet')
        expect(body['currency']).to eq('USD')
        expect(body['id']).to eq(wallet.id)
      end

      it 'persists the update in DB' do
        run_test
        expect(wallet.reload.name).to eq('Updated Wallet')
      end
    end

    context 'when wallet not found' do
      let(:wallet_id) { 999_999 }

      it 'returns 404' do
        run_test
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when name is invalid (too long)' do
      let(:new_name) { 'a' * 101 }

      it 'returns 422 and does not update' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
        expect(wallet.reload.name).to eq(DEFAULT_NAME)
      end
    end

    context 'when updating status to suspended' do
      let(:params) { { status: 'suspended' } }

      it 'returns 200 and updates status' do
        run_test
        expect(response).to have_http_status(:ok)
        expect(wallet.reload.status).to eq('suspended')
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` field `currency` — duplicate currency per user untested (unique constraint)

  Suggested test:
  ```ruby
  context 'when user already has a wallet with this currency' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422 and does not create a wallet' do
      expect { run_test }.not_to change(Wallet, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `spec/services/transaction_service_spec.rb` — tests implementation (method call expectations), not contracts. Should be deleted; coverage should come from API endpoint tests.

**MEDIUM** (tested but missing scenarios — 7 gaps)

- [ ] `POST /api/v1/transactions` field `amount` — missing zero (boundary), max (1_000_000), over-max (1_000_001), non-numeric
- [ ] `POST /api/v1/transactions` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/transactions` field `wallet_id` — missing another user's wallet (authorization)
- [ ] `GET /api/v1/transactions/:id` — no response body assertions, no authorization test (another user's transaction)
- [ ] `GET /api/v1/transactions` — no response shape/pagination/ordering assertions
- [ ] `Wallet#withdraw!` — missing zero amount, exact balance boundary, suspended/closed wallet
- [ ] `Wallet#deposit!` — missing closed wallet enum value

**LOW** (minor gaps — 3 gaps)

- [ ] `POST /wallets` happy path missing `id` and `created_at` response field assertions
- [ ] `POST /wallets` field `name` — missing empty string, max length boundary
- [ ] `GET /wallets` — no response shape or ordering assertions

---

### Top 5 Priority Actions

1. **Add happy path assertions for POST /api/v1/transactions** — assert all 9 response fields + DB state. This single test protects the most critical contract in the app and currently has zero field-level verification.

2. **Add PaymentGateway external API scenarios** — the payment flow (success → completed, failure → failed, ChargeError → 422) is completely untested. This is a money path with no safety net.

3. **Create test file for PATCH /api/v1/wallets/:id** — an entire endpoint with zero coverage. Any change to wallet update logic is undetectable by tests.

4. **Add description and category field scenarios for POST /api/v1/transactions** — two permitted params with validation rules (max 500 chars, enum values) and a default value, all completely untested.

5. **Delete `transaction_service_spec.rb` and add wallet-active/currency-mismatch scenarios to the POST endpoint test** — the service spec tests implementation details (`expect(service).to receive(:build_transaction)`), giving false confidence. Replace with contract-level tests at the API boundary that verify suspended wallet → 422 and currency mismatch → 422.
