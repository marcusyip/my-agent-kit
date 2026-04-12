## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets, PATCH /api/v1/wallets/:id (MISSING)
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb
**Framework:** Rails 7.1 / RSpec (request spec)
**Fintech mode:** Enabled (balance field, wallet status state machine, currency constraints)

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

### Overall Score: 3.8 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 3/10 | 25% | 0.75 |
| Test Grouping | 3/10 | 15% | 0.45 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 4/10 | 15% | 0.60 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **3.75** |

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/wallets_controller.rb
        app/models/wallet.rb
        db/migrate/002_create_wallets.rb
Framework: Rails 7.1 / RSpec

API Contract — POST /api/v1/wallets (inbound):
  Request params:
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
    - name (string, required, max length: 100) [HIGH confidence]
    - status (string, optional — permitted in wallet_params!) [HIGH confidence]
  Response fields (6 fields):
    - id (integer) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - name (string) [HIGH confidence]
    - balance (string, decimal as string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - created_at (string, ISO8601) [HIGH confidence]
  Error response shape:
    - error (string, full_messages joined) [HIGH confidence]
  Status codes: 201, 422, 401

API Contract — GET /api/v1/wallets (inbound):
  Response fields:
    - wallets (array of wallet objects, 6 fields each) [HIGH confidence]
  Status codes: 200, 401
  Business rules:
    - Scoped to current_user.wallets [HIGH confidence]
    - Ordered by currency [HIGH confidence]

API Contract — PATCH /api/v1/wallets/:id (inbound):
  Request params:
    - currency (string, optional) [HIGH confidence]
    - name (string, optional) [HIGH confidence]
    - status (string, optional) [HIGH confidence]
  Response fields: same 6 wallet fields [HIGH confidence]
  Status codes: 200, 404, 422, 401
  Business rules:
    - Scoped to current_user.wallets (IDOR protection) [HIGH confidence]

DB Contract — Wallet model:
  Fields:
    - user_id (integer, NOT NULL, FK → users) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - name (string, NOT NULL) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default: 0) [HIGH confidence]
    - status (string, NOT NULL, default: 'active') [HIGH confidence]
  Enum values:
    - status: active, suspended, closed [HIGH confidence]
  Unique constraints:
    - [user_id, currency] unique index [HIGH confidence]
  Methods (contract boundary for internal callers):
    - deposit!(amount) — increases balance with lock [HIGH confidence]
    - withdraw!(amount) — decreases balance with lock, checks sufficient balance [HIGH confidence]

Fintech Dimensions:
  Money & Precision:
    - balance uses decimal(20,8) — exact type, good [HIGH confidence]
    - balance constrained >= 0 at model level [HIGH confidence]
  Balance & Ledger:
    - deposit!/withdraw! use with_lock (pessimistic locking) [HIGH confidence]
    - withdraw! checks balance >= amount before debit [HIGH confidence]
  Concurrency:
    - with_lock on deposit!/withdraw! [HIGH confidence]
    - No concurrent access tests exist [HIGH confidence — absence confirmed]
  Security:
    - before_action :authenticate_user! on all actions [HIGH confidence]
    - Wallets scoped to current_user [HIGH confidence]
    - Status field permitted in params — user could set status to 'suspended' on create [HIGH confidence]
    - No rate limiting detected [HIGH confidence — absence confirmed]

