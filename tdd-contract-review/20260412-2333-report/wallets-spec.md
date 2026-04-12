## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets (PATCH /api/v1/wallets/:id entirely missing)
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb, db/migrate/002_create_wallets.rb
**Framework:** Rails 7.1 / RSpec (request spec)

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every API endpoint, job, and message consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `+` = scenario is tested
- `x` = scenario is missing (potential silent breakage)
- Each entry point (endpoint, job, consumer) gets its own section
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**One endpoint per file:** Each API endpoint, job, or consumer should have its own test file. This makes gaps immediately visible -- if a file doesn't exist, the entire contract is untested.

**Contract boundary:** Tests should verify behavior at the contract boundary (API endpoint, job entry point), not internal implementation. Testing that a service method is called is implementation testing -- testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have. A codebase with 100 tests that only check status codes scores lower than one with 20 tests that verify response fields, DB state, and error paths.

### Overall Score: 4.4 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 6/10 | 15% | 0.90 |
| Isolation & Flakiness | 5/10 | 15% | 0.75 |
| Anti-Patterns | 4/10 | 10% | 0.40 |
| **Overall** | | | **4.40** |

### Verdict: NEEDS IMPROVEMENT

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/wallets_controller.rb
        app/models/wallet.rb
        db/migrate/002_create_wallets.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):

  POST /api/v1/wallets
    Request params:
      - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - name (string, required, max 100) [HIGH confidence]
      - status (string, optional, permitted) [MEDIUM confidence]
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
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
    Status codes: 200, 404, 422, 401

DB Contract:
  Wallet model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - name (string, NOT NULL) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default: 0) [HIGH confidence]
    - status (string, NOT NULL, default: 'active', enum: active/suspended/closed) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]
  Unique constraint: [user_id, currency] [HIGH confidence]

Business Rules:
  - Currency must be one of: USD, EUR, GBP, BTC, ETH [HIGH confidence]
  - Currency unique per user (one wallet per currency) [HIGH confidence]
  - Name max length: 100 [HIGH confidence]
  - Balance must be >= 0 [HIGH confidence]
  - Default balance: 0 [HIGH confidence]
  - Default status: active [HIGH confidence]
