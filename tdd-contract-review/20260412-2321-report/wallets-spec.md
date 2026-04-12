## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets, PATCH /api/v1/wallets/:id (untested)
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb, db/migrate/002_create_wallets.rb
**Framework:** Rails 7.1 / RSpec (request spec)

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

### Overall Score: 4.3 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 5/10 | 15% | 0.75 |
| Isolation & Flakiness | 6/10 | 15% | 0.90 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **4.30** |

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
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - name (string, required, max: 100) [HIGH confidence]
      - status (string, optional, via permit) [MEDIUM confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string, decimal-as-string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401
    Auth: before_action :authenticate_user!

  GET /api/v1/wallets
    Response fields:
      - wallets (array of wallet objects) [HIGH confidence]
    Status codes: 200, 401
    Auth: before_action :authenticate_user!

  PATCH /api/v1/wallets/:id
    Request params:
      - currency (string, optional) [HIGH confidence]
      - name (string, optional) [HIGH confidence]
      - status (string, optional) [HIGH confidence]
    Response fields:
      - wallet (object, same shape as POST response) [HIGH confidence]
    Status codes: 200, 404, 422, 401
    Auth: before_action :authenticate_user!

DB Contract:
  Wallet model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, NOT NULL, max: 100) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default: 0) [HIGH confidence]
    - status (string, NOT NULL, default: 'active', enum: active/suspended/closed) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]
  Unique constraint: [user_id, currency] [HIGH confidence]
  Association: has_many :transactions, dependent: :restrict_with_error [HIGH confidence]

  Business methods:
    - deposit!(amount): increases balance, requires active status, requires positive amount, uses with_lock [HIGH confidence]
    - withdraw!(amount): decreases balance, requires active status, requires positive amount, requires sufficient balance, uses with_lock [HIGH confidence]
============================
```

**Total contract fields extracted: 30** (6 request params across 3 endpoints + 7 response fields + 4 status code sets + 8 DB columns + 2 business methods + unique constraint + association + default balance). Extraction complete.

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | balance (decimal(20,8)), default: 0 | 1 HIGH, 1 MEDIUM |
| 2 | Idempotency | Not detected -- flagged | -- | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | wallet status enum: active/suspended/closed | 2 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | balance field, deposit!, withdraw!, with_lock | 2 HIGH |
| 5 | External Payment Integrations | Not applicable | -- | -- |
| 6 | Regulatory & Compliance | Not detected -- flagged | -- | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | with_lock in deposit!/withdraw! | 1 HIGH |
| 8 | Security & Access Control | Extracted | authenticate_user!, current_user scoping | 3 HIGH |

**Fintech mode:** Active -- all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ creates wallet (DB count assertion)
│   ├── ✓ response body: currency
│   ├── ✓ response body: name
│   ├── ✓ response body: balance ('0.0')
│   ├── ✓ response body: status ('active')
│   ├── ✗ response body: id
│   └── ✗ response body: created_at
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → success
│   └── ✗ duplicate currency for same user → 422 (unique constraint)
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100) → success
│   └── ✗ over max length (101) → 422
├── field: status (request param) — NO TESTS
│   ├── ✗ can user set initial status? (mass assignment concern)
│   └── ✗ invalid status value → 422
├── [FINTECH] security: auth — NO TESTS
│   └── ✗ missing auth token → 401
├── [FINTECH] idempotency — NO TESTS
│   └── ✗ duplicate POST for same currency → should return existing (unique constraint)
└── error path side effects — NOT ASSERTED
    └── ✗ error scenarios should assert no DB write

GET /api/v1/wallets
├── happy path
│   ├── ✓ returns 200 (status only)
│   ├── ✗ response body: wallets array shape
│   ├── ✗ response body: each wallet has all 6 fields
│   └── ✗ ordering (by currency)
├── [FINTECH] security: auth — NO TESTS
│   └── ✗ missing auth token → 401
└── [FINTECH] security: data leakage — NO TESTS
    └── ✗ only returns current user's wallets

PATCH /api/v1/wallets/:id — NO TESTS (entire endpoint untested)
├── happy path
│   ├── ✗ returns 200 with updated wallet
│   ├── ✗ DB record updated correctly
│   └── ✗ response body asserts all 6 fields
├── field: currency — NO TESTS
│   ├── ✗ change to valid currency → success
│   ├── ✗ change to invalid currency → 422
│   └── ✗ change to duplicate (same user) → 422
├── field: name — NO TESTS
│   ├── ✗ change to valid name → success
│   ├── ✗ change to too-long name → 422
│   └── ✗ nil (remove name) → 422
├── field: status — NO TESTS
│   ├── ✗ active → suspended → success
│   ├── ✗ suspended → active → success
│   ├── ✗ active → closed → success
│   └── ✗ invalid status → 422
├── field: id (path param) — NO TESTS
│   ├── ✗ not found → 404
│   └── ✗ another user's wallet → 404 (IDOR)
├── [FINTECH] security: auth — NO TESTS
│   └── ✗ missing auth token → 401
└── [FINTECH] security: IDOR — NO TESTS
    └── ✗ update another user's wallet → 404
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid, duplicate per user |
| POST /wallets (request) | name | HIGH | Yes | nil | MEDIUM: empty string, max length, over max |
| POST /wallets (request) | status | MEDIUM | No | -- | HIGH: mass assignment not tested |
| POST /wallets (response) | id | HIGH | No | -- | MEDIUM: not asserted in happy path |
| POST /wallets (response) | currency | HIGH | Yes | asserted | -- |
| POST /wallets (response) | name | HIGH | Yes | asserted | -- |
| POST /wallets (response) | balance | HIGH | Yes | asserted ('0.0') | -- |
| POST /wallets (response) | status | HIGH | Yes | asserted ('active') | -- |
| POST /wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: shape not asserted |
| GET /wallets (response) | ordering | HIGH | No | -- | MEDIUM: not verified |
| PATCH /wallets/:id (request) | currency | HIGH | No | -- | HIGH: entire endpoint untested |
| PATCH /wallets/:id (request) | name | HIGH | No | -- | HIGH: entire endpoint untested |
| PATCH /wallets/:id (request) | status | HIGH | No | -- | HIGH: entire endpoint untested |
| PATCH /wallets/:id (param) | id | HIGH | No | -- | HIGH: not found, IDOR untested |
| PATCH /wallets/:id (response) | all 6 fields | HIGH | No | -- | HIGH: untested |
| Wallet (DB) | user_id | HIGH | Implicit | via create(:wallet, user:) | -- |
| Wallet (DB) | currency | HIGH | Yes | via POST tests | MEDIUM: unique constraint not tested |
| Wallet (DB) | name | HIGH | Yes | via POST tests | -- |
| Wallet (DB) | balance | HIGH | Yes | asserted as '0.0' | -- |
| Wallet (DB) | status | HIGH | No | -- | HIGH: enum values suspended/closed untested via API |
| Wallet (DB) | unique [user_id, currency] | HIGH | No | -- | HIGH: duplicate currency not tested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` -- entire endpoint has zero test coverage. All request params, response fields, error paths, and IDOR scenarios are untested.