Total contract fields extracted: 38
============================
```

---

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ Wallet.count increased by 1
│   ├── ✓ response body: currency = 'USD'
│   ├── ✓ response body: name = 'My USD Wallet'
│   ├── ✓ response body: balance = '0.0'
│   ├── ✓ response body: status = 'active'
│   ├── ✗ response body: id (not asserted)
│   ├── ✗ response body: created_at (not asserted)
│   └── ✗ DB: verify user_id, currency, name, balance, status persisted correctly
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid ('XYZ') → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → 201
│   ├── ✗ duplicate currency for same user → 422 (unique constraint)
│   ├── ✗ same currency for different user → 201 (should succeed)
│   ├── ✗ no DB write assertion on nil case
│   └── ✗ no DB write assertion on invalid case
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100 chars) → 201
│   ├── ✗ over max length (101 chars) → 422
│   └── ✗ no DB write assertion on nil case
├── field: status (request param) — NO TESTS
│   ├── ✗ [SECURITY] status param is permitted! User could set 'suspended' on create
│   ├── ✗ setting status to 'active' on create → should succeed
│   ├── ✗ setting status to 'suspended' on create → should this be allowed?
│   └── ✗ setting status to 'closed' on create → should this be allowed?
├── [FINTECH] security — NO TESTS
│   ├── ✗ missing auth token → 401
│   └── ✗ error response shape verification
└── error path assertions
    └── ✗ no error tests assert DB unchanged or error message content

GET /api/v1/wallets
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response body: wallets array shape (6 fields per wallet)
│   └── ✗ ordering: by currency
├── business: only current_user's wallets — NO TESTS
│   └── ✗ does not return other users' wallets
├── empty state — NO TESTS
│   └── ✗ no wallets → empty array
└── [FINTECH] security — NO TESTS
    └── ✗ missing auth token → 401

PATCH /api/v1/wallets/:id — NO TEST FILE (entire endpoint untested)
├── happy path — NO TESTS
│   ├── ✗ update name → 200, response shows new name, DB updated
│   ├── ✗ update currency → 200 or 422 (depends on business rules)
│   └── ✗ update status → 200, response shows new status
├── field: id (path param) — NO TESTS
│   ├── ✗ not found → 404
│   └── ✗ another user's wallet → 404 (IDOR)
├── field: name — NO TESTS
│   ├── ✗ valid name → 200
│   ├── ✗ nil → 422 or no-op
│   ├── ✗ empty string → 422
│   └── ✗ over max length (101) → 422
├── field: currency — NO TESTS
│   ├── ✗ valid change → 200 or 422
│   ├── ✗ duplicate currency for user → 422
│   └── ✗ invalid currency → 422
├── field: status — NO TESTS
│   ├── ✗ active → suspended → 200
│   ├── ✗ suspended → active → 200
│   ├── ✗ invalid status value → 422
│   └── ✗ [FINTECH] state machine transitions: which are valid?
├── validation failure — NO TESTS
│   └── ✗ invalid params → 422 with error message
└── [FINTECH] security — NO TESTS
    ├── ✗ missing auth token → 401
    └── ✗ IDOR: update another user's wallet → 404

Wallet#deposit! (used by internal callers — tested in model spec)
├── ✓ positive amount → increases balance (model spec)
├── ✓ negative amount → raises ArgumentError (model spec)
├── ✓ zero amount → raises ArgumentError (model spec)
├── ✓ suspended wallet → raises error (model spec)
├── ✗ closed wallet → raises error
└── ✗ [FINTECH] concurrent deposits — with_lock not verified

Wallet#withdraw! (used by internal callers — tested in model spec)
├── ✓ positive amount → decreases balance (model spec)
├── ✓ negative amount → raises ArgumentError (model spec)
├── ✓ insufficient balance → raises error (model spec)
├── ✗ exact balance (boundary) → should succeed with balance = 0
├── ✗ zero amount → should raise ArgumentError
├── ✗ suspended wallet → raises error
├── ✗ closed wallet → raises error
└── ✗ [FINTECH] concurrent withdrawals — with_lock not verified
```

