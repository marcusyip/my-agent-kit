## TDD Contract Review: wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets, PATCH /api/v1/wallets/:id
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb
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
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 4/10 | 15% | 0.60 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.90** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/wallets_controller.rb
        app/models/wallet.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):
  POST /api/v1/wallets
    Request params:
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - name (string, required, max: 100) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string, decimal-as-string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (datetime, ISO8601) [HIGH confidence]
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
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string, decimal-as-string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (datetime, ISO8601) [HIGH confidence]
    Status codes: 200, 404, 422, 401
    BUG: Error response (422) leaks balance, user_id, wallet_id in response body

DB Contract:
  Wallet model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK → users) [HIGH confidence]
    - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, NOT NULL, max: 100) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default: 0, >= 0) [HIGH confidence]
    - status (string, NOT NULL, default: 'active', enum: active/suspended/closed) [HIGH confidence]
    - created_at, updated_at [HIGH confidence]

  Constraints:
    - Unique index on [user_id, currency] [HIGH confidence]
    - balance >= 0 validation [HIGH confidence]

  Business rules:
    - One wallet per currency per user [HIGH confidence]
    - Balance defaults to 0 on create [HIGH confidence]
    - Status defaults to 'active' on create [HIGH confidence]
============================
```

### Checkpoint 1 -- Contract Type Verification

| # | Contract Type | Status | Fields Found | Source Files Read |
|---|---------------|--------|-------------|-------------------|
| 1 | API (inbound) | Extracted | 18 | wallets_controller.rb |
| 2 | DB (models/schema) | Extracted | 7 | wallet.rb, 002_create_wallets.rb |
| 3 | Outbound API calls | Not applicable | -- | No outbound API calls in wallet endpoints |
| 4 | Jobs/consumers | Not applicable | -- | No job files in project |
| 5 | UI props | Not applicable | -- | Backend-only API project |

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | balance (decimal(20,8)) | 1 MEDIUM |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | wallet status: active/suspended/closed | 1 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | balance field, default 0 | 1 MEDIUM |
| 5 | External Payment Integrations | Not applicable | -- | -- |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Not detected -- flagged | -- | Infrastructure gap |
| 8 | Security & Access Control | Extracted | authenticate_user!, current_user scoping | 3 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

---

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ creates Wallet (count +1)
│   ├── ✓ response: currency = 'USD'
│   ├── ✓ response: name = 'My USD Wallet'
│   ├── ✓ response: balance = '0.0'
│   ├── ✓ response: status = 'active'
│   ├── ✗ response: id not asserted
│   └── ✗ response: created_at not asserted
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid ('XYZ') → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) individually
│   └── ✗ duplicate currency per user → 422
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100) → should succeed
│   └── ✗ over max length (101) → 422
├── field: status (DB default)
│   └── ✗ defaults to 'active' (asserted in response but not DB)
├── security: authentication — NO TESTS
│   └── ✗ missing auth token → 401
└── security: error response data
    └── ✗ 422 response does not leak internal data

GET /api/v1/wallets
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response shape not asserted (wallets array)
│   └── ✗ ordering not verified (by currency)
├── security: authentication — NO TESTS
│   └── ✗ missing auth token → 401
└── security: data isolation — NO TESTS
    └── ✗ only returns current user's wallets

PATCH /api/v1/wallets/:id — COMPLETELY UNTESTED
├── happy path — NO TESTS
│   ├── ✗ update name → 200 with updated fields
│   ├── ✗ update currency → 200 with updated fields
│   └── ✗ update status → 200 with updated fields
├── field: currency — NO TESTS
│   ├── ✗ invalid currency → 422
│   └── ✗ duplicate currency per user → 422
├── field: name — NO TESTS
│   ├── ✗ over max length → 422
│   └── ✗ nil → 422
├── field: status — NO TESTS
│   ├── ✗ active → suspended
│   ├── ✗ active → closed
│   └── ✗ invalid status value → 422
├── not found — NO TESTS
│   └── ✗ wallet does not exist → 404
├── security: IDOR — NO TESTS
│   └── ✗ another user's wallet → 404
├── security: authentication — NO TESTS
│   └── ✗ missing auth token → 401
└── security: error response data leak — NO TESTS (BUG)
    └── ✗ 422 response leaks balance, user_id, wallet_id (wallets_controller.rb:39-44)
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value, duplicate per user |
| POST /wallets (request) | name | HIGH | Yes | nil | MEDIUM: empty string, max length, over-max |
| POST /wallets (response) | id | HIGH | No | -- | MEDIUM: not asserted in happy path |
| POST /wallets (response) | currency | HIGH | Yes | happy path | -- |
| POST /wallets (response) | name | HIGH | Yes | happy path | -- |
| POST /wallets (response) | balance | HIGH | Yes | happy path (0.0) | -- |
| POST /wallets (response) | status | HIGH | Yes | happy path (active) | -- |
| POST /wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted |
| POST /wallets (DB) | Wallet created | HIGH | Yes | count +1 | -- |
| Wallet (DB) | currency uniqueness per user | HIGH | No | -- | HIGH: untested |
| Wallet (DB) | status enum | HIGH | No | -- | HIGH: active/suspended/closed not tested via API |
| Wallet (DB) | balance default | HIGH | Partial | in response | -- |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: response shape not asserted |
| GET /wallets (security) | data isolation | HIGH | No | -- | HIGH: not tested |
| PATCH /wallets (all) | entire endpoint | HIGH | No | -- | HIGH: completely untested |
| PATCH /wallets (security) | error data leak | HIGH | No | -- | HIGH: 422 response leaks balance, user_id, wallet_id |
| Security | auth (all 3 endpoints) | HIGH | No | -- | HIGH: no auth tests |

### Checkpoint 2 -- Gap Analysis Verification

| # | Contract Type | Gaps Checked? | HIGH Gaps | MEDIUM Gaps | LOW Gaps |
|---|---------------|---------------|-----------|-------------|----------|
| 1 | API (inbound) | Yes | 7 | 5 | 0 |
| 2 | DB (models/schema) | Yes | 2 | 0 | 0 |

---

### Gap Analysis

#### HIGH Priority Gaps

**H1: PATCH /api/v1/wallets/:id -- entire endpoint is untested**
Zero test coverage for the update endpoint. Any change to update behavior (validation, authorization, response shape) would go undetected.

Suggested test (new file `spec/requests/api/v1/patch_wallet_spec.rb`):
```ruby
RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
  DEFAULT_CURRENCY = 'USD'
  DEFAULT_NAME = 'My USD Wallet'

  subject(:run_test) do
    patch "/api/v1/wallets/#{wallet_id}", params: { wallet: wallet_params }, headers: headers
  end

  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
  let(:wallet_id) { wallet.id }
  let(:wallet_params) { { name: new_name } }
  let(:new_name) { 'Updated Wallet Name' }

  context 'happy path' do
    it 'returns 200 with updated wallet' do
      run_test
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['wallet']['name']).to eq('Updated Wallet Name')
      expect(body['wallet']['currency']).to eq(DEFAULT_CURRENCY)
      expect(body['wallet']['id']).to eq(wallet.id)
    end

    it 'persists the change in DB' do
      run_test
      expect(wallet.reload.name).to eq('Updated Wallet Name')
    end
  end

  context 'when wallet not found' do
    let(:wallet_id) { 999_999 }

    it 'returns 404' do
      run_test
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when wallet belongs to another user' do
    let(:other_user) { create(:user) }
    let(:other_wallet) { create(:wallet, user: other_user) }
    let(:wallet_id) { other_wallet.id }

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

  context 'without authentication' do
    let(:headers) { {} }

    it 'returns 401' do
      run_test
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

