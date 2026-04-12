## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets (PATCH /api/v1/wallets/:id has NO tests)
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

### Overall Score: 4.4 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 6/10 | 15% | 0.90 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **4.45** |

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
      - status (string, optional, via wallet_params permit) [MEDIUM confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - name (string) [HIGH confidence]
      - balance (string, decimal as string) [HIGH confidence]
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
      - wallet object (same shape as POST response) [HIGH confidence]
    Status codes: 200, 404, 422, 401

DB Contract:
  Wallet model:
    - id (integer, PK, auto) [HIGH confidence]
    - user_id (integer, NOT NULL, FK to users) [HIGH confidence]
    - currency (string, NOT NULL, inclusion: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, NOT NULL, max 100) [HIGH confidence]
    - balance (decimal(20,8), NOT NULL, default: 0, >= 0) [HIGH confidence]
    - status (string, NOT NULL, default: active, enum: active/suspended/closed) [HIGH confidence]
    - created_at (datetime) [HIGH confidence]
    - updated_at (datetime) [HIGH confidence]
    - UNIQUE constraint: [user_id, currency] [HIGH confidence]
============================
```

**Fintech Dimension Template:**

| # | Dimension | Status | Fields Found | Notes |
|---|-----------|--------|-------------|-------|
| 1 | Money & Precision | Extracted | balance (decimal(20,8)), currency (USD/EUR/GBP/BTC/ETH) | Exact decimal type |
| 2 | Idempotency | Not detected | — | No idempotency key on POST /api/v1/wallets; unique constraint on [user_id, currency] provides partial protection |
| 3 | Transaction State Machine | Extracted | status enum: active/suspended/closed | No explicit transition guards |
| 4 | Balance & Ledger Integrity | Extracted | balance (>= 0 validation), Wallet#deposit!, Wallet#withdraw!, with_lock | Pessimistic locking present |
| 5 | External Payment Integrations | Not applicable | — | No payment gateway code in wallets controller |
| 6 | Regulatory & Compliance | Not detected | — | No KYC/AML fields, no audit trail on wallet operations |
| 7 | Concurrency & Data Integrity | Extracted | with_lock in deposit!/withdraw!, unique constraint on [user_id, currency] | |
| 8 | Security & Access Control | Extracted | before_action :authenticate_user!, current_user.wallets scoping | Ownership enforced via scoping |

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | 2 fields (balance, currency) | 1 HIGH |
| 2 | Idempotency | Not detected — flagged | — | Infrastructure gap |
| 3 | Transaction State Machine | Extracted | 1 field (status enum) | 2 HIGH |
| 4 | Balance & Ledger Integrity | Extracted | 2 fields (balance, with_lock) | 1 MEDIUM |
| 5 | External Payment Integrations | Not applicable | — | — |
| 6 | Regulatory & Compliance | Not detected — flagged | — | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Extracted | 2 fields (with_lock, unique constraint) | 1 MEDIUM |
| 8 | Security & Access Control | Extracted | 2 fields (authenticate_user!, scoping) | 2 HIGH |

**Fintech mode:** Active — all 8 dimensions evaluated.

### Test Structure Tree

```
POST /api/v1/wallets
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value (XYZ) → 422
│   ├── ✗ empty string → 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   └── ✗ duplicate currency for same user → 422 (unique constraint)
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ at max length (100) → 201
│   ├── ✗ over max length (101) → 422
│   └── ✗ empty string → 422
├── field: status (request param — permitted but should it be?)
│   ├── ✗ can user set status on create? (potential mass-assignment issue) [FINTECH]
│   └── ✗ if yes, what values are accepted?
├── response body
│   ├── ✓ happy path asserts currency, name, balance, status
│   └── ✗ missing id and created_at assertions
├── DB assertions
│   ├── ✓ happy path asserts Wallet.count change
│   └── ✗ missing individual field assertions (user_id, balance default)
├── auth — NO TESTS [FINTECH]
│   └── ✗ unauthenticated → 401
└── business: unique currency per user — NO TESTS
    └── ✗ duplicate currency → 422

GET /api/v1/wallets
├── ✓ returns 200
├── response body — NO ASSERTIONS
│   ├── ✗ should assert wallets array shape
│   └── ✗ should assert ordering (by currency)
├── ✗ only returns current user's wallets (IDOR) [FINTECH]
└── ✗ unauthenticated → 401

PATCH /api/v1/wallets/:id — NO TESTS (entire endpoint untested)
├── ✗ happy path (update name) → 200
├── ✗ update status (active → suspended) → 200
├── ✗ invalid status transition [FINTECH]
├── ✗ wallet not found → 404
├── ✗ another user's wallet → 404 (IDOR) [FINTECH]
├── ✗ invalid params → 422
├── ✗ response body shape
└── ✗ unauthenticated → 401
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid (XYZ) | missing: empty string, duplicate per user |
| POST /wallets (request) | name | HIGH | Yes | nil | missing: max length, over max length, empty |
| POST /wallets (request) | status | MEDIUM | No | -- | MEDIUM: mass-assignment check needed |
| POST /wallets (response) | id | HIGH | No | -- | MEDIUM: not asserted |
| POST /wallets (response) | currency | HIGH | Yes | happy path | -- |
| POST /wallets (response) | name | HIGH | Yes | happy path | -- |
| POST /wallets (response) | balance | HIGH | Yes | happy path (0.0) | -- |
| POST /wallets (response) | status | HIGH | Yes | happy path (active) | -- |
| POST /wallets (response) | created_at | HIGH | No | -- | MEDIUM: not asserted |
| POST /wallets (status codes) | 201 | HIGH | Yes | happy path | -- |
| POST /wallets (status codes) | 422 | HIGH | Yes | currency nil/invalid, name nil | -- |
| POST /wallets (status codes) | 401 | HIGH | No | -- | HIGH: untested |
| Wallet (DB) | user_id | HIGH | No | -- | MEDIUM: not asserted in happy path |
| Wallet (DB) | currency | HIGH | Yes | happy path | -- |
| Wallet (DB) | name | HIGH | Yes | happy path | -- |
| Wallet (DB) | balance | HIGH | Yes | default 0.0 | -- |
| Wallet (DB) | status | HIGH | Yes | default active | missing: suspended, closed scenarios |
| Wallet (DB) | status enum: active | HIGH | Yes | happy path | -- |
| Wallet (DB) | status enum: suspended | HIGH | No | -- | HIGH: untested via API |
| Wallet (DB) | status enum: closed | HIGH | No | -- | HIGH: untested via API |
| Wallet (DB) | unique [user_id, currency] | HIGH | No | -- | HIGH: untested |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: response shape not verified |
| GET /wallets (status codes) | 401 | HIGH | No | -- | HIGH: untested |
| PATCH /wallets/:id (all) | -- | HIGH | No | -- | HIGH: entire endpoint untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint has zero tests

  Suggested test:
  ```ruby
  describe 'PATCH /api/v1/wallets/:id' do
    let(:wallet) { create(:wallet, user: user, currency: 'USD', name: 'Old Name') }
    let(:params) { { wallet: { name: 'New Name' } } }

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet.id}", params: params, headers: headers
    end

    context 'with valid params' do
      it 'returns 200 with updated wallet' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['wallet']['name']).to eq('New Name')
        expect(wallet.reload.name).to eq('New Name')
      end
    end

    context 'when wallet not found' do
      it 'returns 404' do
        patch '/api/v1/wallets/999999', params: params, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when wallet belongs to another user' do
      let(:other_user) { create(:user) }
      let(:other_wallet) { create(:wallet, user: other_user) }

      it 'returns 404' do
        patch "/api/v1/wallets/#{other_wallet.id}", params: params, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when not authenticated' do
      it 'returns 401' do
        patch "/api/v1/wallets/#{wallet.id}", params: params
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` duplicate currency per user — unique constraint untested

  Suggested test:
  ```ruby
  context 'when user already has a wallet with the same currency' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422' do
      post '/api/v1/wallets', params: params, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

- [ ] `POST /api/v1/wallets` authentication — no test for unauthenticated access [FINTECH]

  Suggested test:
  ```ruby
  context 'when not authenticated' do
    it 'returns 401' do
      post '/api/v1/wallets', params: params
      expect(response).to have_http_status(:unauthorized)
    end
  end
  ```

- [ ] `GET /api/v1/wallets` only returns current user's wallets — IDOR [FINTECH]

  Suggested test:
  ```ruby
  it 'does not return other users wallets' do
    create(:wallet, user: user, currency: 'USD')
    other_user = create(:user)
    create(:wallet, user: other_user, currency: 'EUR')

    get '/api/v1/wallets', headers: headers
    body = JSON.parse(response.body)
    expect(body['wallets'].size).to eq(1)
    expect(body['wallets'].first['currency']).to eq('USD')
  end
  ```

- [ ] `GET /api/v1/wallets` response body — no assertion on response shape or ordering

- [ ] Wallet status enum: suspended and closed — not tested via API endpoints [FINTECH]

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/wallets` request field `name` — missing max length (100) and over max length (101) boundary
- [ ] `POST /api/v1/wallets` request field `currency` — missing empty string edge case
- [ ] `POST /api/v1/wallets` response fields `id` and `created_at` — not asserted in happy path
- [ ] `POST /api/v1/wallets` request field `status` — permitted in wallet_params, potential mass-assignment issue (user could set status to 'suspended' on create) [FINTECH]
- [ ] Balance validation — no API test verifies balance >= 0 constraint [FINTECH]

**LOW** (rare corner cases)

- [ ] `POST /api/v1/wallets` name with only whitespace
- [ ] `GET /api/v1/wallets` empty result (no wallets)

#### Missing infrastructure [FINTECH]

- [ ] **MEDIUM: No explicit state machine or transition guards for wallet status** — Wallet model defines `enum :status, { active, suspended, closed }` but has no transition guards. The PATCH endpoint permits status changes without validating transitions (e.g., `closed → active` could be allowed).
- [ ] **MEDIUM: No audit trail for wallet operations** — No audit trail detected for wallet creation, status changes, or balance modifications. Financial wallet operations should be auditable.
- [ ] **MEDIUM: No KYC/AML fields or compliance validations** — No KYC/AML fields on User model, no compliance checks on wallet creation. Financial operations may lack regulatory safeguards.

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one test file | wallets_spec.rb | MEDIUM | Split into post_wallets_spec.rb, get_wallets_spec.rb, patch_wallet_spec.rb |
| Status-only assertions (error paths) | wallets_spec.rb:44,53,63 | MEDIUM | Assert no DB changes and error message in error scenarios |
| Missing entire endpoint test | PATCH /api/v1/wallets/:id | HIGH | Create patch_wallet_spec.rb |
| Mass-assignment risk | wallet_params permits :status | MEDIUM | Verify if status should be user-settable on create |

### Top 5 Priority Actions

1. **Create tests for PATCH /api/v1/wallets/:id** — Entire endpoint has zero test coverage. Add happy path, not-found, IDOR (another user's wallet), invalid params, and authentication tests.
2. **Add duplicate currency test for POST /wallets** — The unique constraint on [user_id, currency] is a critical business rule with no test. A regression could allow users to create duplicate wallets.
3. **Add IDOR tests for GET /wallets and PATCH /wallets** — No test verifies that users can only see/modify their own wallets. This is a critical security gap.
4. **Add authentication tests for all endpoints** — No test verifies that unauthenticated requests are rejected with 401.
5. **Add wallet status transition tests via PATCH** — The status field (active/suspended/closed) is changeable via PATCH but no test verifies valid/invalid transitions or side effects.