---

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | empty string, duplicate per user, each valid value |
| POST /wallets (request) | name | HIGH | Yes | nil | empty string, max length, over max |
| POST /wallets (request) | status | HIGH | No | -- | HIGH: permitted but untested — security concern |
| POST /wallets (response) | currency | HIGH | Yes (happy) | matches input | -- |
| POST /wallets (response) | name | HIGH | Yes (happy) | matches input | -- |
| POST /wallets (response) | balance | HIGH | Yes (happy) | '0.0' | -- |
| POST /wallets (response) | status | HIGH | Yes (happy) | 'active' | -- |
| POST /wallets (response) | id | HIGH | No | -- | MEDIUM: not asserted in happy path |
| POST /wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: no body assertions |
| GET /wallets (business) | scoped to user | HIGH | No | -- | HIGH: no isolation test |
| PATCH /wallets/:id (all) | entire endpoint | HIGH | No | -- | HIGH: zero coverage |
| Wallet DB | status enum | HIGH | No | -- | HIGH: closed state untested everywhere |
| [FINTECH] balance | concurrent ops | HIGH | No | -- | HIGH: with_lock not verified |
| [FINTECH] security | auth (all) | HIGH | No | -- | HIGH: no auth tests |
| [FINTECH] security | IDOR (PATCH) | HIGH | No | -- | HIGH: no IDOR tests |

