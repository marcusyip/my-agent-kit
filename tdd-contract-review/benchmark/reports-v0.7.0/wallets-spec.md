## TDD Contract Review: spec/requests/api/v1/wallets_spec.rb

**Test file:** `spec/requests/api/v1/wallets_spec.rb`
**Endpoints:** POST /api/v1/wallets, GET /api/v1/wallets
**Source files:** `app/controllers/api/v1/wallets_controller.rb`, `app/models/wallet.rb`
**Framework:** Rails 7.1 / RSpec (request spec)

### Overall Score: 4.3 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 4/10 | 25% | 1.00 |
| Test Grouping | 4/10 | 15% | 0.60 |
| Scenario Depth | 3/10 | 20% | 0.60 |
| Test Case Quality | 5/10 | 15% | 0.75 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 3/10 | 10% | 0.30 |
| **Overall** | | | **4.30** |

### Verdict: NEEDS IMPROVEMENT

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/wallets_controller.rb
        app/models/wallet.rb
Framework: Rails 7.1 / RSpec

API Contract — POST /api/v1/wallets (inbound):
  Request params:
    - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
    - name (string, required, max 100) [HIGH confidence]
  Response fields:
    - id (integer) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - name (string) [HIGH confidence]
    - balance (string) [HIGH confidence]
    - status (string) [HIGH confidence]
    - created_at (string, ISO8601) [HIGH confidence]
  Status codes: 201, 422
  Business rules:
    - currency unique per user [HIGH confidence]
    - balance defaults to 0 [HIGH confidence]
    - status defaults to 'active' [HIGH confidence]

API Contract — GET /api/v1/wallets (inbound):
  Response fields:
    - wallets (array of serialized wallets) [HIGH confidence]
  Ordering: by currency [HIGH confidence]
  Scoping: current_user.wallets [HIGH confidence]

API Contract — PATCH /api/v1/wallets/:id (inbound):
  Request params:
    - currency (string, optional) [HIGH confidence]
    - name (string, optional) [HIGH confidence]
    - status (string, optional) [HIGH confidence]
  Response fields: same 6 fields as POST response [HIGH confidence]
  Status codes: 200, 404, 422 [HIGH confidence]
  Scoping: current_user.wallets [HIGH confidence]

DB Contract — Wallet model:
  - user_id (integer, NOT NULL, FK) [HIGH confidence]
  - currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH, unique per user) [HIGH confidence]
  - name (string, NOT NULL, max 100) [HIGH confidence]
  - balance (decimal, NOT NULL, >= 0, default 0) [HIGH confidence]
  - status (string, NOT NULL, default 'active', enum: active/suspended/closed) [HIGH confidence]
============================
```

### Anti-Pattern: Multiple Endpoints in One File + Missing Endpoint

This file covers 2 endpoints (POST, GET index) in one file. PATCH /api/v1/wallets/:id has **no test file at all**. Should be split into:
- `spec/requests/api/v1/post_wallets_spec.rb`
- `spec/requests/api/v1/get_wallets_spec.rb`
- `spec/requests/api/v1/patch_wallet_spec.rb` (does not exist)

### Test Structure Tree

```
POST /api/v1/wallets
├── happy path
│   ├── ✓ returns 201
│   ├── ✓ DB count change(Wallet, :count).by(1)
│   ├── ✓ response: currency = 'USD'
│   ├── ✓ response: name = 'My USD Wallet'
│   ├── ✓ response: balance = '0.0'
│   ├── ✓ response: status = 'active'
│   ├── ✗ response: id — not asserted
│   └── ✗ response: created_at — not asserted
├── field: currency (request param)
│   ├── ✓ nil → 422
│   ├── ✓ invalid value ('XYZ') → 422
│   ├── ✗ empty string → 422
│   └── ✗ each valid value (USD, EUR, GBP, BTC, ETH) → success
├── field: name (request param)
│   ├── ✓ nil → 422
│   ├── ✗ empty string → 422
│   ├── ✗ max length (100) → should succeed
│   └── ✗ over max length (101) → 422
├── business: currency unique per user — NO TESTS
│   └── ✗ duplicate currency for same user → 422
└── error assertions completeness
    └── ✗ error scenarios only assert status code — no DB-unchanged assertions

GET /api/v1/wallets
├── happy path
│   ├── ✓ returns 200
│   ├── ✗ response body — no wallets array shape or count assertion
│   └── ✗ response fields — no individual wallet field assertions
├── ordering — NO TESTS
│   └── ✗ ordered by currency
├── scoping — NO TESTS
│   └── ✗ does not return other user's wallets
└── empty state — NO TESTS
    └── ✗ returns empty array when no wallets

