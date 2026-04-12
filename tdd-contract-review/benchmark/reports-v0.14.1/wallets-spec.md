## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets, PATCH /api/v1/wallets/:id (UNTESTED)
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb, db/migrate/002_create_wallets.rb
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

### Overall Score: 3.9 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 4/10 | 15% | 0.60 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 2/10 | 10% | 0.20 |
| **Overall** | | | **3.95** |

### Verdict: WEAK

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/wallets_controller.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):
  POST /api/v1/wallets
    Request params:
      - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - name (string, required, max: 100) [HIGH confidence]
      - status (string, optional, enum: active/suspended/closed) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string, decimal as string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422

  GET /api/v1/wallets
    Response fields:
      - wallets (array of wallet objects) [HIGH confidence]
      - Each wallet: id, currency, name, balance, status, created_at [HIGH confidence]
    Status codes: 200

  PATCH /api/v1/wallets/:id
    Request params:
      - currency (string, optional) [HIGH confidence]
      - name (string, optional) [HIGH confidence]
      - status (string, optional) [HIGH confidence]
    Response fields:
      - wallet: id, currency, name, balance, status, created_at [HIGH confidence]
    Error response (RecordInvalid -- BUG):
      - error (string) [HIGH confidence]
      - wallet_id (integer -- data leak) [HIGH confidence]
      - balance (string -- data leak) [HIGH confidence]
      - user_id (integer -- data leak) [HIGH confidence]
    Status codes: 200, 404, 422

DB Contract:
  Wallet model:
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, NOT NULL, max: 100) [HIGH confidence]
    - balance (decimal, precision: 20, scale: 8, NOT NULL, default: 0, >= 0) [HIGH confidence]
    - status (string, NOT NULL, default: 'active', enum: active/suspended/closed) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]
  Unique constraint: [user_id, currency] [HIGH confidence]

Outbound API:
  (none for wallet endpoints)