**H2: PATCH /api/v1/wallets/:id -- error response leaks sensitive data (BUG) [FINTECH]**
The `RecordInvalid` rescue block in `wallets_controller.rb:39-44` exposes `wallet.balance`, `wallet.user_id`, and `wallet.id` in the error response. This is a security vulnerability.

Suggested test:
```ruby
context 'when validation fails on PATCH' do
  let(:wallet_params) { { name: '' } }

  it 'does not leak balance, user_id, or wallet_id in error response' do
    run_test
    body = JSON.parse(response.body)
    expect(body).not_to have_key('balance')
    expect(body).not_to have_key('user_id')
    expect(body).not_to have_key('wallet_id')
  end
end
```

**H3: POST /api/v1/wallets -- duplicate currency per user not tested**

Suggested test:
```ruby
context 'when user already has a wallet with the same currency' do
  before { create(:wallet, user: user, currency: 'USD') }

  it 'returns 422 and does not create a wallet' do
    expect {
      post '/api/v1/wallets', params: params, headers: headers
    }.not_to change(Wallet, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

**H4: Security -- no authentication tests for any endpoint**

Suggested test:
```ruby
context 'without authentication' do
  it 'returns 401 for POST' do
    post '/api/v1/wallets', params: { wallet: { currency: 'USD', name: 'Test' } }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 for GET index' do
    get '/api/v1/wallets'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 for PATCH' do
    patch '/api/v1/wallets/1', params: { wallet: { name: 'x' } }
    expect(response).to have_http_status(:unauthorized)
  end