---

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 14 gaps)

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint has zero test coverage

  Suggested test (new file `spec/requests/api/v1/patch_wallet_spec.rb`):
  ```ruby
  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    DEFAULT_NAME = 'My USD Wallet'
    DEFAULT_CURRENCY = 'USD'

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet_id}", params: { wallet: params }, headers: headers
    end

    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let!(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
    let(:wallet_id) { wallet.id }
    let(:params) { { name: new_name } }
    let(:new_name) { 'Updated Wallet Name' }

    context 'happy path' do
      it 'returns 200 with updated wallet' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['wallet']['name']).to eq('Updated Wallet Name')
        expect(body['wallet']['id']).to eq(wallet.id)
        expect(body['wallet']['currency']).to eq(DEFAULT_CURRENCY)
        expect(body['wallet']['status']).to eq('active')
        expect(body['wallet']['balance']).to eq(wallet.balance.to_s)
      end

      it 'persists change in DB' do
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

    context 'when name is empty' do
      let(:new_name) { '' }

      it 'returns 422' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
        expect(wallet.reload.name).to eq(DEFAULT_NAME)
      end
    end

    context 'when name exceeds max length' do
      let(:new_name) { 'a' * 101 }

      it 'returns 422' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when updating status' do
      let(:params) { { status: 'suspended' } }

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

- [ ] `POST /api/v1/wallets` request field `status` — permitted in params but untested. **Security concern:** user could set `status: 'suspended'` on create, bypassing the default 'active' state.

  Suggested test:
  ```ruby
  context 'when status is set in params' do
    let(:params) do
      { wallet: { currency: currency, name: name, status: 'suspended' } }
    end

    it 'ignores the status param or rejects it' do
      post '/api/v1/wallets', params: params, headers: headers
      # If status should NOT be settable on create, expect either:
      # - 422 (rejected), or
      # - 201 but status is 'active' (ignored)
      if response.status == 201
        expect(JSON.parse(response.body)['wallet']['status']).to eq('active')
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` field `currency` — duplicate per user must return 422 (unique constraint)

  Suggested test:
  ```ruby
  context 'when user already has a wallet with this currency' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422 and does not create a duplicate' do
      expect { post '/api/v1/wallets', params: params, headers: headers }
        .not_to change(Wallet, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to include('currency')
    end
  end
  ```

- [ ] `GET /api/v1/wallets` — no response body assertions, no user isolation test

  Suggested test:
  ```ruby
  it 'returns wallets with correct shape ordered by currency' do
    btc = create(:wallet, user: user, currency: 'BTC', name: 'BTC Wallet')
    usd = create(:wallet, user: user, currency: 'USD', name: 'USD Wallet')
    get '/api/v1/wallets', headers: headers
    body = JSON.parse(response.body)
    currencies = body['wallets'].map { |w| w['currency'] }
    expect(currencies).to eq(%w[BTC USD])
    wallet_obj = body['wallets'].first
    expect(wallet_obj.keys).to match_array(%w[id currency name balance status created_at])
  end

  it 'does not return other users wallets' do
    other_user = create(:user)
    create(:wallet, user: other_user)
    create(:wallet, user: user)
    get '/api/v1/wallets', headers: headers
    body = JSON.parse(response.body)
    expect(body['wallets'].length).to eq(1)
  end
  ```

- [ ] `[FINTECH]` All 3 endpoints — no authentication tests (missing/expired token → 401)

  Suggested test:
  ```ruby
  context 'without authentication' do
    it 'returns 401' do
      post '/api/v1/wallets', params: params
      expect(response).to have_http_status(:unauthorized)
    end
  end
  ```

- [ ] `[FINTECH]` IDOR — PATCH endpoint accepts resource ID but has no test verifying another user cannot update

- [ ] `[FINTECH]` Concurrency — `Wallet#deposit!` and `Wallet#withdraw!` use `with_lock` but no test verifies the lock prevents concurrent corruption

- [ ] `[FINTECH]` Balance — `Wallet#withdraw!` exact balance boundary (withdraw exactly the full balance → balance should be 0)

**MEDIUM** (tested but missing scenarios — 7 gaps)

- [ ] `POST /api/v1/wallets` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/wallets` field `name` — missing empty string, max length (100), over max length (101)
- [ ] `POST /api/v1/wallets` response — `id` and `created_at` not asserted in happy path
- [ ] `POST /api/v1/wallets` error paths — none assert DB unchanged or error message content
- [ ] `GET /api/v1/wallets` — no empty state test (no wallets → empty array)
- [ ] Wallet status enum `closed` — untested in both model spec and request spec
- [ ] `Wallet#withdraw!` — zero amount not tested (should raise ArgumentError like deposit!)

**LOW** (rare corner cases — 2 gaps)

- [ ] `POST /api/v1/wallets` — same currency for different users should succeed (validates uniqueness scoped to user)
- [ ] `Wallet#deposit!`/`Wallet#withdraw!` — very large amounts near decimal(20,8) max

### Missing Infrastructure [FINTECH]

- [ ] **No rate limiting** detected on any wallet endpoint — MEDIUM. Financial mutation endpoints should be rate-limited.
- [ ] **No audit trail** for wallet status changes — MEDIUM. Status transitions (active → suspended) should be auditable.
- [ ] **Status field permitted on create** — HIGH. `wallet_params` permits `:status`, allowing users to create wallets in non-active states. This may be a security/design bug — consider removing `:status` from create params or adding authorization.

---

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `wallets_spec.rb` (POST + GET index) | HIGH | Split into `post_wallets_spec.rb`, `get_wallets_spec.rb` |
| Missing entire endpoint | PATCH /api/v1/wallets/:id | HIGH | Create `patch_wallet_spec.rb` |
| Status-only error assertions | `wallets_spec.rb:41-65` | MEDIUM | Add DB unchanged + error message assertions |
| No test foundation | `wallets_spec.rb` — no `subject(:run_test)`, no DEFAULT constants | MEDIUM | Add test foundation pattern |
| Status param permitted on create | `wallets_controller.rb:43` | HIGH | Remove `:status` from create params or add authorization check |

---

### Top 5 Priority Actions

1. **Create `patch_wallet_spec.rb`** — entire PATCH endpoint has zero coverage. Any change to the update action would go undetected.
2. **Add duplicate currency test for POST** — unique constraint exists but is untested; a migration removing the index would silently break data integrity.
3. **Add status param security test for POST** — `status` is permitted in params, so a user could create a suspended wallet. Test and potentially fix the controller to reject or ignore status on create.
4. **Add IDOR test for PATCH** — scoped to `current_user.wallets` but no test verifies another user cannot update.
5. **Add response body and ordering assertions to GET index** — current test only checks status code; response shape changes would go undetected.