Suggested test:
```ruby
# spec/requests/api/v1/patch_wallet_spec.rb
RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
  DEFAULT_CURRENCY = 'USD'
  DEFAULT_NAME = 'My Wallet'

  subject(:run_test) do
    patch "/api/v1/wallets/#{wallet_id}", params: { wallet: params }, headers: headers
  end

  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
  let(:wallet_id) { wallet.id }
  let(:params) { { name: new_name } }
  let(:new_name) { 'Updated Wallet' }

  context 'happy path' do
    it 'returns 200 with updated wallet' do
      run_test
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['wallet']['name']).to eq('Updated Wallet')
      expect(body['wallet']['currency']).to eq(DEFAULT_CURRENCY)
      expect(body['wallet']['status']).to eq('active')
      expect(body['wallet']).to have_key('id')
      expect(body['wallet']).to have_key('balance')
      expect(body['wallet']).to have_key('created_at')
    end

    it 'persists changes in DB' do
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

  context 'when wallet belongs to another user (IDOR)' do
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

  context 'when status changed to suspended' do
    let(:params) { { status: 'suspended' } }

    it 'returns 200 and updates status' do
      run_test
      expect(response).to have_http_status(:ok)
      expect(wallet.reload.status).to eq('suspended')
    end
  end
end
```

- [ ] `POST /api/v1/wallets` unique constraint `[user_id, currency]` -- no test for duplicate currency per user.

