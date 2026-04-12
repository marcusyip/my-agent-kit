## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets (PATCH /api/v1/wallets/:id — NO TESTS)
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb
**Framework:** Rails 7.1 / RSpec (request spec)
**Fintech mode:** Enabled (balance field, currency, wallet status enum, decimal types)

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

### Overall Score: 4.9 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 4/10 | 20% | 0.80 |
| Test Case Quality | 5/10 | 15% | 0.75 |
| Isolation & Flakiness | 8/10 | 15% | 1.20 |
| Anti-Patterns | 4/10 | 10% | 0.40 |
| **Overall** | | | **4.90** |

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
      - name (string, required, max 100 chars) [HIGH confidence]
      - status (string, optional, enum: active/suspended/closed) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string — decimal.to_s) [HIGH confidence]
      - status (string) [HIGH confidence]
      - created_at (string, ISO8601) [HIGH confidence]
    Error response: { error: string (joined validation messages) }
    Status codes: 201, 422, 401

  GET /api/v1/wallets
    Response fields:
      - wallets (array of wallet objects) [HIGH confidence]
    Ordering: by currency [HIGH confidence]
    Status codes: 200, 401

  PATCH /api/v1/wallets/:id
    Request params:
      - currency (string, optional) [HIGH confidence]
      - name (string, optional) [HIGH confidence]
      - status (string, optional) [HIGH confidence]
    Response fields: same as POST response [HIGH confidence]
    Error response: { error: string }
    Status codes: 200, 404, 422, 401

DB Contract:
  Wallet model:
    - id (integer, PK) [HIGH confidence]
    - user_id (integer, NOT NULL, FK) [HIGH confidence]
    - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, NOT NULL, max 100) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default 0) [HIGH confidence]
    - status (string, NOT NULL, default 'active', enum: active/suspended/closed) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]
  Unique constraint: [user_id, currency] [HIGH confidence]

Business Rules:
  - Currency must be unique per user [HIGH confidence]
  - Balance must be >= 0 [HIGH confidence]
  - Default balance is 0 on create [HIGH confidence]
  - authenticate_user! on all endpoints [HIGH confidence]
  - Wallets scoped to current_user [HIGH confidence]

Fintech Dimensions:
  Money & Precision:
    - balance: decimal(20,8), exact type ✓ [HIGH confidence]
    - Validation: >= 0 [HIGH confidence]
  Balance & Ledger:
    - deposit! and withdraw! use with_lock (pessimistic locking) [HIGH confidence]
    - withdraw! checks balance >= amount before deducting [HIGH confidence]
  Security:
    - authenticate_user! on all endpoints [HIGH confidence]
    - Wallets scoped to current_user.wallets [HIGH confidence]
    - PATCH finds wallet via current_user.wallets.find (IDOR protection) [HIGH confidence]
