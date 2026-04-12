## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets (PATCH /api/v1/wallets/:id — **NO TESTS**)
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb, db/migrate/002_create_wallets.rb
**Framework:** Rails 7.1 / RSpec (request spec)
**Mode:** Fintech mode enabled (balance fields, currency, wallet status)

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

### Overall Score: 4.6 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 5/10 | 15% | 0.75 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 5/10 | 15% | 0.75 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 4/10 | 10% | 0.40 |
| **Overall** | | | **4.55** |

### Verdict: NEEDS IMPROVEMENT

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
    - currency (string, required, inclusion: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
    - name (string, required, max length 100) [HIGH confidence]
    - status (string, optional, enum: active/suspended/closed) [HIGH confidence — permitted but risky]
  Response fields:
    - id (integer) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - name (string) [HIGH confidence]
    - balance (string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - created_at (string/iso8601) [HIGH confidence]
  Status codes: 201, 422, 401

API Contract — GET /api/v1/wallets (inbound):
  Request params: none
  Response fields:
    - wallets (array of serialized wallets) [HIGH confidence]
  Ordering: by currency [HIGH confidence]
  Status codes: 200, 401

API Contract — PATCH /api/v1/wallets/:id (inbound):
  Request params:
    - currency (string, optional) [HIGH confidence]
    - name (string, optional) [HIGH confidence]
    - status (string, optional) [HIGH confidence]
  Response fields: same 6 fields as POST response [HIGH confidence]
  Status codes: 200, 404, 422, 401

DB Data Contract — Wallet model:
  Fields:
    - user_id (integer, NOT NULL, FK → users) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - name (string, NOT NULL) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default 0) [HIGH confidence]
    - status (string, NOT NULL, default 'active') [HIGH confidence]
  Data states:
    - status enum: active, suspended, closed [HIGH confidence]
  Constraints:
    - UNIQUE(user_id, currency) [HIGH confidence]
    - balance >= 0 [HIGH confidence]

[FINTECH] Balance & Ledger:
  - balance field: decimal(20,8) — exact type, good [HIGH confidence]
  - deposit!/withdraw! use with_lock (pessimistic locking) [HIGH confidence]
  - balance >= 0 validated at model level [HIGH confidence]

[FINTECH] Security:
  - wallet_params permits :status — client can set wallet status on create [HIGH confidence — potential issue]

Total contract fields extracted: 30+
============================
```

### Test Structure Tree

```
POST /api/v1/wallets (spec/requests/api/v1/wallets_spec.rb:13)
├── happy path
│   ├── ✓ returns 201 status
│   ├── ✓ response body: currency
│   ├── ✓ response body: name
│   ├── ✓ response body: balance (= '0.0')
│   ├── ✓ response body: status (= 'active')
│   ├── ✗ response body: id
│   ├── ✗ response body: created_at
│   ├── ✓ DB: Wallet count increases by 1
│   ├── ✗ DB: Wallet persisted with correct user_id
│   ├── ✗ DB: Wallet persisted with correct currency
│   └── ✗ DB: Wallet persisted with correct name
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value (XYZ) → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ duplicate currency for same user → 422 [FINTECH]
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ at max length (100) → succeeds
│   └── ✗ over max length (101) → 422
├── field: status (request param) — NO TESTS
│   ├── ✗ [FINTECH] client can set status to 'suspended' on create — should be blocked?
│   ├── ✗ [FINTECH] client can set status to 'closed' on create — should be blocked?
│   └── ✗ invalid value → 422
├── [FINTECH] security / access control
│   ├── ✗ unauthenticated request → 401
│   └── ✗ status param accepted on create (mass assignment risk)
├── error path side effects — PARTIALLY ASSERTED
│   ├── ✗ on 422: error paths don't assert no Wallet created
│   └── ✗ on 422: error response body not asserted
└── [FINTECH] balance initialization
    └── ✗ default balance = 0 persisted in DB (only checked in response)

GET /api/v1/wallets (spec/requests/api/v1/wallets_spec.rb:71)
├── happy path
│   ├── ✓ returns 200 status
│   ├── ✗ response body: wallets array shape
│   ├── ✗ response body: each wallet has correct fields
│   └── ✗ ordering by currency verified
├── [FINTECH] security / access control
│   ├── ✗ unauthenticated request → 401
│   └── ✗ only returns current user's wallets
└── edge cases — NO TESTS
    └── ✗ no wallets → empty array

PATCH /api/v1/wallets/:id — NO TEST FILE [CRITICAL]
├── happy path — NO TESTS
│   ├── ✗ update name → 200, response shows new name
│   ├── ✗ update currency → 200 or 422 (depending on rules)
│   ├── ✗ update status → 200, response shows new status
│   ├── ✗ DB: fields persisted correctly
│   └── ✗ response body: all 6 fields
├── field: id (request param) — NO TESTS
│   ├── ✗ not found → 404
│   ├── ✗ another user's wallet → 404 (IDOR) [FINTECH]
│   └── ✗ non-integer → error
├── field: name — NO TESTS
│   ├── ✗ valid name → updated
│   ├── ✗ nil → validation error or unchanged
│   ├── ✗ too long (> 100) → 422
│   └── ✗ empty string → 422
├── field: currency — NO TESTS
│   ├── ✗ valid currency → updated
│   ├── ✗ invalid currency → 422
│   └── ✗ duplicate currency for user → 422
├── field: status — NO TESTS [FINTECH]
│   ├── ✗ active → suspended → succeeds
│   ├── ✗ suspended → active → succeeds
│   ├── ✗ active → closed → succeeds
│   ├── ✗ closed → active → depends on rules
│   └── ✗ invalid status value → 422
├── [FINTECH] security / access control
│   ├── ✗ unauthenticated → 401
│   ├── ✗ another user's wallet → 404 (IDOR)
│   └── ✗ [FINTECH] status change should require elevated permissions?
└── [FINTECH] wallet with balance
    └── ✗ closing wallet with non-zero balance → should it be blocked?
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | empty, duplicate, each valid |
| POST /wallets (request) | name | HIGH | Yes | nil | empty, max length, over max |
| POST /wallets (request) | status | HIGH | No | -- | HIGH: entirely untested [FINTECH] |
| POST /wallets (response) | currency | HIGH | Yes | happy path | -- |
| POST /wallets (response) | name | HIGH | Yes | happy path | -- |
| POST /wallets (response) | balance | HIGH | Yes | happy path (= '0.0') | -- |
| POST /wallets (response) | status | HIGH | Yes | happy path (= 'active') | -- |
| POST /wallets (response) | id | HIGH | No | -- | MEDIUM: not asserted |
| POST /wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted |
| POST /wallets (DB) | count | HIGH | Yes | happy path | field values not checked |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: shape untested |
| GET /wallets (response) | ordering | HIGH | No | -- | MEDIUM: not verified |
| PATCH /wallets/:id | ALL | HIGH | No | -- | **CRITICAL: no test file** |
| [FINTECH] Wallet | status transitions | HIGH | No | -- | HIGH: no state tests |
| [FINTECH] POST /wallets | duplicate currency | HIGH | No | -- | HIGH: unique constraint untested |
| [FINTECH] all endpoints | auth/IDOR | HIGH | No | -- | HIGH: no auth/IDOR tests |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests — 12 gaps)