============================
Total contract fields extracted: 32
```

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | balance (decimal(20,8)) | 1 HIGH |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | status enum: active/suspended/closed | 1 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | balance field, deposit!/withdraw! with_lock | 1 HIGH, 1 MEDIUM |
| 5 | External Payment Integrations | Not applicable | -- | -- |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | with_lock in deposit!/withdraw! | 1 HIGH |
| 8 | Security & Access Control | Extracted | before_action :authenticate_user!, wallet scoped to current_user | 2 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/wallets
|-- field: currency (request param)
|   |-- + nil -> 422
|   |-- + invalid ('XYZ') -> 422
|   |-- x empty string -> 422
|   |-- x each valid value (USD, EUR, GBP, BTC, ETH)
|   |-- x duplicate currency per user -> 422 (unique constraint)
|-- field: name (request param)
|   |-- + nil -> 422
|   |-- x empty string -> 422
|   |-- x max length (100) -> should succeed
|   |-- x over max length (101) -> 422
|-- field: status (request param)
|   |-- x status permitted in params but no tests
|-- response body
|   |-- + happy path asserts currency, name, balance, status
|   |-- x missing: id, created_at assertions
|-- DB assertions
|   |-- + happy path asserts Wallet count +1
|   |-- x error paths don't assert no Wallet created
|-- [FINTECH] authentication
|   |-- x missing auth token -> 401
|-- [FINTECH] balance default
|   |-- + verified: balance starts at '0.0'

GET /api/v1/wallets
|-- + returns 200
|-- response body -- MINIMAL ASSERTIONS
|   |-- x should assert wallets array shape
|   |-- x should assert each wallet has all fields
|   |-- x should verify ordering (by currency)
|-- [FINTECH] authentication
|   |-- x missing auth token -> 401
|-- [FINTECH] data isolation
|   |-- x only returns current user's wallets

PATCH /api/v1/wallets/:id -- NO TEST FILE
|-- x happy path: update name -> 200
|-- x happy path: update status -> 200
|-- x wallet not found -> 404
|-- x invalid params -> 422
|-- x another user's wallet -> 404 (IDOR)
|-- x all response fields asserted
|-- [FINTECH] authentication
|   |-- x missing auth token -> 401
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, duplicate per user, each valid value |
| POST /wallets (request) | name | HIGH | Yes | nil | MEDIUM: empty string, max length, over max |
| POST /wallets (request) | status | MEDIUM | No | -- | MEDIUM: not tested |
| POST /wallets (response) | id | HIGH | No | -- | HIGH: not asserted |
| POST /wallets (response) | currency | HIGH | Yes | happy path | -- |
| POST /wallets (response) | name | HIGH | Yes | happy path | -- |
| POST /wallets (response) | balance | HIGH | Yes | happy path (0.0) | -- |
| POST /wallets (response) | status | HIGH | Yes | happy path (active) | -- |
| POST /wallets (response) | created_at | HIGH | No | -- | HIGH: not asserted |
| Wallet (DB) | user_id | HIGH | No | -- | HIGH: not asserted in happy path |
| Wallet (DB) | currency | HIGH | Yes | happy path | -- |
| Wallet (DB) | name | HIGH | Yes | happy path | -- |
| Wallet (DB) | balance | HIGH | Yes | happy path | -- |
| Wallet (DB) | status | HIGH | Partial | only active | HIGH: suspended/closed not tested |
| Wallet (DB) | unique [user_id, currency] | HIGH | No | -- | HIGH: duplicate currency per user untested |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: no shape assertions |
| PATCH /wallets/:id (all) | all fields | HIGH | No | -- | HIGH: entire endpoint untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` -- entire endpoint has zero tests. All request params, response fields, error paths, and business rules are untested.

Suggested test (new file `spec/requests/api/v1/patch_wallet_spec.rb`):
```ruby
# Generated tests follow your project's patterns. Review before committing.
RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
  DEFAULT_NAME = 'My USD Wallet'

  subject(:run_test) do
    patch "/api/v1/wallets/#{wallet_id}", params: { wallet: update_params }, headers: headers
  end

  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:wallet) { create(:wallet, user: user, currency: 'USD', name: DEFAULT_NAME) }
  let(:wallet_id) { wallet.id }
  let(:update_params) { { name: new_name } }
  let(:new_name) { 'Updated Wallet Name' }

  context 'happy path' do
    it 'returns 200 with updated wallet' do
      run_test
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['wallet']['id']).to eq(wallet.id)
      expect(body['wallet']['name']).to eq('Updated Wallet Name')
      expect(body['wallet']['currency']).to eq('USD')
      expect(body['wallet']['status']).to eq('active')
      expect(body['wallet']['balance']).to be_present
      expect(body['wallet']['created_at']).to be_present
    end

    it 'persists the update in DB' do
      run_test
      expect(wallet.reload.name).to eq('Updated Wallet Name')
    end
  end

  context 'when wallet does not exist' do
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
      expect(wallet.reload.name).to eq(DEFAULT_NAME)
    end
  end

  context 'when auth token is missing' do
    let(:headers) { {} }

    it 'returns 401' do
      run_test
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

- [ ] `POST /api/v1/wallets` unique constraint -- duplicate currency per user not tested. The DB has a unique index on [user_id, currency] but no test verifies the 422 when creating a second wallet with the same currency.

Suggested test:
```ruby
context 'when user already has a wallet with this currency' do
  before { create(:wallet, user: user, currency: 'USD') }

  it 'returns 422 and does not create a duplicate wallet' do
    expect {
      post '/api/v1/wallets', params: params, headers: headers
    }.not_to change(Wallet, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['error']).to include('already exists')
  end
