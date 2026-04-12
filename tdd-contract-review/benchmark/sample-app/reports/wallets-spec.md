## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** spec/requests/api/v1/wallets_spec.rb
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets
**Source files:** app/controllers/api/v1/wallets_controller.rb, app/models/wallet.rb
**Framework:** Rails / RSpec (request spec)

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
Framework: Rails / RSpec

API Contract -- POST /api/v1/wallets:
  Request params (from wallet_params):
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
    - name (string, required, max 100 chars) [HIGH confidence]
    - status (string, permitted in params but typically set by system) [MEDIUM confidence]
  Response fields (serialize_wallet):
    - id (integer) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - name (string) [HIGH confidence]
    - balance (string, decimal as string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - created_at (string, iso8601) [HIGH confidence]
  Status codes: 201, 422, 401

API Contract -- GET /api/v1/wallets:
  Response fields:
    - wallets (array of serialize_wallet objects) [HIGH confidence]
  Ordering: by currency [HIGH confidence]
  Status codes: 200, 401
  Business rules:
    - Only returns current_user's wallets [HIGH confidence]

API Contract -- PATCH /api/v1/wallets/:id:
  Request params (from wallet_params):
    - currency (string, optional) [HIGH confidence]
    - name (string, optional) [HIGH confidence]
    - status (string, optional) [HIGH confidence]
  Response fields: same as serialize_wallet (6 fields) [HIGH confidence]
  Status codes: 200, 404, 422, 401
  Business rules:
    - Only updates current_user's wallets (scoped find) [HIGH confidence]

DB Contract -- Wallet model:
  - user_id (integer, NOT NULL, FK) [HIGH confidence]
  - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
  - name (string, NOT NULL, max 100) [HIGH confidence]
  - balance (decimal(20,8), NOT NULL, default: 0, >= 0) [HIGH confidence]
  - status (string, NOT NULL, default: 'active', enum: active/suspended/closed) [HIGH confidence]
============================
```

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ response body: currency
│   ├── ✓ response body: name
│   ├── ✓ response body: balance ('0.0')
│   ├── ✓ response body: status ('active')
│   ├── ✓ DB: Wallet.count increases by 1
│   ├── ✗ response body: id
│   └── ✗ response body: created_at
├── field: currency (request param, required, in: USD/EUR/GBP/BTC/ETH, unique per user)
│   ├── ✓ nil -> 422
│   ├── ✓ invalid value -> 422
│   ├── ✗ empty string -> 422
│   ├── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
│   ├── ✗ duplicate currency for same user -> 422
│   └── ✗ error paths: no DB write assertions
├── field: name (request param, required, max 100)
│   ├── ✓ nil -> 422
│   ├── ✗ empty string -> 422
│   ├── ✗ at max length (100 chars) -> 201
│   ├── ✗ over max length (101 chars) -> 422
│   └── ✗ error paths: no DB write assertions
├── field: status -- NO TESTS
│   ├── ✗ default value on creation is 'active'
│   └── ✗ status param permitted but behavior untested
└── field: balance -- NO TESTS
    └── ✗ default balance is 0 on creation

GET /api/v1/wallets
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response body: wallets array with all 6 fields per wallet
│   └── ✗ ordering by currency
├── edge cases -- NO TESTS
│   └── ✗ no wallets -> empty array
└── business: scoping -- NO TESTS
    └── ✗ only returns current user's wallets

PATCH /api/v1/wallets/:id -- NO TESTS AT ALL
├── happy path
│   ├── ✗ returns 200 with updated wallet
│   ├── ✗ response body: all 6 fields
│   └── ✗ DB: wallet updated with correct values
├── field: id (path param)
│   ├── ✗ not found -> 404
│   └── ✗ belongs to another user -> 404
├── field: currency
│   ├── ✗ valid change -> 200
│   ├── ✗ invalid value -> 422
│   └── ✗ duplicate for same user -> 422
├── field: name
│   ├── ✗ valid change -> 200
│   ├── ✗ nil -> 422
│   └── ✗ over max length (101) -> 422
└── field: status
    ├── ✗ change to suspended -> 200
    ├── ✗ change to closed -> 200
    └── ✗ invalid value -> 422
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid value, duplicate per user |
| POST /wallets (request) | name | HIGH | Yes | nil | empty string, max length, over max |
| POST /wallets (request) | status | MEDIUM | No | -- | MEDIUM: untested |
| POST /wallets (response) | 6 fields | HIGH | Partial | currency, name, balance, status | missing: id, created_at |
| POST /wallets (DB) | balance default | HIGH | No | -- | MEDIUM: default 0 not explicitly tested |
| GET /wallets (response) | wallets array | HIGH | No | -- | MEDIUM: no shape assertion |
| GET /wallets (business) | ordering | HIGH | No | -- | MEDIUM: ordering untested |
| GET /wallets (business) | user scoping | HIGH | No | -- | MEDIUM: scoping untested |
| PATCH /wallets/:id | all fields | HIGH | No | -- | HIGH: entire endpoint untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` -- entire endpoint has zero test coverage

  Suggested test (new file: `spec/requests/api/v1/patch_wallet_spec.rb`):
  ```ruby
  # frozen_string_literal: true

  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    DEFAULT_NAME = 'My BTC Wallet'
    DEFAULT_CURRENCY = 'BTC'

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet_id}", params: { wallet: update_params }, headers: headers
    end

    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let!(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
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
        expect(body['wallet']['currency']).to eq(DEFAULT_CURRENCY)
        expect(body['wallet']['balance']).to eq('0.0')
        expect(body['wallet']['status']).to eq('active')
        expect(body['wallet']['created_at']).to be_present
      end

      it 'persists updated values in DB' do
        run_test
        expect(wallet.reload.name).to eq('Updated Wallet Name')
      end
    end

    context 'field: id (path param)' do
      context 'when wallet not found' do
        let(:wallet_id) { 999_999 }

        it 'returns 404' do
          run_test
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when wallet belongs to another user' do
        let(:other_user) { create(:user) }
        let!(:other_wallet) { create(:wallet, user: other_user) }
        let(:wallet_id) { other_wallet.id }

        it 'returns 404' do
          run_test
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'field: name' do
      context 'when over max length (101 chars)' do
        let(:new_name) { 'a' * 101 }

        it 'returns 422 and does not update wallet' do
          run_test
          expect(response).to have_http_status(:unprocessable_entity)
          expect(wallet.reload.name).to eq(DEFAULT_NAME)
        end
      end
    end

    context 'field: status' do
      context 'when changing to suspended' do
        let(:update_params) { { status: 'suspended' } }

        it 'returns 200 with updated status' do
          run_test
          expect(response).to have_http_status(:ok)
          body = JSON.parse(response.body)
          expect(body['wallet']['status']).to eq('suspended')
          expect(wallet.reload.status).to eq('suspended')
        end
      end

      context 'when changing to closed' do
        let(:update_params) { { status: 'closed' } }

        it 'returns 200 with updated status' do
          run_test
          expect(response).to have_http_status(:ok)
          expect(wallet.reload.status).to eq('closed')
        end
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` field `currency` -- missing duplicate per user scenario

  Suggested test:
  ```ruby
  context 'when user already has a wallet with same currency' do
    before { create(:wallet, user: user, currency: 'USD') }

    it 'returns 422 and does not create wallet' do
      expect {
        post '/api/v1/wallets', params: params, headers: headers
      }.not_to change(Wallet, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `POST /api/v1/wallets` field `name` -- missing at max length (100) and over max length (101) boundary tests
- [ ] `POST /api/v1/wallets` field `currency` -- missing empty string scenario
- [ ] `POST /api/v1/wallets` response -- missing id and created_at field assertions in happy path
- [ ] `POST /api/v1/wallets` error paths -- none assert `.not_to change(Wallet, :count)`
- [ ] `GET /api/v1/wallets` -- no response shape assertions, no ordering verification, no user scoping test
- [ ] `POST /api/v1/wallets` field `status` -- permitted in params but untested (should it be settable on create?)

**LOW** (rare corner cases)

- [ ] `POST /api/v1/wallets` -- each valid currency value verified individually (USD, EUR, GBP, BTC, ETH)
- [ ] `GET /api/v1/wallets` -- empty state (no wallets returns empty array)

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | wallets_spec.rb (POST + GET combined) | HIGH | Split into post_wallets_spec.rb, get_wallets_spec.rb |
| Missing endpoint entirely | PATCH /api/v1/wallets/:id | HIGH | Create patch_wallet_spec.rb |
| Status-only assertions on errors | wallets_spec.rb:44,55,63 | MEDIUM | Add `.not_to change(Wallet, :count)` in error contexts |
| No test foundation | wallets_spec.rb:13-22 | MEDIUM | Add DEFAULT constants, subject(:run_test) |

### Top 5 Priority Actions

1. **Create test file for PATCH /api/v1/wallets/:id** -- entire endpoint has zero coverage. Changes to update logic, validation, or authorization can break silently.
2. **Add duplicate currency per user test** -- the uniqueness constraint (`validates :currency, uniqueness: { scope: :user_id }`) is a core business rule with zero test coverage.
3. **Add name boundary tests** (max 100, over 101) -- the `length: { maximum: 100 }` validation exists but is untested.
4. **Split into one endpoint per file** -- separate POST and GET into their own files for visible gap analysis.
5. **Add DB assertions to error scenarios** -- current error tests only check status code, not that no wallet was created.
