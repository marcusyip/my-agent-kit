## TDD Contract Review: spec/requests/api/v1/transactions_spec.rb

**Test file:** spec/requests/api/v1/transactions_spec.rb
**Endpoints:** POST /api/v1/transactions, GET /api/v1/transactions/:id, GET /api/v1/transactions
**Source files:** app/controllers/api/v1/transactions_controller.rb, app/services/transaction_service.rb, app/models/transaction.rb, db/migrate/003_create_transactions.rb
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

### Overall Score: 3.3 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 2/10 | 20% | 0.40 |
| Test Case Quality | 3/10 | 15% | 0.45 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 1/10 | 10% | 0.10 |
| **Overall** | | | **3.35** |

### Verdict: WEAK

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb, app/services/transaction_service.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):
  POST /api/v1/transactions
    Request params:
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - wallet_id (integer, required, must exist and belong to current_user) [HIGH confidence]
      - description (string, optional, max: 500) [HIGH confidence]
      - category (string, optional, enum: transfer/payment/deposit/withdrawal, default: 'transfer') [HIGH confidence]
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
    Status codes: 201, 422

  GET /api/v1/transactions/:id
    Response fields:
      - transaction: id, amount, currency, status, description, category, wallet_id, created_at, updated_at [HIGH confidence]
    Status codes: 200, 404

  GET /api/v1/transactions (index)
    Query params:
      - start_date (string, optional, date filter) [HIGH confidence]
      - end_date (string, optional, date filter) [HIGH confidence]
      - status (string, optional, filter) [HIGH confidence]
      - page (integer, optional, pagination) [HIGH confidence]
      - per_page (integer, optional, default: 25) [HIGH confidence]
    Response fields:
      - transactions (array of transaction objects) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
      - meta.per_page (integer) [HIGH confidence]
    Status codes: 200

DB Contract:
  Transaction model:
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK to wallets) [HIGH confidence]
    - amount (decimal, precision: 20, scale: 8, NOT NULL, > 0, <= 1_000_000) [HIGH confidence]
    - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - status (string, NOT NULL, default: 'pending', enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable, max: 500) [HIGH confidence]
    - category (string, NOT NULL, default: 'transfer', enum: transfer/payment/deposit/withdrawal) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (triggered for payment category):
    Request params:
      - amount (decimal) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - user_id (integer) [HIGH confidence]
      - transaction_id (integer) [HIGH confidence]
    Expected response: { success?: boolean } [HIGH confidence]
    Error: PaymentGateway::ChargeError [HIGH confidence]
    Side effects:
      - On success: transaction status → 'completed' [HIGH confidence]
      - On failure: transaction status → 'failed' [HIGH confidence]

Business Rules (from TransactionService):
  - Wallet must be active (WalletInactiveError) [HIGH confidence]
  - Currency must match wallet currency (CurrencyMismatchError) [HIGH confidence]
  - Amount must not exceed wallet balance (InsufficientBalanceError) [HIGH confidence]
  - Balance deducted via wallet.withdraw! (except for deposits) [HIGH confidence]
  - Error response for InsufficientBalanceError leaks current balance and requested amount [HIGH confidence]