end
```

- [ ] `GET /api/v1/wallets` response shape -- no test asserts the structure of the response or individual wallet fields

Suggested test:
```ruby
it 'returns wallets with correct shape ordered by currency' do
  create(:wallet, user: user, currency: 'EUR', name: 'EUR Wallet')
  create(:wallet, user: user, currency: 'USD', name: 'USD Wallet')

  get '/api/v1/wallets', headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  wallets = body['wallets']
  expect(wallets.length).to eq(2)

  # Verify ordering by currency
  expect(wallets[0]['currency']).to eq('EUR')
  expect(wallets[1]['currency']).to eq('USD')

  # Verify shape
  wallet = wallets.first
  expect(wallet).to have_key('id')
  expect(wallet).to have_key('currency')
  expect(wallet).to have_key('name')
  expect(wallet).to have_key('balance')
  expect(wallet).to have_key('status')
  expect(wallet).to have_key('created_at')
end
```

- [ ] `POST /api/v1/wallets` and `GET /api/v1/wallets` [FINTECH] authentication -- no test for missing auth token -> 401

Suggested test:
```ruby
context 'when auth token is missing' do
  it 'returns 401' do
    post '/api/v1/wallets', params: params
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] [FINTECH] Wallet status enum -- no tests verify transition between active/suspended/closed or behavior restrictions per status

- [ ] [FINTECH] Concurrency -- wallet uses `with_lock` in deposit!/withdraw! but no test verifies the lock prevents concurrent corruption

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/wallets` request field `currency` -- missing empty string edge case
- [ ] `POST /api/v1/wallets` request field `name` -- missing empty string, max length (100), over max (101) scenarios
- [ ] `POST /api/v1/wallets` error paths -- currency nil/invalid tests don't assert no Wallet created
- [ ] `GET /api/v1/wallets` [FINTECH] data isolation -- no test verifying only authenticated user's wallets returned
- [ ] `POST /api/v1/wallets` response -- missing id and created_at assertions

**Missing Infrastructure** [FINTECH]

- [ ] **MEDIUM: No balance validation or ledger consistency patterns on wallet creation** -- balance defaults to 0 but no test verifies the default is applied correctly via the API, or that a non-zero balance cannot be submitted on creation.
- [ ] **MEDIUM: No KYC/AML fields, transaction limits, or compliance validations** -- financial user accounts and wallets exist but no regulatory safeguards detected.

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | wallets_spec.rb (POST + GET index, missing PATCH) | HIGH | Split into post-wallets-spec.rb, get-wallets-spec.rb, patch-wallet-spec.rb |
| Missing test foundation | wallets_spec.rb (no subject/run_test, no DEFAULT constants) | MEDIUM | Add `subject(:run_test)` and DEFAULT_CURRENCY, DEFAULT_NAME constants |
| Error-path tests don't assert no DB write | wallets_spec.rb:40-48, :49-56, :58-65 | MEDIUM | Add `expect { ... }.not_to change(Wallet, :count)` |
| Minimal GET index test | wallets_spec.rb:71-78 | MEDIUM | Assert response shape, ordering, individual wallet fields |

### Top 5 Priority Actions

1. **Create tests for PATCH /api/v1/wallets/:id** -- an entire endpoint has zero coverage. All request params, response fields, not-found, IDOR, and validation errors are untested.
2. **Add duplicate currency uniqueness test** -- the unique [user_id, currency] constraint is a critical business rule with no test coverage. A regression here creates corrupted wallet state.
3. **Add response shape assertions to GET /api/v1/wallets** -- the index endpoint only checks status 200. No verification of response structure, wallet fields, or ordering.
4. **Add authentication tests** -- no endpoint has a test for missing/expired auth token -> 401.
5. **Split into one endpoint per file** -- POST and GET in one file, PATCH entirely missing. Split makes gaps immediately visible.