end
```

**H5: GET /api/v1/wallets -- response shape not verified**

Suggested test:
```ruby
context 'happy path' do
  before { create_list(:wallet, 2, user: user) }

  it 'returns wallets array with correct shape' do
    get '/api/v1/wallets', headers: headers
    body = JSON.parse(response.body)
    expect(body['wallets']).to be_an(Array)
    expect(body['wallets'].length).to eq(2)

    wallet_json = body['wallets'].first
    expect(wallet_json).to have_key('id')
    expect(wallet_json).to have_key('currency')
    expect(wallet_json).to have_key('name')
    expect(wallet_json).to have_key('balance')
    expect(wallet_json).to have_key('status')
    expect(wallet_json).to have_key('created_at')
  end
end
```

**H6: GET /api/v1/wallets -- data isolation not tested**

Suggested test:
```ruby
context 'data isolation' do
  let(:other_user) { create(:user) }

  before do
    create(:wallet, user: user, currency: 'USD')
    create(:wallet, user: other_user, currency: 'EUR')
  end

  it 'only returns current user wallets' do
    get '/api/v1/wallets', headers: headers
    body = JSON.parse(response.body)
    expect(body['wallets'].length).to eq(1)
  end
end
```

**H7: Wallet status transitions not tested via API [FINTECH]**
Wallet has three status values (active/suspended/closed) but no API tests verify status transitions or behavior changes per status.

#### MEDIUM Priority Gaps

**M1: POST /api/v1/wallets -- currency empty string not tested**
**M2: POST /api/v1/wallets -- name max length (100) not boundary-tested**
**M3: POST /api/v1/wallets -- response fields `id` and `created_at` not asserted**
**M4: POST /api/v1/wallets -- each valid currency value not individually verified**
**M5: POST /api/v1/wallets -- error tests only assert status, not error message body or no-side-effect**

---

### Fintech Gap Analysis

#### Missing Infrastructure

| Priority | Finding |
|---|---|
| HIGH | **Error response data leak in PATCH endpoint** -- `wallets_controller.rb:39-44` returns `balance`, `user_id`, `wallet_id` in 422 response body. Attackers can extract sensitive financial data by triggering validation errors |
| MEDIUM | **No rate limiting on wallet creation** -- could be abused for resource exhaustion |
| MEDIUM | **No audit trail for wallet status changes** -- status changes (active → suspended → closed) are not logged |

---

### Anti-Patterns

| # | Anti-Pattern | Severity | Details |
|---|---|---|---|
| 1 | Multiple endpoints in one test file | MAJOR | POST and GET are in `wallets_spec.rb`. PATCH is completely missing. Split into `post_wallets_spec.rb`, `get_wallets_spec.rb`, `patch_wallet_spec.rb` |
| 2 | No test foundation pattern | MAJOR | No DEFAULT constants, no `subject(:run_test)` |
| 3 | Entire endpoint untested | CRITICAL | PATCH /api/v1/wallets/:id has zero tests |
| 4 | Error tests status-only | MEDIUM | Error scenarios only check `have_http_status(...)`, don't verify error message or no-side-effects |
| 5 | Model spec for wallet exists | MEDIUM | `spec/models/wallet_spec.rb` tests internal `deposit!`/`withdraw!` methods. These should be tested through the API endpoint instead |