============================
```

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | amount (decimal 20,8), balance deduction via withdraw! | 5 HIGH, 2 MEDIUM |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | status (pending/completed/failed/reversed), category (transfer/payment/deposit/withdrawal) | 3 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | balance check in TransactionService, withdraw! with with_lock | 3 HIGH |
| 5 | External Payment Integrations | Extracted | PaymentGateway.charge for payment category | 3 HIGH |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | with_lock in withdraw!, but no test | 2 HIGH |
| 8 | Security & Access Control | Extracted | authenticate_user!, current_user scoping, set_wallet ownership check | 5 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/transactions
├── field: amount (request param)
│   ├── ✓ nil → 422
│   ├── ✓ negative → 422
│   ├── ✗ zero → 422 (boundary: greater_than 0)
│   ├── ✗ at max (1_000_000) → success
│   ├── ✗ over max (1_000_001) → 422
│   ├── ✗ exceeds wallet balance → 422 [FINTECH]
│   ├── ✗ exactly equals wallet balance → success, balance becomes zero [FINTECH]
│   ├── ✗ precision overflow (e.g. 0.123456789 with scale 8) [FINTECH]
│   └── ✗ non-numeric string → 422
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value verified (USD, EUR, GBP, BTC, ETH)
│   └── ✗ currency mismatch with wallet → 422 [FINTECH]
├── field: wallet_id (request param)
│   ├── ✓ not found (999999) → 422
│   ├── ✗ another user's wallet → 422 (IDOR) [FINTECH]
│   ├── ✗ suspended wallet → 422 [FINTECH]
│   └── ✗ closed wallet → 422 [FINTECH]
├── field: description (request param) — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length (500) → success
│   ├── ✗ over max length (501) → 422
│   └── ✗ empty string
├── field: category (request param) — NO TESTS
│   ├── ✗ each valid value (transfer, payment, deposit, withdrawal)
│   ├── ✗ invalid value → 422
│   ├── ✗ nil → defaults to 'transfer'
│   └── ✗ 'payment' triggers PaymentGateway.charge
├── response body — NO ASSERTIONS
│   ├── ✗ happy path should assert all 9 response fields
│   │   (id, amount, currency, status, description, category, wallet_id, created_at, updated_at)
│   └── ✗ error response should not leak balance (InsufficientBalanceError details leak balance)
├── DB assertions — NO ASSERTIONS
│   ├── ✗ happy path should assert Transaction created with correct values
│   ├── ✗ happy path should assert wallet balance deducted
│   └── ✗ error paths should assert no Transaction created
├── auth: authentication required — NO TESTS
│   └── ✗ unauthenticated request → 401
├── business: wallet must be active [FINTECH]
│   ├── ✗ suspended wallet → 422
│   └── ✗ closed wallet → 422
├── business: currency must match wallet [FINTECH]
│   └── ✗ mismatch → 422
├── business: balance check [FINTECH]
│   ├── ✗ amount > balance → 422
│   └── ✗ amount == balance → success, balance becomes zero
├── state machine: transaction status [FINTECH]
│   ├── ✗ created with status 'pending'
│   ├── ✗ payment success → 'completed'
│   ├── ✗ payment failure → 'failed'
│   └── ✗ 'reversed' transition (not tested)
├── external: PaymentGateway.charge (for payment category) — NO TESTS [FINTECH]
│   ├── ✗ success → transaction status 'completed'
│   ├── ✗ failure → transaction status 'failed'
│   ├── ✗ ChargeError → 422
│   └── ✗ timeout/unavailable
└── concurrency [FINTECH]
    ├── ✗ two concurrent debits exceeding balance → only one succeeds
    └── ✗ double-submit same transaction → only one created

GET /api/v1/transactions/:id
├── field: id (path param)
│   ├── ✓ valid id → 200
│   ├── ✓ not found → 404
│   └── ✗ another user's transaction → 404 (IDOR) [FINTECH]
├── response body
│   ├── ✓ returns 200
│   └── ✗ does not verify any response fields
├── auth: authentication required — NO TESTS
│   └── ✗ unauthenticated request → 401

GET /api/v1/transactions (index)
├── response body
│   ├── ✓ returns 200
│   ├── ✗ does not verify transactions array shape
│   ├── ✗ does not verify meta pagination fields (total, page, per_page)
│   └── ✗ does not verify ordering (created_at desc)
├── field: start_date (query param) — NO TESTS
│   ├── ✗ valid date filters results
│   ├── ✗ invalid date format → 422 or ignored?
│   └── ✗ future date → empty results
├── field: end_date (query param) — NO TESTS
│   ├── ✗ valid date filters results
│   └── ✗ end_date before start_date → empty results
├── field: status (query param) — NO TESTS
│   ├── ✗ valid status filters correctly
│   └── ✗ invalid status → all results or 422?
├── field: page (query param) — NO TESTS
│   ├── ✗ page=1 → first page
│   ├── ✗ page=0 → rejected or default?
│   ├── ✗ page=-1 → rejected
│   ├── ✗ page beyond last → empty results
│   └── ✗ default page when omitted
├── field: per_page (query param) — NO TESTS
│   ├── ✗ custom per_page respected
│   ├── ✗ default (25) when omitted
│   ├── ✗ very large per_page → capped?
│   └── ✗ per_page=0 → rejected or default?
├── auth: authentication required — NO TESTS
│   └── ✗ unauthenticated request → 401
└── security: data isolation — NO TESTS
    └── ✗ only returns current_user's transactions
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /transactions (request) | amount | HIGH | Yes | nil, negative | missing: zero, max, over max, exceeds balance, equals balance, precision overflow |
| POST /transactions (request) | currency | HIGH | Yes | nil, invalid | missing: empty string, each valid value, mismatch with wallet |
| POST /transactions (request) | wallet_id | HIGH | Yes | not found | missing: another user's wallet (IDOR), suspended, closed |
| POST /transactions (request) | description | HIGH | No | -- | HIGH: untested |
| POST /transactions (request) | category | HIGH | No | -- | HIGH: untested (4 enum values, default behavior, payment gateway trigger) |
| POST /transactions (response) | id | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | amount | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | currency | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | status | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | description | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | category | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | wallet_id | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | created_at | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (response) | updated_at | HIGH | No | -- | HIGH: not asserted |
| POST /transactions (DB) | Transaction record | HIGH | No | -- | HIGH: no DB assertions in happy path |
| POST /transactions (DB) | wallet.balance after deduction | HIGH | No | -- | HIGH: balance change not asserted |
| Transaction (DB) | status enum | HIGH | No | -- | HIGH: 4 values (pending/completed/failed/reversed) untested through API |
| Transaction (DB) | category enum | HIGH | No | -- | HIGH: 4 values (transfer/payment/deposit/withdrawal) untested through API |
| GET /transactions/:id (response) | all fields | HIGH | No | -- | HIGH: response fields not asserted |
| GET /transactions/:id (path) | id (IDOR) | HIGH | No | -- | HIGH: no IDOR test |
| GET /transactions (response) | transactions array | HIGH | No | -- | HIGH: response shape not verified |
| GET /transactions (response) | meta.total | HIGH | No | -- | HIGH: pagination meta not verified |
| GET /transactions (response) | meta.page | HIGH | No | -- | HIGH: pagination meta not verified |
| GET /transactions (response) | meta.per_page | HIGH | No | -- | HIGH: pagination meta not verified |
| GET /transactions (query) | start_date | HIGH | No | -- | HIGH: untested filter |
| GET /transactions (query) | end_date | HIGH | No | -- | HIGH: untested filter |
| GET /transactions (query) | status | HIGH | No | -- | HIGH: untested filter |
| GET /transactions (query) | page | HIGH | No | -- | HIGH: untested pagination |
| GET /transactions (query) | per_page | HIGH | No | -- | HIGH: untested pagination |
| PaymentGateway.charge (outbound) | amount | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | currency | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | success response | HIGH | No | -- | HIGH: untested |
| PaymentGateway.charge (outbound) | failure/error | HIGH | No | -- | HIGH: untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `POST /api/v1/transactions` -- happy path only checks status code (201), does not assert any of the 9 response body fields or DB state. transactions_spec.rb:36-39

  Suggested test:
  ```ruby
  context 'with valid params' do
    it 'returns 201 with complete transaction response' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      txn = body['transaction']
      expect(txn['amount']).to eq('100.5')
      expect(txn['currency']).to eq('USD')
      expect(txn['status']).to eq('pending')
      expect(txn['category']).to eq('transfer')
      expect(txn['wallet_id']).to eq(wallet.id)
      expect(txn).to have_key('id')
      expect(txn).to have_key('description')
      expect(txn).to have_key('created_at')
      expect(txn).to have_key('updated_at')
    end

    it 'creates a Transaction with correct DB values and deducts balance' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.to change(Transaction, :count).by(1)

      db_txn = Transaction.last
      expect(db_txn.user_id).to eq(user.id)
      expect(db_txn.wallet_id).to eq(wallet.id)
      expect(db_txn.amount).to eq(BigDecimal('100.50'))
      expect(db_txn.currency).to eq('USD')
      expect(db_txn.status).to eq('pending')

      expect(wallet.reload.balance).to eq(wallet_initial_balance - BigDecimal('100.50'))
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `description` -- no test verifies this field. 500-char max, optional, nullable.

  Suggested test:
  ```ruby
  context 'when description is nil' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, description: nil } }
    end

    it 'succeeds (description is optional)' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
    end
  end

  context 'when description exceeds 500 characters' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, description: 'x' * 501 } }
    end

    it 'returns 422' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` request field `category` -- no test verifies this field. 4 enum values (transfer/payment/deposit/withdrawal), default 'transfer', payment triggers PaymentGateway.charge.

  Suggested test:
  ```ruby
  context 'when category is payment' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }
    end

    before do
      allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
    end

    it 'creates transaction and calls PaymentGateway.charge' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(PaymentGateway).to have_received(:charge).with(
        amount: BigDecimal('100.50'),
        currency: 'USD',
        user_id: user.id,
        transaction_id: Transaction.last.id
      )
      expect(Transaction.last.status).to eq('completed')
    end
  end

  context 'when category is invalid' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'invalid' } }
    end

    it 'returns 422' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'when category is nil (defaults to transfer)' do
    it 'creates transaction with category transfer' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(Transaction.last.category).to eq('transfer')
    end
  end
  ```

