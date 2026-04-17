<!-- version: 0.28.0 -->
# Test Patterns Reference

Detailed guidance for Steps 4-5 of the TDD Contract Review workflow.

## Input/Assertion Model

Every field is either an **input** (you set it in the test) or an **assertion** (you verify it after the request), or both:

| Prefix | Role | Tree branch? | How |
|---|---|---|---|
| `request field:` | Input | Yes | Set in request params |
| `request header:` | Input | Yes | Set in request headers |
| `db field:` (input) | Input | Yes | Set in test setup (precondition) |
| `db field:` (assertion) | Assertion | No | Verify DB state after request (postcondition) |
| `response field:` | Assertion | No | Verify inbound API response body fields |
| `outbound response field:` | Input | Yes | Set via mock return value |
| `outbound request field:` | Assertion | No | Verify correct params sent to external API mock |
| `prop:` | Input | Yes | Set as component props |

**Input fields get their own tree branch with scenarios.** Request fields, request headers, db fields (as input), outbound response fields, props.
**Assertion fields do NOT get their own tree branch.** `response field:`, `db field:` (assertion), `outbound request field:` are verified in the happy path.

## One Endpoint Per Test File

Each API endpoint gets its own test file. Do not combine multiple endpoints in a single file — it obscures gaps and makes the tree harder to audit.

```
# GOOD: one endpoint per file
spec/requests/api/v1/
├── post_transactions_spec.rb      # POST /api/v1/transactions
├── get_transactions_spec.rb       # GET /api/v1/transactions
├── get_transaction_spec.rb        # GET /api/v1/transactions/:id
├── post_wallets_spec.rb           # POST /api/v1/wallets
├── patch_wallet_spec.rb           # PATCH /api/v1/wallets/:id
└── get_wallets_spec.rb            # GET /api/v1/wallets

# BAD: multiple endpoints in one file
spec/requests/api/v1/
├── transactions_spec.rb           # POST + GET + GET/:id mixed together
└── wallets_spec.rb                # POST + GET + PATCH mixed together
```

## Test Foundation Pattern

The foundation is what makes the sessions structure work. Define defaults, a single `subject`/`runTest` that executes the action, and let blocks that build from defaults. Each test overrides exactly one field.

**RSpec (request spec):**
```ruby
RSpec.describe 'POST /api/v1/transactions', type: :request do
  # Test foundation
  DEFAULT_CURRENCY = 'BTC'
  DEFAULT_AMOUNT = '100'.to_d

  subject(:run_test) do
    post '/api/v1/transactions', params: { transaction: params }, headers: headers
  end

  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:params) { { currency: currency, amount: amount } }
  let(:currency) { DEFAULT_CURRENCY }
  let(:amount) { DEFAULT_AMOUNT }
  let!(:db_wallet) { create(:wallet, user: user, currency: DEFAULT_CURRENCY) }

  # 1) Happy path
  context 'happy path' do
    it 'returns 201 with transaction' do
      run_test
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['transaction']['amount']).to eq(DEFAULT_AMOUNT.to_s)
      expect(body['transaction']['currency']).to eq(DEFAULT_CURRENCY)
    end

    it 'persists correct data in DB' do
      expect { run_test }.to change(Transaction, :count).by(1)
      db_txn = Transaction.last
      expect(db_txn.user_id).to eq(user.id)
      expect(db_txn.wallet_id).to eq(db_wallet.id)
    end
  end

  # 2) Scenarios per field -- each overrides ONE field
  context 'when currency is nil' do
    let(:currency) { nil }

    it 'returns 422' do
      run_test
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'when wallet does not exist in DB' do
    before { db_wallet.destroy! }

    it 'returns 422' do
      run_test
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

**Go (handler test with real DB):**
```go
func TestCreateTransaction(t *testing.T) {
    // Test foundation
    const (
        defaultCurrency = "BTC"
        defaultAmount   = 100
    )
    defaults := func() CreateParams {
        return CreateParams{Currency: defaultCurrency, Amount: defaultAmount}
    }
    runTest := func(t *testing.T, userID int64, p CreateParams) *httptest.ResponseRecorder {
        t.Helper()
        body, _ := json.Marshal(p)
        req := httptest.NewRequest("POST", "/api/v1/transactions", bytes.NewReader(body))
        req = withUserCtx(req, userID)
        w := httptest.NewRecorder()
        handler.CreateTransaction(w, req)
        return w
    }

    // 1) Happy path
    t.Run("happy_path", func(t *testing.T) {
        w := runTest(t, 1, defaults())
        assert.Equal(t, http.StatusCreated, w.Code)
    })

    // 2) Scenarios per field -- each overrides ONE field
    t.Run("field/currency/nil", func(t *testing.T) {
        p := defaults()
        p.Currency = ""
        w := runTest(t, 1, p)
        assert.Equal(t, http.StatusUnprocessableEntity, w.Code)
    })
}
```

## Frontend/UI Test Pattern

For frontend/UI tests, the same pattern applies with component props as fields:

```
Component (top-level describe)
|
+-- Test foundation (default props, render helper)
|
+-- 1) Happy path (renders correctly with default props)
|   +-- Asserts every visible element with default props
|   +-- Asserts each prop's default rendering (isLoading, items, etc.)
|   +-- (Baseline -- each prop gets its own scenario group below)
|
+-- 2) Scenarios per prop
    +-- prop: isLoading
    |   +-- true -> shows spinner
    |   +-- false -> shows content
    +-- prop: items
    |   +-- empty array -> shows empty state
    |   +-- single item -> renders correctly
    |   +-- many items -> renders list
    +-- prop: onSubmit
        +-- called on form submit
        +-- not called when validation fails