PATCH /api/v1/wallets/:id — NO TEST FILE EXISTS
├── ✗ happy path — update name → 200 with updated fields
├── ✗ field: currency — update currency → success or 422
├── ✗ field: name — update name → success
├── ✗ field: status — update to suspended, closed, back to active
├── ✗ not found → 404
├── ✗ belongs to another user → 404
├── ✗ invalid params → 422
└── ✗ name too long → 422
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| POST /wallets (request) | currency | HIGH | Yes | nil, invalid | empty string, each valid, duplicate |
| POST /wallets (request) | name | HIGH | Yes | nil | empty string, max, over-max |
| POST /wallets (response) | currency, name, balance, status | HIGH | In happy path | checked | missing: id, created_at |
| POST /wallets (business) | unique currency/user | HIGH | No | -- | HIGH: untested |
| GET /wallets (response) | wallets array | HIGH | No | -- | HIGH: no shape assertions |
| PATCH /wallets/:id | all fields | HIGH | No | -- | HIGH: entire endpoint untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `PATCH /api/v1/wallets/:id` — entire endpoint has zero test coverage (`wallets_controller.rb:30-39`)

  Suggested test (new file `spec/requests/api/v1/patch_wallet_spec.rb`):
  ```ruby
  # Generated tests follow your project's patterns. Review before committing.
  RSpec.describe 'PATCH /api/v1/wallets/:id', type: :request do
    DEFAULT_NAME = 'My USD Wallet'
    DEFAULT_CURRENCY = 'USD'

    subject(:run_test) do
      patch "/api/v1/wallets/#{wallet.id}", params: { wallet: update_params }, headers: headers
    end

    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }
    let(:wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY, name: DEFAULT_NAME) }
    let(:update_params) { { name: new_name } }
    let(:new_name) { 'Updated Wallet Name' }

    context 'happy path' do
      it 'returns 200 with updated wallet' do
        run_test
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)['wallet']
        expect(body['name']).to eq('Updated Wallet Name')
        expect(body['currency']).to eq(DEFAULT_CURRENCY)
        expect(body['id']).to eq(wallet.id)
      end

      it 'persists updated data in DB' do
        run_test
        expect(wallet.reload.name).to eq('Updated Wallet Name')
      end
    end

    context 'when wallet does not exist' do
      it 'returns 404' do
        patch '/api/v1/wallets/999999', params: { wallet: update_params }, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when wallet belongs to another user' do
      let(:other_user) { create(:user) }
      let(:wallet) { create(:wallet, user: other_user) }

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

    context 'when updating status to suspended' do
      let(:update_params) { { status: 'suspended' } }

      it 'returns 200 with updated status' do
        run_test
        expect(response).to have_http_status(:ok)
        expect(wallet.reload.status).to eq('suspended')
      end
    end
  end
  ```

- [ ] `POST /api/v1/wallets` business rule — duplicate currency per user (`wallet.rb:10`)

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

- [ ] `POST /api/v1/wallets` field `name` — missing empty string, max length (100), over max length (101)
- [ ] `POST /api/v1/wallets` field `currency` — missing empty string edge case
- [ ] `POST /api/v1/wallets` happy path — missing `id` and `created_at` response field assertions
- [ ] `POST /api/v1/wallets` error scenarios — status-only assertions, no DB-unchanged checks
- [ ] `GET /api/v1/wallets` — no response shape, ordering, scoping, or empty state tests

**LOW** (rare corner cases)

- [ ] `POST /api/v1/wallets` — each valid currency value individually verified

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Multiple endpoints in one file | `wallets_spec.rb` (POST + GET index) | HIGH | Split into separate files |
| Missing entire endpoint test file | PATCH /wallets/:id | HIGH | Create `patch_wallet_spec.rb` |
| Status-only error assertions | `wallets_spec.rb:44,55,63` | MEDIUM | Add DB-unchanged assertions |
| Missing test foundation | `wallets_spec.rb` | MEDIUM | Add `subject(:run_test)`, `DEFAULT_` constants |

### Top 5 Priority Actions

1. **Create test file for PATCH /api/v1/wallets/:id** — entire endpoint is unprotected
2. **Add duplicate currency per user test** — this is a uniqueness constraint that can silently break
3. **Add `name` field edge cases** — max length boundary (100/101) is unverified
4. **Add response shape and ordering tests for GET index** — response contract is unverified
5. **Split into one endpoint per file** for gap visibility

---
