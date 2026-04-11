Now I have all the information needed to produce the full report.

## TDD Contract Review Report

**Scope:** `benchmark/sample-app/`
**Framework:** Rails 7.1 / RSpec (request specs + model specs)
**Test files analyzed:** 3
**Source files in scope:** 6

---

### Overall Score: 3.8 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 3/10 | 15% | 0.45 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 2/10 | 10% | 0.20 |
| **Overall** | | | **3.80** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================

Source: app/controllers/api/v1/transactions_controller.rb
        app/services/transaction_service.rb
        app/models/transaction.rb

API Contract (inbound):
  POST /api/v1/transactions
    Request params:
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max 500 chars) [HIGH confidence]
      - category (string, optional, in: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]
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
      - Wallet must belong to current_user [HIGH confidence]
      - Wallet must be active (not suspended/closed) [HIGH confidence]
      - Currency must match wallet currency [HIGH confidence]
      - Payment category triggers PaymentGateway.charge [HIGH confidence]

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [HIGH confidence]
      - per_page (integer, optional, default 25) [HIGH confidence]
    Response fields:
      - transactions[] (array of transaction objects) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200, 401
    Business rules:
      - Only returns current_user's transactions [HIGH confidence]
      - Ordered by created_at DESC [HIGH confidence]

  GET /api/v1/transactions/:id
    Response fields:
      - transaction (object, same shape as create) [HIGH confidence]
    Status codes: 200, 404, 401
    Business rules:
      - Only returns current_user's transaction [HIGH confidence]

Source: app/controllers/api/v1/wallets_controller.rb
        app/models/wallet.rb