```

## Contract Boundary Rules

Only produce full reports for test files that cover **contract boundaries**:
- API endpoints (controllers/handlers)
- Jobs (workers, ActiveJob, Sidekiq, Celery, BullMQ)
- Message consumers (Kafka, RabbitMQ, SQS)

**Do NOT produce full reports for:**
- Model specs (e.g. `spec/models/wallet_spec.rb`) — models are internal, tested implicitly through endpoints
- Service specs (e.g. `spec/services/transaction_service_spec.rb`) — services are internal implementation
- Unit tests for internal modules, helpers, utilities

When these non-boundary test files are found in scope, **flag them as anti-patterns in the summary** with a one-line recommendation (e.g. "Delete `transaction_service_spec.rb` — test through `POST /api/v1/transactions` instead"). Do not produce a per-file report for them.

**Exception — when internals ARE contract boundaries:** A contract is an agreement between teams, services, or systems. If a service or model is consumed across team boundaries (e.g., a shared library, a public SDK, an internal service called by other teams' code), then it IS a contract boundary and deserves a full report. The test is: "would changing this break someone outside my team?" If yes, it's a contract.

## Anti-Patterns to Flag

- Multiple endpoints in one test file (should be one endpoint per file)
- Tests verifying internal method calls or execution order (implementation testing)
- Mocked database (should use real DB)
- Mocked internal modules (only external APIs should be mocked)
- Missing test foundation (no defaults, no subject/runTest helper)
- Flat test structure without grouping by field
- Tests named after implementation rather than behavior
- Model/service specs that should be tested through the API endpoint

## Test Case Quality (Step 5)

### Assertion Completeness

Each test should assert the **full picture**, not just one side effect:

**For happy path tests (verify ALL assertion fields):**
- Response status code + response field values
- `db field (assertion):` — every DB field persisted correctly (e.g. transaction.user_id == user.id)
- `outbound request field (assertion):` — correct params sent to external API mock (e.g. expect(Gateway).to have_received(:charge).with(amount: 100))
- Side effects triggered (emails, jobs, events)

**For error/invalid scenario tests (verify nothing happened):**
- Error response (status code + error message)
- No DB records created or updated (assert count unchanged)
- No outbound API calls made (assert mock not called)
- No side effects triggered
- No data leak in error response

Flag tests that only assert status code without checking DB or API side effects.

### Test Readability

- **Test descriptions** state the behavior, not the implementation: "returns 422 when currency is nil" not "test_nil_currency"
- **Test data is meaningful**: `DEFAULT_CURRENCY = 'BTC'` not `currency = 'abc'`. Defaults should be realistic values that a reader can understand without context
- **Magic numbers explained**: if a test uses `999` or `100_00`, the intent should be clear from the constant name or context
- **One assertion focus per test**: each test verifies one scenario. Multiple assertions within a test are fine if they describe the same scenario (status + body + DB state for one happy path)

### Test Isolation

- No shared mutable state between tests
- Database cleaned/rolled back between tests (transactions, truncation, or factory cleanup)
- Mocks/stubs reset between tests (`clearAllMocks`, `restore`, etc.)
- No test ordering dependencies (tests pass when run individually or in random order)
- No global variables modified in tests

### Flaky Patterns

Flag these as anti-patterns:
- Time-dependent assertions (`Time.now`, `Date.today`) without frozen/mocked time
- Sleep/wait with fixed duration instead of condition-based waiting
- Tests depending on external network calls (unmocked HTTP)
- Random data without a seed (random failures)
- File system tests without cleanup (`t.TempDir`, `tmpdir`)