- [ ] `PATCH /api/v1/wallets/:id` — **entire endpoint untested** (all fields, all scenarios)

  Suggested test (new file `spec/requests/api/v1/patch_wallet_spec.rb`):
  ```ruby
  # Generated tests follow your project's patterns. Review before committing.
  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    DEFAULT_NAME = 'Updated Wallet'

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet_id}", params: { wallet: update_params }, headers: headers
    end

    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let(:wallet) { create(:wallet, user: user, currency: 'USD', name: 'Original') }
    let(:wallet_id) { wallet.id }
    let(:update_params) { { name: name } }
    let(:name) { DEFAULT_NAME }

    context 'happy path' do
      it 'returns 200 with updated wallet' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)['wallet']
        expect(body['name']).to eq(DEFAULT_NAME)
        expect(body['currency']).to eq('USD')
        expect(body['id']).to eq(wallet.id)
        expect(body).to have_key('balance')
        expect(body).to have_key('status')
        expect(body).to have_key('created_at')
      end

      it 'persists the update in DB' do
        run_test
        expect(wallet.reload.name).to eq(DEFAULT_NAME)
      end
    end

    context 'when wallet not found' do
      let(:wallet_id) { 999_999 }

      it 'returns 404' do
        run_test
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when wallet belongs to another user [FINTECH IDOR]' do
      let(:other_user) { create(:user) }
      let(:other_wallet) { create(:wallet, user: other_user) }
      let(:wallet_id) { other_wallet.id }

      it 'returns 404' do
        run_test
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when name is too long' do
      let(:name) { 'a' * 101 }

      it 'returns 422' do
        run_test
        expect(response).to have_http_status(:unprocessable_entity)
        expect(wallet.reload.name).to eq('Original')
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` duplicate currency per user — unique constraint untested [FINTECH]

  Suggested test:
  ```ruby
  context 'when user already has a wallet with this currency [FINTECH]' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422 and does not create a duplicate' do
      expect {
        post '/api/v1/wallets', params: params, headers: headers
      }.not_to change(Wallet, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/wallets` field `status` — client can set status on create via permitted params [FINTECH]

  Suggested test:
  ```ruby
  context 'field: status on create [FINTECH]' do
    let(:params) { { wallet: { currency: currency, name: name, status: 'suspended' } } }

    it 'ignores client-provided status or rejects it' do
      post '/api/v1/wallets', params: params, headers: headers
      # If the app allows this, the test documents that behavior.
      # If it should NOT allow it, this test will catch the gap.
      if response.status == 201
        body = JSON.parse(response.body)['wallet']
        expect(body['status']).to eq('active') # should ignore client status
      else
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
  ```

