## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/models/transaction.rb, app/services/transaction_service.rb, db/migrate/003_create_transactions.rb
**Framework:** Rails 7.1 / RSpec (request spec)
**Mode:** Fintech mode enabled (money/amount/balance fields, payment gateway, decimal types)

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

### Overall Score: 3.4 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 2/10 | 20% | 0.40 |
| Test Case Quality | 2/10 | 15% | 0.30 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.40** |

### Verdict: WEAK

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
    - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - wallet_id (integer, required, must belong to current_user) [HIGH confidence]
    - description (string, optional, max length 500) [HIGH confidence]
    - category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]
  Response fields:
    - id (integer) [HIGH confidence]
    - amount (string) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - description (string) [HIGH confidence]
    - category (string) [HIGH confidence]
    - wallet_id (integer) [HIGH confidence]
    - created_at (string/iso8601) [HIGH confidence]
    - updated_at (string/iso8601) [HIGH confidence]
  Status codes: 201, 422, 401
  Business rules:
    - Wallet must be active (WalletInactiveError → 422) [HIGH confidence]
    - Currency must match wallet currency (CurrencyMismatchError → 422) [HIGH confidence]
    - If category=payment, charges PaymentGateway [HIGH confidence]

API Contract — GET /api/v1/transactions/:id (inbound):
  Request params:
    - id (integer, required, must belong to current_user) [HIGH confidence]
  Response fields: same 9 fields as POST response [HIGH confidence]
  Status codes: 200, 404, 401

API Contract — GET /api/v1/transactions (inbound):
  Request params:
    - page (integer, optional) [MEDIUM confidence]
    - per_page (integer, optional, default 25) [MEDIUM confidence]
  Response fields:
    - transactions (array of serialized transactions) [HIGH confidence]
    - meta.total (integer) [HIGH confidence]
    - meta.page (integer) [HIGH confidence]
    - meta.per_page (integer) [HIGH confidence]
  Status codes: 200, 401

DB Data Contract — Transaction model:
  Fields:
    - user_id (integer, NOT NULL, FK → users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK → wallets) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - status (string, NOT NULL, default 'pending') [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, NOT NULL, default 'transfer') [HIGH confidence]
  Data states:
    - status enum: pending, completed, failed, reversed [HIGH confidence]
    - category enum: transfer, payment, deposit, withdrawal [HIGH confidence]

Outbound API — PaymentGateway.charge:
  Request params:
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - transaction_id (integer) [HIGH confidence]
  Expected response: object with success? method [HIGH confidence]
  On success: transaction.status → completed [HIGH confidence]
  On failure: transaction.status → failed [HIGH confidence]
  On ChargeError: returns 422 with error message [HIGH confidence]

[FINTECH] Money & Precision:
  - amount field: decimal(20,8) — exact type, good [HIGH confidence]
  - No idempotency key on POST endpoint [HIGH confidence — gap]
  - State machine: pending → completed, pending → failed (via gateway) [HIGH confidence]
  - No explicit handling of reversed state transitions in service [MEDIUM confidence]