API Contract (inbound):
  POST /api/v1/wallets
    Request params:
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - name (string, required, max 100 chars) [HIGH confidence]
      - status (string, optional, in: active/suspended/closed) [MEDIUM confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401
    Business rules:
      - Currency unique per user [HIGH confidence]

  GET /api/v1/wallets
    Response fields:
      - wallets[] (array of wallet objects) [HIGH confidence]
    Status codes: 200, 401
    Business rules:
      - Only returns current_user's wallets [HIGH confidence]
      - Ordered by currency [HIGH confidence]

  PATCH /api/v1/wallets/:id
    Request params:
      - currency (string, optional) [HIGH confidence]
      - name (string, optional) [HIGH confidence]
      - status (string, optional) [HIGH confidence]
    Response fields:
      - wallet (object, same shape as create) [HIGH confidence]
    Status codes: 200, 404, 422, 401
    Business rules:
      - Only updates current_user's wallet [HIGH confidence]

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

Outbound API:
  PaymentGateway.charge (called for payment category transactions):
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
    - Expected: response with .success? method [MEDIUM confidence]
    - On success: transaction status → completed [HIGH confidence]
    - On failure: transaction status → failed [HIGH confidence]
    - On error: PaymentGateway::ChargeError raised [HIGH confidence]

Wallet#deposit! / Wallet#withdraw! (model methods):
    - amount (decimal, must be positive) [HIGH confidence]
    - Wallet must be active [HIGH confidence]
    - withdraw! requires sufficient balance [HIGH confidence]
============================
```

---

### Test Structure Tree

```
POST /api/v1/transactions
├── ✓ field: amount (nil → 422, negative → 422)
│   └── ✗ missing: zero, boundary max (1_000_000), over max, non-numeric
├── ✓ field: currency (nil → 422, invalid → 422)
│   └── ✗ missing: empty string, each valid value verified
├── ✓ field: wallet_id (not found → 422)
│   └── ✗ missing: another user's wallet → 422
├── ✗ field: description — NO TESTS
├── ✗ field: category — NO TESTS (4 enum values untested)
├── ✗ response body — happy path only checks status code
├── ✗ DB assertions — no change(Transaction, :count) in happy path
├── ✗ business: wallet must be active — NO TESTS
├── ✗ business: currency must match wallet — NO TESTS
└── ✗ external: PaymentGateway.charge — NO TESTS (success/failure/error)

GET /api/v1/transactions/:id
├── ✓ field: id (not found → 404)
├── ✗ response body shape — only checks status code
└── ✗ business: another user's transaction — NO TESTS

GET /api/v1/transactions (index)
├── ✗ response shape — only checks 200
├── ✗ pagination: meta.total, meta.page, meta.per_page — untested
├── ✗ pagination: page/per_page params — untested
└── ✗ ordering (created_at DESC) — untested

POST /api/v1/wallets
├── ✓ field: currency (nil → 422, invalid → 422) + happy path response verified
├── ✓ field: name (nil → 422) + happy path response verified
├── ✗ field: name — missing: too long (> 100 chars)
├── ✗ field: status — missing: enum values not tested
├── ✗ business: duplicate currency per user — NO TESTS
└── ✓ DB assertions — happy path checks count + response fields

GET /api/v1/wallets (index)
├── ✗ response shape — only checks 200
└── ✗ ordering (by currency) — untested

PATCH /api/v1/wallets/:id — NO TESTS AT ALL
├── ✗ happy path — untested
├── ✗ field: currency — untested
├── ✗ field: name — untested
├── ✗ field: status — untested
├── ✗ not found → 404 — untested
└── ✗ validation failure → 422 — untested

Wallet#deposit!
├── ✓ increases balance (+500)
├── ✓ negative amount → raises ArgumentError
├── ✓ zero amount → raises ArgumentError
├── ✓ suspended wallet → raises 'Wallet is not active'
└── ✗ closed wallet — NOT TESTED

Wallet#withdraw!
├── ✓ decreases balance (-500)
├── ✓ negative amount → raises ArgumentError
├── ✓ insufficient balance → raises
├── ✗ exact balance (boundary) — NOT TESTED
├── ✗ suspended wallet — NOT TESTED
└── ✗ closed wallet — NOT TESTED
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (req) | amount | HIGH | Yes | nil, negative | zero, max boundary, over max |
| POST /transactions (req) | currency | HIGH | Yes | nil, invalid | empty string, each valid value |
| POST /transactions (req) | wallet_id | HIGH | Yes | not found | another user's wallet |
| POST /transactions (req) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (req) | category | HIGH | No | -- | HIGH: untested (4 enum values) |
| POST /transactions (resp) | all fields | HIGH | No | -- | HIGH: no response body assertions |
| POST /transactions (DB) | all fields | HIGH | No | -- | HIGH: no DB state assertions |
| POST /transactions (biz) | wallet active | HIGH | No | -- | HIGH: untested |
| POST /transactions (biz) | currency match | HIGH | No | -- | HIGH: untested |
| POST /transactions (ext) | PaymentGateway | HIGH | No | -- | HIGH: untested |
| GET /transactions/:id (resp) | shape | HIGH | No | -- | HIGH: only status checked |
| GET /transactions/:id (biz) | ownership | HIGH | No | -- | HIGH: untested |
| GET /transactions (resp) | shape + meta | HIGH | No | -- | HIGH: untested |
| GET /transactions (biz) | pagination | HIGH | No | -- | MEDIUM: untested |
| GET /transactions (biz) | ordering | HIGH | No | -- | MEDIUM: untested |
| POST /wallets (req) | currency | HIGH | Yes | nil, invalid, happy | duplicate per user |
| POST /wallets (req) | name | HIGH | Yes | nil, happy | too long |
| POST /wallets (req) | status | MEDIUM | No | -- | MEDIUM: untested |
| GET /wallets (resp) | shape | HIGH | No | -- | MEDIUM: only status checked |
| PATCH /wallets (all) | all fields | HIGH | No | -- | HIGH: entire endpoint untested |
| Wallet#deposit! | amount | HIGH | Yes | positive, negative, zero | -- |
| Wallet#deposit! | wallet status | HIGH | Partial | suspended | closed |
| Wallet#withdraw! | amount | HIGH | Partial | negative, insufficient | zero, exact balance |
| Wallet#withdraw! | wallet status | HIGH | No | -- | HIGH: suspended/closed |

---

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint untested (happy path, not found, validation)

  Suggested test:
  ```ruby
  describe 'PATCH /api/v1/wallets/:id' do
    let(:wallet) { create(:wallet, user: user, currency: 'USD', name: 'Old Name') }
    let(:params) { { wallet: { name: new_name } } }
    let(:new_name) { 'New Name' }

    context 'with valid params' do
      it 'updates the wallet and returns 200' do
        patch "/api/v1/wallets/#{wallet.id}", params: params, headers: headers
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['wallet']['name']).to eq('New Name')
        expect(wallet.reload.name).to eq('New Name')
      end
    end

    context 'when wallet does not exist' do
      it 'returns 404' do
        patch '/api/v1/wallets/999999', params: params, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when name is too long' do
      let(:new_name) { 'a' * 101 }

      it 'returns 422' do
        patch "/api/v1/wallets/#{wallet.id}", params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` response body — happy path only checks status code, never verifies response shape

  Suggested test:
  ```ruby
  context 'with valid params' do
    it 'returns 201 with correct transaction shape' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      txn = body['transaction']
      expect(txn['amount']).to eq('100.5')
      expect(txn['currency']).to eq('USD')
      expect(txn['status']).to eq('pending')
      expect(txn['wallet_id']).to eq(wallet.id)
      expect(txn.keys).to match_array(%w[id amount currency status description category wallet_id created_at updated_at])
    end

    it 'persists correct data in DB' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.to change(Transaction, :count).by(1)

      db_txn = Transaction.last
      expect(db_txn.user_id).to eq(user.id)
      expect(db_txn.wallet_id).to eq(wallet.id)
      expect(db_txn.amount).to eq(100.50)
      expect(db_txn.currency).to eq('USD')
      expect(db_txn.status).to eq('pending')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` field `description` — no test verifies this field

  Suggested test:
  ```ruby
  context 'field: description' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, description: description } }
    end
    let(:description) { 'Valid description' }

    context 'when description is too long (> 500 chars)' do
      let(:description) { 'a' * 501 }

      it 'returns 422 and does not create a transaction' do
        expect { post '/api/v1/transactions', params: params, headers: headers }
          .not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when description is nil' do
      let(:description) { nil }

      it 'succeeds (description is optional)' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` field `category` — no test for any of the 4 enum values (transfer/payment/deposit/withdrawal)

  Suggested test:
  ```ruby
  context 'field: category' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: category } }
    end

    context 'when category is payment' do
      let(:category) { 'payment' }

      it 'creates transaction with payment category' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.category).to eq('payment')
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

    context 'when category is omitted' do
      let(:params) { { transaction: { amount: amount, currency: currency, wallet_id: wallet.id } } }

      it 'defaults to transfer' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.category).to eq('transfer')
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: wallet must be active — no test for suspended/closed wallet

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

- [ ] `POST /api/v1/transactions` business rule: currency must match wallet — no test

  Suggested test:
  ```ruby
  context 'when currency does not match wallet' do
    let(:currency) { 'EUR' } # wallet is USD

    it 'returns 422 and does not create a transaction' do
      expect { post '/api/v1/transactions', params: params, headers: headers }
        .not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to include('Currency does not match wallet')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external API: PaymentGateway.charge — no tests for success/failure/error

  Suggested test:
  ```ruby
  context 'external: PaymentGateway' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }
    end

    before do
      allow(PaymentGateway).to receive(:charge).and_return(gateway_response)
    end

    context 'when gateway succeeds' do
      let(:gateway_response) { double(success?: true) }

      it 'creates transaction with completed status' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('completed')
      end

      it 'calls gateway with correct params' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(PaymentGateway).to have_received(:charge).with(
          hash_including(amount: 100.50, currency: 'USD')
        )
      end
    end

    context 'when gateway fails' do
      let(:gateway_response) { double(success?: false) }

      it 'creates transaction with failed status' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.status).to eq('failed')
      end
    end

    context 'when gateway raises ChargeError' do
      before do
        allow(PaymentGateway).to receive(:charge)
          .and_raise(PaymentGateway::ChargeError, 'Connection refused')
      end

      it 'returns 422 with payment error' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Payment processing failed')
      end
    end
  end
  ```

- [ ] `Wallet#withdraw!` wallet status — no test for suspended/closed wallet

  Suggested test:
  ```ruby
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
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` field `amount` — missing: zero boundary, max (1_000_000), over max
- [ ] `POST /api/v1/transactions` field `currency` — missing: empty string edge case
- [ ] `POST /api/v1/transactions` field `wallet_id` — missing: another user's wallet (authorization)
- [ ] `GET /api/v1/transactions/:id` — response body shape not verified, ownership not tested
- [ ] `GET /api/v1/transactions` — response shape, pagination meta, ordering all untested
- [ ] `POST /api/v1/wallets` field `currency` — missing: duplicate per user scenario
- [ ] `POST /api/v1/wallets` field `name` — missing: too long (> 100 chars)
- [ ] `GET /api/v1/wallets` — response shape and ordering untested
- [ ] `Wallet#deposit!` — missing: closed wallet state
- [ ] `Wallet#withdraw!` — missing: exact balance boundary (withdraw entire balance)

**LOW** (rare corner cases)

- [ ] `POST /api/v1/transactions` field `amount` — non-numeric string value
- [ ] `GET /api/v1/transactions` — per_page param with invalid/extreme values
- [ ] Transaction status enum — `reversed` state never exercised in any test

---

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Status-code-only assertions | `spec/requests/api/v1/transactions_spec.rb:33` | HIGH | Assert response body fields + DB state in happy path |
| Status-code-only assertions | `spec/requests/api/v1/transactions_spec.rb:41-88` | HIGH | Error scenarios should assert no DB write + no side effects |
| Status-code-only assertions | `spec/requests/api/v1/transactions_spec.rb:100,119` | HIGH | Verify response shape on GET endpoints |
| No test foundation (missing subject) | `spec/requests/api/v1/transactions_spec.rb` | MEDIUM | Extract `subject(:run_test)` so each test overrides one field |
| Missing DB assertion in error paths | `spec/requests/api/v1/transactions_spec.rb:39-88` | MEDIUM | Add `expect { ... }.not_to change(Transaction, :count)` |
| No test for entire endpoint | `wallets_spec.rb` (PATCH missing) | HIGH | Write complete test session for PATCH |

---

### Top 5 Priority Actions

1. **Add response body + DB assertions to `POST /transactions` happy path** — the current test only checks `201`, meaning any regression in response shape or DB persistence goes undetected.
2. **Add PaymentGateway external API test session** — the payment flow (category: payment) triggers an external charge with no test coverage at all. Gateway success/failure/error paths are completely unprotected.
3. **Write full test session for `PATCH /api/v1/wallets/:id`** — entire endpoint is untested, any breakage would ship silently.
4. **Add business rule tests: wallet active + currency match** — two critical validation paths in `TransactionService` have zero coverage. A regression here means money moves to wrong wallets.
5. **Add `description` and `category` field test groups** — two permitted params with validations (max length, enum constraint) have no tests, meaning the contract for these fields is unprotected.