============================
```

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | balance (decimal 20,8) | 2 HIGH |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | status (active/suspended/closed) | 2 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | balance field, with_lock in deposit!/withdraw! | 2 HIGH, 1 MEDIUM |
| 5 | External Payment Integrations | Not applicable | -- | -- |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | with_lock in deposit!/withdraw! | 1 HIGH |
| 8 | Security & Access Control | Extracted | before_action :authenticate_user!, current_user scoping | 4 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/wallets
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid ('XYZ') → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ duplicate currency per user → 422 (unique constraint)
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100 chars) → success
│   └── ✗ over max length (101 chars) → 422
├── field: status (request param)
│   ├── ✗ explicitly setting status on create
│   ├── ✗ invalid status value → 422
│   └── ✗ defaults to 'active' when omitted
├── response body
│   ├── ✓ happy path asserts currency, name, balance, status
│   ├── ✗ happy path missing: id field assertion
│   └── ✗ happy path missing: created_at field assertion
├── DB assertions
│   └── ✓ happy path asserts Wallet count changed by 1
├── auth: authentication required
│   └── ✗ unauthenticated request → 401
└── security: IDOR
    └── ✗ (not applicable for create -- wallet scoped to current_user)

GET /api/v1/wallets
├── response body
│   ├── ✓ returns 200
│   ├── ✗ does not verify response shape (wallets array)
│   ├── ✗ does not verify wallet fields in response
│   └── ✗ does not verify ordering (by currency)
├── auth: authentication required
│   └── ✗ unauthenticated request → 401
├── security: data isolation
│   └── ✗ only returns current_user's wallets (not other users')
└── edge: empty state
    └── ✗ user with no wallets → empty array

PATCH /api/v1/wallets/:id — NO TESTS (entire endpoint untested)
├── field: name (request param) — NO TESTS
│   ├── ✗ valid name → 200
│   ├── ✗ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100) → success
│   └── ✗ over max length → 422
├── field: currency (request param) — NO TESTS
│   ├── ✗ valid change → 200
│   ├── ✗ invalid currency → 422
│   └── ✗ duplicate currency for user → 422
├── field: status (request param) — NO TESTS
│   ├── ✗ active → suspended → 200
│   ├── ✗ suspended → active → 200
│   ├── ✗ active → closed → 200
│   ├── ✗ invalid status → 422
│   └── ✗ closed → active (should this be allowed?)
├── response body — NO TESTS
│   └── ✗ returns wallet with all fields
├── error: not found — NO TESTS
│   └── ✗ wallet_id not found → 404
├── error: another user's wallet — NO TESTS
│   └── ✗ IDOR: access other user's wallet → 404
├── auth: authentication required — NO TESTS
│   └── ✗ unauthenticated request → 401
└── security: error response data leak (BUG) — NO TESTS
    └── ✗ 422 response leaks wallet_id, balance, user_id (wallets_controller.rb:39-44)
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /api/v1/wallets (request) | currency | HIGH | Yes | nil, invalid | missing: empty string, duplicate per user, each valid value |
| POST /api/v1/wallets (request) | name | HIGH | Yes | nil | missing: empty string, max length, over max length |
| POST /api/v1/wallets (request) | status | HIGH | No | -- | HIGH: no test for status param on create |
| POST /api/v1/wallets (response) | id | HIGH | No | -- | HIGH: not asserted in happy path |
| POST /api/v1/wallets (response) | currency | HIGH | Yes | happy path | -- |
| POST /api/v1/wallets (response) | name | HIGH | Yes | happy path | -- |
| POST /api/v1/wallets (response) | balance | HIGH | Yes | happy path (eq '0.0') | -- |
| POST /api/v1/wallets (response) | status | HIGH | Yes | happy path (eq 'active') | -- |
| POST /api/v1/wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted in happy path |
| GET /api/v1/wallets (response) | wallets array | HIGH | No | -- | HIGH: response shape not verified |
| GET /api/v1/wallets (response) | ordering | HIGH | No | -- | MEDIUM: ordering not verified |
| PATCH /api/v1/wallets/:id (all) | all fields | HIGH | No | -- | HIGH: entire endpoint untested |
| Wallet (DB) | user_id | HIGH | Yes (implicit) | create scoped to user | -- |
| Wallet (DB) | currency | HIGH | Yes | valid, nil, invalid | missing: duplicate constraint |
| Wallet (DB) | name | HIGH | Yes | nil | missing: length constraints |
| Wallet (DB) | balance | HIGH | Partial | default 0 in happy path | missing: >= 0 validation |
| Wallet (DB) | status | HIGH | No | -- | HIGH: enum values (active/suspended/closed) not tested through API |
| Wallet (DB) | [user_id, currency] unique index | HIGH | No | -- | HIGH: duplicate currency per user not tested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` -- entire endpoint has zero test coverage (wallets_controller.rb:29-45). This endpoint has a data leak bug: the 422 error response includes `wallet_id`, `balance`, and `user_id` (line 39-44).

  Suggested test:
  ```ruby
  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let!(:wallet) { create(:wallet, user: user, currency: 'USD', name: 'My Wallet') }
    let(:params) { { wallet: { name: new_name } } }
    let(:new_name) { 'Updated Wallet' }

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet.id}", params: params, headers: headers
    end

    context 'happy path' do
      it 'updates the wallet and returns correct response' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['wallet']['name']).to eq('Updated Wallet')
        expect(body['wallet']['id']).to eq(wallet.id)
        expect(body['wallet']['currency']).to eq('USD')
        expect(body['wallet']['status']).to eq('active')
        expect(wallet.reload.name).to eq('Updated Wallet')
      end
    end

    context 'when wallet does not exist' do
      it 'returns 404' do
        patch '/api/v1/wallets/999999', params: params, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when wallet belongs to another user' do
      let(:other_user) { create(:user) }
      let(:other_wallet) { create(:wallet, user: other_user) }

      it 'returns 404 (IDOR protection)' do
        patch "/api/v1/wallets/#{other_wallet.id}", params: params, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when name is invalid (too long)' do
      let(:new_name) { 'x' * 101 }

      it 'returns 422 and does not leak sensitive data' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        # BUG: currently leaks wallet_id, balance, user_id in error response
        expect(body).not_to have_key('balance')
        expect(body).not_to have_key('user_id')
        expect(body).not_to have_key('wallet_id')
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        patch "/api/v1/wallets/#{wallet.id}", params: params
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` request field `currency` -- no test for duplicate currency per user. Unique constraint `[user_id, currency]` exists in DB but is untested through the API.

  Suggested test:
  ```ruby
  context 'when user already has a wallet with this currency' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422 and does not create a duplicate wallet' do
      expect {
        post '/api/v1/wallets', params: params, headers: headers
      }.not_to change(Wallet, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `GET /api/v1/wallets` response shape -- test only checks status code, does not verify response body contains wallets array with correct fields.

  Suggested test:
  ```ruby
  describe 'GET /api/v1/wallets' do
    let!(:wallet) { create(:wallet, user: user, currency: 'USD', name: 'My Wallet') }

    it 'returns wallets with all fields' do
      get '/api/v1/wallets', headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['wallets'].length).to eq(1)
      w = body['wallets'].first
      expect(w['id']).to eq(wallet.id)
      expect(w['currency']).to eq('USD')
      expect(w['name']).to eq('My Wallet')
      expect(w['balance']).to eq('0.0')
      expect(w['status']).to eq('active')
      expect(w).to have_key('created_at')
    end

    it 'returns wallets ordered by currency' do
      create(:wallet, user: user, currency: 'BTC')
      get '/api/v1/wallets', headers: headers
      body = JSON.parse(response.body)
      currencies = body['wallets'].map { |w| w['currency'] }
      expect(currencies).to eq(currencies.sort)
    end

    it 'does not return other users wallets' do
      other_user = create(:user)
      create(:wallet, user: other_user, currency: 'EUR')
      get '/api/v1/wallets', headers: headers
      body = JSON.parse(response.body)
      expect(body['wallets'].length).to eq(1)
    end
  end
  ```

- [ ] `POST /api/v1/wallets` -- no test for unauthenticated request (missing auth → 401). [FINTECH]

  Suggested test:
  ```ruby
  context 'when unauthenticated' do
    it 'returns 401' do
      post '/api/v1/wallets', params: params
      expect(response).to have_http_status(:unauthorized)
    end
  end
  ```

- [ ] `GET /api/v1/wallets` -- no test for unauthenticated request (missing auth → 401). [FINTECH]

- [ ] `PATCH /api/v1/wallets/:id` -- error response leaks `wallet_id`, `balance`, and `user_id` (wallets_controller.rb:39-44). No test verifies error response body content. [FINTECH]

- [ ] `POST /api/v1/wallets` -- no idempotency key on mutating financial endpoint. Duplicate requests can create duplicate wallets (mitigated by unique constraint but no idempotency handling). [FINTECH]

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/wallets` request field `name` -- missing empty string, max length (100), and over max length (101) scenarios
- [ ] `POST /api/v1/wallets` response field `created_at` -- not asserted in happy path
- [ ] `POST /api/v1/wallets` response field `id` -- not asserted in happy path
- [ ] `GET /api/v1/wallets` -- does not verify ordering by currency
- [ ] `GET /api/v1/wallets` -- no test for empty state (user with no wallets)
- [ ] `POST /api/v1/wallets` -- no test for each valid currency value (USD, EUR, GBP, BTC, ETH) explicitly verified
- [ ] No rate limiting detected on financial mutation endpoints (POST, PATCH). [FINTECH]
- [ ] No audit trail table/fields for wallet mutations. [FINTECH]