Total contract fields extracted: 45+
============================
```

### Test Structure Tree

```
POST /api/v1/transactions (spec/requests/api/v1/transactions_spec.rb:17)
├── happy path
│   ├── ✓ returns 201 status
│   ├── ✗ response body: id field
│   ├── ✗ response body: amount field
│   ├── ✗ response body: currency field
│   ├── ✗ response body: status field (should be 'pending' or 'completed')
│   ├── ✗ response body: description field
│   ├── ✗ response body: category field
│   ├── ✗ response body: wallet_id field
│   ├── ✗ response body: created_at field
│   ├── ✗ response body: updated_at field
│   ├── ✗ DB: Transaction record created with correct user_id
│   ├── ✗ DB: Transaction record created with correct wallet_id
│   ├── ✗ DB: Transaction record created with correct amount
│   ├── ✗ DB: Transaction record created with correct currency
│   ├── ✗ DB: Transaction record created with correct status
│   └── ✗ DB: Transaction record created with correct category (defaults to transfer)
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero (boundary) → 422 (validates > 0)
│   ├── ✗ at max (1_000_000) → 201
│   ├── ✗ over max (1_000_001) → 422
│   ├── ✗ non-numeric string → 422
│   ├── ✗ [FINTECH] precision overflow (e.g. 0.000000001 beyond scale 8)
│   └── ✗ [FINTECH] very small amount (0.00000001) → succeeds
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → 201
│   └── ✗ [FINTECH] currency mismatch with wallet → 422
├── field: wallet_id (request param)
│   ├── ✓ not found → 422
│   ├── ✗ another user's wallet → 422 (IDOR) [FINTECH]
│   ├── ✗ nil → 422
│   └── ✗ non-integer → 422
├── field: description — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ present → stored correctly
│   ├── ✗ at max length (500) → succeeds
│   └── ✗ over max length (501) → 422
├── field: category — NO TESTS
│   ├── ✗ nil (defaults to 'transfer') → 201
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal) → 201
│   ├── ✗ invalid value → 422
│   └── ✗ payment triggers PaymentGateway.charge
├── business: wallet must be active — NO TESTS
│   ├── ✗ suspended wallet → 422, no DB write
│   └── ✗ closed wallet → 422, no DB write
├── business: currency must match wallet — NO TESTS
│   └── ✗ mismatch → 422, no DB write
├── external: PaymentGateway.charge — NO TESTS [FINTECH]
│   ├── ✗ gateway success → transaction status = completed
│   ├── ✗ gateway failure → transaction status = failed
│   ├── ✗ gateway ChargeError → 422
│   └── ✗ gateway timeout → appropriate error
├── [FINTECH] idempotency — NO TESTS
│   └── ✗ no idempotency key on mutating endpoint (design gap)
├── [FINTECH] state machine — NO TESTS
│   ├── ✗ pending → completed (via gateway success)
│   ├── ✗ pending → failed (via gateway failure)
│   ├── ✗ invalid transition: completed → pending
│   └── ✗ terminal state: reversed cannot transition
├── [FINTECH] security / access control
│   ├── ✗ unauthenticated request → 401
│   ├── ✗ another user's wallet → 403/422 (IDOR)
│   └── ✗ sensitive data not leaked in error responses
└── error path side effects — NOT ASSERTED
    ├── ✗ on 422: no Transaction record created
    ├── ✗ on 422: no PaymentGateway.charge called
    └── ✗ on 422: no side effects triggered

GET /api/v1/transactions/:id (spec/requests/api/v1/transactions_spec.rb:96)
├── happy path
│   ├── ✓ returns 200 status
│   ├── ✗ response body: id field
│   ├── ✗ response body: amount field
│   ├── ✗ response body: currency field
│   ├── ✗ response body: status field
│   ├── ✗ response body: description field
│   ├── ✗ response body: category field
│   ├── ✗ response body: wallet_id field
│   ├── ✗ response body: created_at field
│   └── ✗ response body: updated_at field
├── field: id (request param)
│   ├── ✓ not found → 404
│   ├── ✗ another user's transaction → 404 (IDOR) [FINTECH]
│   └── ✗ non-integer → error
├── [FINTECH] security / access control
│   ├── ✗ unauthenticated request → 401
│   └── ✗ another user's transaction → 404 (IDOR)
└── response body — NO ASSERTIONS
    └── ✗ happy path should assert all 9 response fields