============================
```

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ creates Wallet (count +1)
│   ├── ✓ response currency = 'USD'
│   ├── ✓ response name = 'My USD Wallet'
│   ├── ✓ response balance = '0.0'
│   ├── ✓ response status = 'active'
│   ├── ✗ response id present
│   └── ✗ response created_at present
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid ('XYZ') → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ duplicate currency for same user → 422 (unique constraint)
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length 100 → should succeed
│   └── ✗ over max length 101 → 422
├── field: status (request param) — NO TESTS
│   ├── ✗ not provided (defaults to 'active')
│   ├── ✗ explicitly set to 'suspended' → behavior?
│   └── ✗ invalid value → 422
├── DB assertions
│   ├── ✓ count increases by 1
│   ├── ✗ user_id set correctly
│   └── ✗ balance defaults to 0 (DB-level)
├── error response body — NOT ASSERTED
│   └── ✗ error message content verified for 422 responses
├── [FINTECH] security
│   ├── ✗ unauthenticated → 401
│   └── ✗ duplicate currency shows correct error message
└── [FINTECH] balance
    └── ✗ default balance is exactly 0 (asserted in response but not DB)

GET /api/v1/wallets
├── ✓ returns 200 (status only)
├── response body — NO ASSERTIONS
│   ├── ✗ wallets array shape
│   ├── ✗ correct number of wallets
│   └── ✗ ordering by currency
├── [FINTECH] security
│   ├── ✗ unauthenticated → 401
│   └── ✗ only returns current user's wallets

PATCH /api/v1/wallets/:id — NO TEST FILE
├── ✗ happy path (update name) → 200 with updated fields
├── ✗ update currency → behavior?
├── ✗ update status → 200
├── field: id (path param)
│   ├── ✗ not found → 404
│   └── ✗ another user's wallet → 404 (IDOR)
├── field: name
│   ├── ✗ valid update
│   ├── ✗ nil/blank → 422
│   └── ✗ over max length → 422
├── field: status
│   ├── ✗ active → suspended
│   ├── ✗ suspended → active
│   ├── ✗ active → closed
│   └── ✗ invalid value → 422
├── [FINTECH] security
│   ├── ✗ unauthenticated → 401
│   └── ✗ another user's wallet → 404
└── validation errors
    └── ✗ RecordInvalid → 422 with error message
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value, duplicate per user |
| POST /wallets (request) | name | HIGH | Yes | nil | MEDIUM: empty string, max length, over max |
| POST /wallets (request) | status | HIGH | No | -- | HIGH: untested (default, explicit values, invalid) |
| POST /wallets (response) | id | HIGH | No | -- | MEDIUM: not asserted in happy path |
| POST /wallets (response) | currency | HIGH | Yes | happy path | -- |
| POST /wallets (response) | name | HIGH | Yes | happy path | -- |
| POST /wallets (response) | balance | HIGH | Yes | happy path ('0.0') | -- |
| POST /wallets (response) | status | HIGH | Yes | happy path ('active') | -- |
| POST /wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted |
| POST /wallets (error) | error message | HIGH | No | -- | MEDIUM: error body content not verified |
| Wallet (DB) | user_id | HIGH | No | -- | MEDIUM: not directly asserted |
| Wallet (DB) | currency | HIGH | Partial | count +1 | -- (covered via response) |
| Wallet (DB) | name | HIGH | Partial | count +1 | -- (covered via response) |
| Wallet (DB) | balance | HIGH | No | -- | MEDIUM: DB default not directly tested |
| Wallet (DB) | status | HIGH | No | -- | HIGH: enum values active/suspended/closed untested in DB |
| Wallet (DB) | unique [user_id, currency] | HIGH | No | -- | HIGH: unique constraint untested |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: no shape assertion |
| GET /wallets (response) | ordering | HIGH | No | -- | MEDIUM: ordering by currency not verified |
| PATCH /wallets/:id (all) | entire endpoint | HIGH | No | -- | HIGH: no tests exist for this endpoint |
| [FINTECH] Security | auth (POST) | HIGH | No | -- | HIGH: no 401 test |
| [FINTECH] Security | auth (GET) | HIGH | No | -- | HIGH: no 401 test |
| [FINTECH] Security | auth (PATCH) | HIGH | No | -- | HIGH: no 401 test |
| [FINTECH] Security | IDOR (PATCH) | HIGH | No | -- | HIGH: no ownership test on PATCH |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 10 gaps)

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint is untested. No test file exists. This endpoint supports update of currency, name, and status, returns 404 for not found, and 422 for validation errors.

Suggested test:
```ruby
# spec/requests/api/v1/patch_wallet_spec.rb
RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
  DEFAULT_CURRENCY = 'USD'
  DEFAULT_NAME = 'My USD Wallet'

  subject(:run_test) do
    patch "/api/v1/wallets/#{wallet_id}", params: { wallet: update_params }, headers: headers
  end

  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
  let(:wallet_id) { wallet.id }
  let(:update_params) { { name: new_name } }
  let(:new_name) { 'Updated Wallet' }

  context 'happy path' do
    it 'returns 200 with updated wallet' do
      run_test
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['wallet']['name']).to eq('Updated Wallet')
      expect(body['wallet']['currency']).to eq(DEFAULT_CURRENCY)
    end

    it 'persists the change' do
      run_test
      expect(wallet.reload.name).to eq('Updated Wallet')
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

  context 'when name is blank' do
    let(:new_name) { '' }

    it 'returns 422' do
      run_test
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'when updating status to suspended' do
    let(:update_params) { { status: 'suspended' } }

    it 'returns 200 with updated status' do
      run_test
      expect(response).to have_http_status(:ok)
      expect(wallet.reload.status).to eq('suspended')
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

- [ ] `POST /api/v1/wallets` request field `status` — no tests for explicitly setting status on create, or invalid status values

Suggested test:
```ruby
context 'when status is explicitly set to suspended' do
  let(:params) do
    { wallet: { currency: currency, name: name, status: 'suspended' } }
  end

  it 'creates wallet with specified status' do
    post '/api/v1/wallets', params: params, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body['wallet']['status']).to eq('suspended')
  end
end
```

- [ ] `POST /api/v1/wallets` DB unique constraint — duplicate currency per user is untested