- [ ] `POST /api/v1/transactions` -- wallet belonging to another user (IDOR). Controller uses `current_user.wallets.find_by` which returns nil, but no test verifies this path. [FINTECH]

  Suggested test:
  ```ruby
  context 'when wallet belongs to another user' do
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

- [ ] `POST /api/v1/transactions` -- suspended/closed wallet. TransactionService validates `wallet.active?` but no test covers this through the API. [FINTECH]

  Suggested test:
  ```ruby
  context 'when wallet is suspended' do
    before { wallet.update!(status: 'suspended') }

    it 'returns 422' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'when wallet is closed' do
    before { wallet.update!(status: 'closed') }

    it 'returns 422' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` -- currency mismatch with wallet. TransactionService validates but no test covers this through the API. [FINTECH]

  Suggested test:
  ```ruby
  context 'when currency does not match wallet' do
    let(:currency) { 'EUR' }

    it 'returns 422 and does not create a transaction' do
      expect {
        post '/api/v1/transactions', params: params, headers: headers
      }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` -- amount exceeds wallet balance. TransactionService validates `wallet.balance >= amount` but no test covers this through the API. [FINTECH]

  Suggested test:
  ```ruby
  context 'when amount exceeds wallet balance' do
    let(:amount) { (wallet.balance + 1).to_s }

    it 'returns 422 and does not deduct balance' do
      original_balance = wallet.balance
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(wallet.reload.balance).to eq(original_balance)
    end
  end

  context 'when amount exactly equals wallet balance' do
    let(:amount) { wallet.balance.to_s }

    it 'succeeds and balance becomes zero' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(response).to have_http_status(:created)
      expect(wallet.reload.balance).to eq(0)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` -- PaymentGateway.charge scenarios. No test covers the external API call path (success, failure, ChargeError). [FINTECH]

  Suggested test:
  ```ruby
  context 'when PaymentGateway.charge succeeds (payment category)' do
    let(:params) do
      { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }
    end

    before do
      allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
    end

    it 'sets transaction status to completed' do
      post '/api/v1/transactions', params: params, headers: headers
      expect(Transaction.last.status).to eq('completed')
    end
  end

  context 'when PaymentGateway.charge fails' do
    before do
      allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
    end

    it 'sets transaction status to failed' do
      post '/api/v1/transactions', params: { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }, headers: headers
      expect(Transaction.last.status).to eq('failed')
    end
  end

  context 'when PaymentGateway.charge raises ChargeError' do
    before do
      allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError, 'Gateway timeout')
    end

    it 'returns 422' do
      post '/api/v1/transactions', params: { transaction: { amount: amount, currency: currency, wallet_id: wallet.id, category: 'payment' } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/transactions` -- no test for unauthenticated request (missing auth → 401). [FINTECH]

- [ ] `GET /api/v1/transactions/:id` -- no IDOR test. Another user's transaction should return 404. [FINTECH]

  Suggested test:
  ```ruby
  context 'when transaction belongs to another user' do
    let(:other_user) { create(:user) }
    let(:other_wallet) { create(:wallet, user: other_user) }
    let(:other_txn) { create(:transaction, user: other_user, wallet: other_wallet) }

    it 'returns 404' do
      get "/api/v1/transactions/#{other_txn.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
  ```

- [ ] `GET /api/v1/transactions` -- response shape, pagination meta, and data isolation not tested.

- [ ] `GET /api/v1/transactions` -- date filters (start_date, end_date), status filter, pagination params (page, per_page) all untested.

- [ ] `POST /api/v1/transactions` -- error response for InsufficientBalanceError leaks wallet balance: `"Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"` (transaction_service.rb:34-35). No test verifies error response body content. [FINTECH]

- [ ] `POST /api/v1/transactions` -- no idempotency key. Duplicate POST requests can create duplicate financial transactions. [FINTECH]

- [ ] `POST /api/v1/transactions` -- no concurrency protection test. Two concurrent requests that both pass balance check individually but together exceed balance could cause overdraw. The code uses `with_lock` in `withdraw!` but no test verifies the lock prevents concurrent corruption. [FINTECH]

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/transactions` request field `amount` -- missing zero, max boundary (1_000_000), over max, non-numeric string scenarios
- [ ] `POST /api/v1/transactions` request field `currency` -- missing empty string scenario, each valid value not verified individually
- [ ] `GET /api/v1/transactions/:id` -- response body fields not asserted (only checks status 200)
- [ ] `GET /api/v1/transactions` -- ordering (created_at desc) not verified
- [ ] `POST /api/v1/transactions` -- amount precision: test with amounts exceeding schema scale (8 decimal places) [FINTECH]
- [ ] No rate limiting on financial mutation endpoint POST /api/v1/transactions [FINTECH]
- [ ] No audit trail for transaction mutations [FINTECH]
- [ ] No explicit state machine or transition guards for Transaction status -- invalid transitions (e.g. completed → pending) could corrupt financial data [FINTECH]

**LOW** (rare corner cases)

- [ ] `GET /api/v1/transactions` -- per_page=0, page=-1, very large per_page edge cases
- [ ] `GET /api/v1/transactions` -- invalid date format in start_date/end_date

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | transactions_spec.rb (POST + GET/:id + GET index) | HIGH | Split into post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb |
| Status-only assertions in happy path | transactions_spec.rb:37-39 | CRITICAL | Assert all 9 response fields + DB state + wallet balance deduction |
| Status-only assertions in error tests | transactions_spec.rb:45, 52, 63, 72, 90 | HIGH | Assert no DB changes, assert error body content |
| No test foundation (no subject/run_test, no DEFAULT constants) | transactions_spec.rb | MEDIUM | Add subject(:run_test), DEFAULT_AMOUNT, DEFAULT_CURRENCY constants |
| Service spec tests implementation details | spec/services/transaction_service_spec.rb:12-25 | HIGH | Delete -- tests `receive(:build_transaction)`, `receive(:validate_wallet_active!)` which verify internal method calls, not contract behavior |
| Error response leaks financial data | transaction_service.rb:34-35 (InsufficientBalanceError) | CRITICAL | Remove balance details from error response |
| Model spec for internal model | spec/models/wallet_spec.rb | MEDIUM | Delete -- test deposit!/withdraw! behavior through POST /api/v1/transactions instead |

### Missing Infrastructure [FINTECH]

- No idempotency key on POST /api/v1/transactions -- duplicate requests can create duplicate financial transactions
- No concurrency protection test -- `with_lock` exists in `withdraw!` but no test verifies it prevents double-debit
- No explicit state machine or transition guards for Transaction status field -- invalid state transitions can corrupt financial data
- No rate limiting detected on POST /api/v1/transactions
- No audit trail detected -- financial transactions should be auditable
- No KYC/AML fields, transaction limits, or compliance validations detected
- No webhook signature verification or payment gateway error handling beyond ChargeError

### Top 5 Priority Actions

1. **Add response body and DB assertions to POST happy path** -- currently only checks status 201, meaning any of the 9 response fields or the DB record could be completely wrong without a test catching it (transactions_spec.rb:36-39)
2. **Add balance validation tests (amount > balance, amount == balance)** -- the code validates balance in TransactionService but no test covers this through the API. Financial transactions without balance protection tests are critical [FINTECH]
3. **Add PaymentGateway.charge scenarios** -- payment category triggers an external API call that transitions transaction status to completed/failed, but no test covers success, failure, or error paths [FINTECH]
4. **Add IDOR tests for wallet_id (POST) and transaction id (GET/:id)** -- no test verifies that users cannot access other users' wallets or transactions [FINTECH]
5. **Split transactions_spec.rb into one file per endpoint** and add test foundation (subject, DEFAULT constants) -- current structure obscures that GET index has zero meaningful coverage and all filter/pagination params are untested