Suggested test:
```ruby
context 'when user already has wallet with same currency' do
  before { create(:wallet, user: user, currency: 'USD') }

  it 'returns 422 and does not create wallet' do
    expect {
      post '/api/v1/wallets', params: params, headers: headers
    }.not_to change(Wallet, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] `GET /api/v1/wallets` -- response body shape not asserted. Only checks status 200.

Suggested test:
```ruby
it 'returns wallets with correct shape and ordering' do
  create(:wallet, user: user, currency: 'EUR', name: 'EUR Wallet')
  create(:wallet, user: user, currency: 'USD', name: 'USD Wallet')
  get '/api/v1/wallets', headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  wallets = body['wallets']
  expect(wallets.length).to eq(2)
  expect(wallets.first['currency']).to eq('EUR')  # ordered by currency
  expect(wallets.first).to have_key('id')
  expect(wallets.first).to have_key('name')
  expect(wallets.first).to have_key('balance')
  expect(wallets.first).to have_key('status')
  expect(wallets.first).to have_key('created_at')
end
```

- [ ] [FINTECH] All 3 endpoints missing authentication tests -- no test for missing auth token returning 401.

Suggested test:
```ruby
context 'when auth token is missing' do
  it 'returns 401' do
    post '/api/v1/wallets', params: params
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] [FINTECH] Wallet status enum values `suspended` and `closed` -- no API-level tests verify behavior when wallet is in these states (e.g., can a suspended wallet be updated? Can transactions be created against it?).

- [ ] [FINTECH] `POST /api/v1/wallets` field `status` mass assignment -- the controller permits `:status` via `wallet_params`. No test verifies whether a user can set the initial status to `suspended` or `closed` on creation (potential privilege escalation).

Suggested test:
```ruby
context 'when user tries to set initial status to suspended' do
  let(:params) do
    { wallet: { currency: 'USD', name: 'Test', status: 'suspended' } }
  end

  it 'should either reject or ignore the status param' do
    post '/api/v1/wallets', params: params, headers: headers
    # Depending on desired behavior:
    # Option A: rejects
    # expect(response).to have_http_status(:unprocessable_entity)
    # Option B: ignores and defaults to active
    expect(response).to have_http_status(:created)
    expect(Wallet.last.status).to eq('active')
  end
end
```

- [ ] [FINTECH] Concurrency: `deposit!` and `withdraw!` use `with_lock` but no test verifies the lock prevents concurrent corruption.

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/wallets` field `currency` -- missing empty string edge case
- [ ] `POST /api/v1/wallets` field `currency` -- missing test for each valid value
- [ ] `POST /api/v1/wallets` field `name` -- missing empty string, max length (100), over-max (101) tests
- [ ] `POST /api/v1/wallets` error scenarios -- missing `not_to change(Wallet, :count)` assertions on error paths (only checks status)
- [ ] `GET /api/v1/wallets` -- missing ordering verification (should be by currency)
- [ ] [FINTECH] Balance field -- default value tested as '0.0' but no negative balance prevention test via API

**LOW** (rare corner cases)

- [ ] `POST /api/v1/wallets` -- wallet with transactions cannot be destroyed (restrict_with_error) -- indirect, low priority

### Missing Infrastructure (Fintech)

- [ ] **[FINTECH] MEDIUM: No rate limiting detected** on wallet mutation endpoints.
- [ ] **[FINTECH] MEDIUM: No audit trail detected** -- wallet status changes and balance operations should be auditable.
- [ ] **[FINTECH] MEDIUM: No balance validation or ledger consistency patterns** detected at the API level -- balance integrity depends on model-level checks only.

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | wallets_spec.rb (POST + GET index, missing PATCH) | HIGH | Split into post-wallets-spec.rb, get-wallets-spec.rb, patch-wallet-spec.rb |
| Entire endpoint untested | PATCH /api/v1/wallets/:id | HIGH | Create patch-wallet-spec.rb with full coverage |
| Status-only assertions on error paths | wallets_spec.rb:44, 51, 58, 64 | MEDIUM | Add `not_to change(Wallet, :count)` assertions |
| Status-only assertion on GET index | wallets_spec.rb:73-76 | MEDIUM | Assert response body shape and ordering |

### Top 5 Priority Actions

1. **Create test file for PATCH /api/v1/wallets/:id** -- entire endpoint has zero coverage. Status changes, name updates, not-found, and IDOR scenarios all untested.
2. **Add duplicate currency per user test for POST** -- the unique constraint `[user_id, currency]` is a core business rule with no test. A migration change removing this constraint would break silently.
3. **Add authentication tests for all 3 endpoints** -- no test verifies that unauthenticated requests are rejected with 401.
4. **Add response body assertions to GET /api/v1/wallets** -- the index test only checks status 200, not the array shape, field presence, or ordering.
5. **Test status field mass assignment on POST** -- the controller permits `:status`, so users might be able to create wallets with suspended/closed status. This is a potential privilege escalation.