GET /api/v1/transactions (spec/requests/api/v1/transactions_spec.rb:115)
├── happy path
│   ├── ✓ returns 200 status
│   ├── ✗ response body: transactions array shape
│   ├── ✗ response body: meta.total
│   ├── ✗ response body: meta.page
│   └── ✗ response body: meta.per_page
├── field: page (request param) — NO TESTS
│   ├── ✗ page 1 → returns first page
│   ├── ✗ page 2 → returns second page
│   └── ✗ page beyond range → empty array
├── field: per_page (request param) — NO TESTS
│   ├── ✗ custom per_page → respects limit
│   └── ✗ default → 25
├── ordering — NO TESTS
│   └── ✗ ordered by created_at desc
├── [FINTECH] security / access control
│   ├── ✗ unauthenticated request → 401
│   └── ✗ only returns current user's transactions
└── scoping — NO TESTS
    └── ✗ does not return other users' transactions
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | zero, max, over max, non-numeric, [FINTECH] precision |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid value, [FINTECH] wallet mismatch |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | another user's (IDOR), nil |
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
| POST /transactions (DB) | all fields | HIGH | No | -- | HIGH: no DB assertions |
| POST /transactions (business) | wallet active | HIGH | No | -- | HIGH: untested |
| POST /transactions (business) | currency match | HIGH | No | -- | HIGH: untested |
| POST /transactions (external) | PaymentGateway | HIGH | No | -- | HIGH: untested [FINTECH] |
| GET /transactions/:id (request) | id | HIGH | Yes | not found | another user's (IDOR) |
| GET /transactions/:id (response) | all 9 fields | HIGH | No | -- | HIGH: no response assertions |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: shape untested |
| GET /transactions (response) | meta pagination | HIGH | No | -- | HIGH: untested |
| GET /transactions (request) | page | MEDIUM | No | -- | MEDIUM: untested |
| GET /transactions (request) | per_page | MEDIUM | No | -- | MEDIUM: untested |
| [FINTECH] Transaction status | state machine | HIGH | No | -- | HIGH: no transition tests |
| [FINTECH] POST /transactions | idempotency | HIGH | No | -- | HIGH: no idempotency key |
| [FINTECH] all endpoints | auth/IDOR | HIGH | No | -- | HIGH: no auth/IDOR tests |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 18 gaps)

- [ ] `POST /api/v1/transactions` happy path response body — no test verifies any of the 9 response fields

  Suggested test:
  ```ruby
  context 'happy path' do
    it 'returns 201 with correct response body' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)['transaction']
      expect(body['amount']).to eq('100.5')
      expect(body['currency']).to eq('USD')
      expect(body['status']).to eq('pending')
      expect(body['category']).to eq('transfer')
      expect(body['wallet_id']).to eq(wallet.id)
      expect(body).to have_key('id')
      expect(body).to have_key('description')
      expect(body).to have_key('created_at')
      expect(body).to have_key('updated_at')
    end

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
  context 'field: description' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, description: description } }
    end
    let(:description) { 'Test payment' }

    context 'when nil' do
      let(:description) { nil }

      it 'succeeds (optional field)' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when at max length (500)' do
      let(:description) { 'a' * 500 }

      it 'succeeds' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when over max length (501)' do
      let(:description) { 'a' * 501 }

      it 'returns 422 and does not create a transaction' do
        expect {
          post '/api/v1/transactions', params: params, headers: headers
        }.not_to change(Transaction, :count)
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
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: category } }
    end

    context 'when nil (defaults to transfer)' do
      let(:category) { nil }

      it 'creates transaction with default category' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(Transaction.last.category).to eq('transfer')
      end
    end

    context 'when payment' do
      let(:category) { 'payment' }

      it 'charges payment gateway' do
        allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
        expect(PaymentGateway).to have_received(:charge)
      end
    end

    context 'when invalid' do
      let(:category) { 'invalid_category' }

      it 'returns 422 and does not create a transaction' do
        expect {
          post '/api/v1/transactions', params: params, headers: headers
        }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: wallet must be active — no test

  Suggested test:
  ```ruby
  context 'field: wallet status (DB state)' do
    context 'when wallet is suspended' do
      before { wallet.update!(status: 'suspended') }

      it 'returns 422 and does not create a transaction' do
        expect {
          post '/api/v1/transactions', params: params, headers: headers
        }.not_to change(Transaction, :count)
        expect(response).to have_http_status(:unprocessable_entity)
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
  end
  ```

- [ ] `POST /api/v1/transactions` business rule: currency must match wallet — no test

  Suggested test:
  ```ruby
  context 'field: currency mismatch with wallet [FINTECH]' do
    let(:currency) { 'EUR' } # wallet is USD

    it 'returns 422 and does not create a transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to include('Currency')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` external API: PaymentGateway — no test [FINTECH]

  Suggested test:
  ```ruby
  context 'external: PaymentGateway.charge (category=payment) [FINTECH]' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }
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
        allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError, 'Declined')
      end

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Payment processing failed')
      end
    end
  end
  ```