- [ ] `GET /api/v1/wallets` response shape — wallets array fields not verified
- [ ] `GET /api/v1/wallets` — does not verify only current user's wallets returned [FINTECH]
- [ ] [FINTECH] Authentication — no test for unauthenticated requests on any endpoint
- [ ] [FINTECH] Wallet status transitions — no tests via PATCH endpoint
- [ ] `POST /api/v1/wallets` error paths don't assert no Wallet created or error body content

**MEDIUM** (tested but missing scenarios — 6 gaps)

- [ ] `POST /api/v1/wallets` field `currency`: missing empty string edge case
- [ ] `POST /api/v1/wallets` field `currency`: each valid value not individually verified
- [ ] `POST /api/v1/wallets` field `name`: missing max length (100) and over max (101) boundary tests
- [ ] `POST /api/v1/wallets` field `name`: missing empty string edge case
- [ ] `POST /api/v1/wallets` response: `id` and `created_at` not asserted in happy path
- [ ] `GET /api/v1/wallets`: ordering by currency not verified

**LOW** (rare corner cases — 2 gaps)

- [ ] `GET /api/v1/wallets`: empty state (no wallets) → returns empty array
- [ ] [FINTECH] Closing wallet with non-zero balance behavior undefined

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | wallets_spec.rb (POST + GET, missing PATCH) | MEDIUM | Split into post_wallets_spec.rb, get_wallets_spec.rb, patch_wallet_spec.rb |
| Missing entire endpoint test | PATCH /api/v1/wallets/:id | CRITICAL | Create patch_wallet_spec.rb |
| Status-only assertions on errors | wallets_spec.rb:44, :54, :63 | MEDIUM | Assert error body and no DB record created |
| No test foundation pattern | wallets_spec.rb:13 | MEDIUM | Add DEFAULT constants, subject(:run_test) |
| [FINTECH] Status permitted on create | wallets_controller.rb:44 | HIGH | Either remove :status from wallet_params or add test documenting behavior |

### Top 5 Priority Actions

1. **Create test file for PATCH /api/v1/wallets/:id** — entire endpoint is untested. This is the most critical gap: name, status, and currency can be updated with zero test coverage. IDOR is also untested
2. **Add duplicate currency test for POST** [FINTECH] — the unique constraint on (user_id, currency) has no test. A migration removing this constraint would pass all tests silently
3. **Add status field tests for POST** [FINTECH] — `wallet_params` permits `:status`, meaning clients can create suspended/closed wallets. This needs either a test documenting the behavior or a code fix to remove the permission
4. **Add response body assertions to GET /api/v1/wallets** — currently only checks status 200, not the shape or content of the wallets array
5. **Add IDOR tests across all endpoints** [FINTECH] — no test verifies that users cannot access other users' wallets