**LOW** (rare corner cases)

- [ ] `POST /api/v1/wallets` request field `status` -- no test for explicitly setting status on create (should it be allowed?)

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | spec/requests/api/v1/wallets_spec.rb | HIGH | Split into post_wallets_spec.rb, get_wallets_spec.rb, patch_wallets_spec.rb |
| Status-only assertions (no response body check) | wallets_spec.rb:44, 55, 64 | HIGH | Assert error body contains meaningful message |
| Missing test foundation pattern | wallets_spec.rb (POST section) | MEDIUM | Add subject(:run_test) and DEFAULT constants |
| Error response leaks internal state | wallets_controller.rb:39-44 (PATCH error) | CRITICAL | Remove wallet_id, balance, user_id from 422 response |
| Model spec tests internal methods | spec/models/wallet_spec.rb | MEDIUM | Delete -- test deposit!/withdraw! through API endpoints instead |
| GET index test has no assertions beyond status | wallets_spec.rb:73-78 | HIGH | Assert response shape, fields, ordering |

### Missing Infrastructure [FINTECH]

- No idempotency key on mutating endpoints (POST, PATCH) -- duplicate requests can create duplicate financial records
- No rate limiting detected -- consider adding to prevent brute-force attacks
- No audit trail detected -- financial operations should be auditable
- No KYC/AML fields, transaction limits, or compliance validations detected on wallet creation

### Top 5 Priority Actions

1. **Add test file for PATCH /api/v1/wallets/:id** -- entire endpoint is untested and contains a data leak bug that exposes wallet balance and user_id in error responses (wallets_controller.rb:39-44)
2. **Fix data leak in PATCH error response** -- remove `wallet_id`, `balance`, and `user_id` from the 422 JSON response body, then add test asserting error responses do not contain sensitive fields
3. **Split wallets_spec.rb into one file per endpoint** -- current file mixes POST, GET, and (missing) PATCH, obscuring that PATCH has zero coverage
4. **Add response body assertions to GET /api/v1/wallets** -- currently only checks status 200, does not verify wallet fields, ordering, or data isolation
5. **Add duplicate currency test for POST /api/v1/wallets** -- unique constraint `[user_id, currency]` exists in DB but is never tested through the API boundary