- [ ] `POST /api/v1/transactions` field `wallet_id`: another user's wallet — IDOR [FINTECH]

  Suggested test:
  ```ruby
  context 'when wallet belongs to another user [FINTECH IDOR]' do
    let(:other_user) { create(:user) }
    let(:other_wallet) { create(:wallet, user: other_user, currency: 'USD') }
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: other_wallet.id } }
    end

    it 'returns 422 and does not create a transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `GET /api/v1/transactions/:id` field `id`: another user's transaction — IDOR [FINTECH]

  Suggested test:
  ```ruby
  context 'when transaction belongs to another user [FINTECH IDOR]' do
    let(:other_user) { create(:user) }
    let(:other_wallet) { create(:wallet, user: other_user) }
    let(:other_transaction) { create(:transaction, user: other_user, wallet: other_wallet) }

    it 'returns 404' do
      get "/api/v1/transactions/#{other_transaction.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
  ```

- [ ] `GET /api/v1/transactions/:id` response body — no assertions on any field
- [ ] `GET /api/v1/transactions` response shape — transactions array and meta pagination untested
- [ ] [FINTECH] No idempotency key on POST /api/v1/transactions — mutating financial endpoint without duplicate protection
- [ ] [FINTECH] Transaction state machine — no tests for valid/invalid transitions or terminal states
- [ ] [FINTECH] Authentication — no test for unauthenticated requests on any endpoint
- [ ] [FINTECH] Error paths don't assert absence of side effects (no DB write, no gateway call)

**MEDIUM** (tested but missing scenarios — 6 gaps)

- [ ] `POST /api/v1/transactions` field `amount`: missing zero boundary, max boundary (1_000_000), over max (1_000_001)
- [ ] `POST /api/v1/transactions` field `currency`: missing empty string edge case
- [ ] `POST /api/v1/transactions` field `currency`: no test verifies each valid value produces correct behavior
- [ ] `GET /api/v1/transactions` field `page` and `per_page`: pagination not tested
- [ ] `GET /api/v1/transactions`: ordering by created_at desc not tested
- [ ] All error path tests only assert status code — missing: no DB record created, no external API called

**LOW** (rare corner cases — 3 gaps)

- [ ] `POST /api/v1/transactions` field `amount`: non-numeric string input
- [ ] `POST /api/v1/transactions` field `wallet_id`: nil value
- [ ] [FINTECH] Amount precision overflow beyond decimal(20,8)

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | transactions_spec.rb (3 endpoints) | HIGH | Split into post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb |
| Status-only assertions | transactions_spec.rb:33, :43, :52, :61, :69, :86, :101, :108, :119 | HIGH | Assert response body, DB state, and side effects |
| No test foundation | transactions_spec.rb:17 | MEDIUM | Add DEFAULT constants, subject(:run_test), single post call |
| No DB assertions in happy path | transactions_spec.rb:31-35 | HIGH | Assert Transaction created with correct field values |
| No response body assertions | transactions_spec.rb:31-35, :99-103, :117-121 | HIGH | Parse and verify all response fields |
| Error paths don't assert no side effects | transactions_spec.rb:38-88 | MEDIUM | Assert no DB records created, no external calls |

### Top 5 Priority Actions

1. **Add response body + DB assertions to POST happy path** — protects 18 response/DB fields from silent breakage. Currently the happy path only checks status code 201, so any field could be removed or corrupted without detection
2. **Add PaymentGateway external API test group** [FINTECH] — the payment gateway integration is completely untested. Gateway success, failure, and error scenarios could all break silently
3. **Add wallet status and currency mismatch tests** [FINTECH] — business rules that prevent transactions on inactive wallets and mismatched currencies have zero coverage
4. **Add description and category field test groups** — two request params with validation rules (max length, enum) are entirely untested
5. **Split into one-endpoint-per-file** — 3 endpoints in one file makes it harder to see which endpoints have gaps. Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, `get_transactions_spec.rb`