Suggested test:
```ruby
context 'when user already has a wallet with the same currency' do
  before { create(:wallet, user: user, currency: 'USD') }

  it 'returns 422 and does not create a duplicate' do
    expect {
      post '/api/v1/wallets', params: params, headers: headers
    }.not_to change(Wallet, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['error']).to include('wallet already exists for this currency')
  end
end
```

- [ ] `GET /api/v1/wallets` — no response shape assertions. Test only checks status 200.

Suggested test:
```ruby
it 'returns wallets array with correct shape ordered by currency' do
  btc_wallet = create(:wallet, user: user, currency: 'BTC', name: 'BTC Wallet')
  usd_wallet = create(:wallet, user: user, currency: 'USD', name: 'USD Wallet')
  get '/api/v1/wallets', headers: headers
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  expect(body['wallets'].length).to eq(2)
  expect(body['wallets'][0]['currency']).to eq('BTC')
  expect(body['wallets'][1]['currency']).to eq('USD')
  expect(body['wallets'][0]).to have_key('id')
  expect(body['wallets'][0]).to have_key('balance')
  expect(body['wallets'][0]).to have_key('status')
end
```

- [ ] [FINTECH] Authentication — no test on any wallet endpoint verifies unauthenticated requests return 401

Suggested test:
```ruby
context 'without authentication' do
  it 'POST returns 401' do
    post '/api/v1/wallets', params: { wallet: { currency: 'USD', name: 'Test' } }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'GET returns 401' do
    get '/api/v1/wallets'
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] [FINTECH] Security — GET /api/v1/wallets does not verify it only returns current user's wallets (not other users')

Suggested test:
```ruby
context 'when other users have wallets' do
  let!(:other_wallet) { create(:wallet, user: create(:user), currency: 'EUR') }
  let!(:my_wallet) { create(:wallet, user: user, currency: 'USD') }

  it 'only returns current user wallets' do
    get '/api/v1/wallets', headers: headers
    body = JSON.parse(response.body)
    wallet_ids = body['wallets'].map { |w| w['id'] }
    expect(wallet_ids).to include(my_wallet.id)
    expect(wallet_ids).not_to include(other_wallet.id)
  end
end
```

**MEDIUM** (tested but missing scenarios — 7 gaps)

- [ ] `POST /api/v1/wallets` field `currency` — missing empty string scenario
- [ ] `POST /api/v1/wallets` field `currency` — no test verifying each valid value (USD, EUR, GBP, BTC, ETH)
- [ ] `POST /api/v1/wallets` field `name` — missing empty string, max length (100), over max (101) scenarios
- [ ] `POST /api/v1/wallets` response — `id` and `created_at` not asserted in happy path
- [ ] `POST /api/v1/wallets` error responses — error body content not verified in any 422 test
- [ ] `GET /api/v1/wallets` — ordering by currency not verified
- [ ] Wallet (DB) — balance default of 0 only tested via response, not directly on DB record

**LOW** (rare corner cases — 1 gap)

- [ ] `POST /api/v1/wallets` field `name` — unicode/special characters handling

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | wallets_spec.rb | MEDIUM | Split into post_wallets_spec.rb, get_wallets_spec.rb; create patch_wallet_spec.rb |
| Missing endpoint test file | PATCH /api/v1/wallets/:id | HIGH | Create spec/requests/api/v1/patch_wallet_spec.rb |
| Status-only assertions (errors) | wallets_spec.rb:44-56 | MEDIUM | Error tests should assert no DB record created and error message content |
| No test foundation | wallets_spec.rb | MEDIUM | Add DEFAULT_CURRENCY, DEFAULT_NAME constants, subject(:run_test) helper |
| Model spec tests internal methods | spec/models/wallet_spec.rb | MEDIUM | Delete — test deposit!/withdraw! behavior through API endpoints or dedicated endpoint tests instead. deposit!/withdraw! are called from TransactionService which is tested through POST /api/v1/transactions. |

### Top 5 Priority Actions

1. **Create test file for PATCH /api/v1/wallets/:id** — The entire update endpoint is untested. Add happy path, not found, IDOR, validation error, and status update scenarios.
2. **Add duplicate currency test for POST** — The unique [user_id, currency] constraint is untested. A regression here would allow corrupt wallet state.
3. **Add authentication (401) tests** — No wallet endpoint tests unauthenticated access. This is a critical security contract.
4. **Add response shape assertions to GET /api/v1/wallets** — Currently only checks status 200. Verify array shape, wallet fields, and ordering.
5. **Add IDOR test for GET /api/v1/wallets** — Verify that the endpoint only returns wallets belonging to the authenticated user.
