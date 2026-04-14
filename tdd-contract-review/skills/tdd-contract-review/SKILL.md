---
name: tdd-contract-review
description: Contract-based test quality review. Extracts contracts from source code, maps test coverage per field, identifies gaps, produces a scored report with prioritized actions, and auto-generates test stubs for high-priority gaps.
argument-hint: "[path, file, or 'quick' for abbreviated output -- defaults to PR scope or project root]"
allowed-tools: [Read, Write, Glob, Grep, Bash]
version: 0.16.1
---

# TDD Contract Review

Contract-based test quality review. Extract contracts from source code, map test coverage per field, identify gaps, produce a scored report with prioritized actions, and auto-generate test stubs for high-priority gaps.

## Core Philosophy

Tests protect against breaking changes by verifying contracts -- the agreements between components about data shape, behavior, and error handling. A contract field without tests means changes to that field can break things silently.

**Rules to enforce:**
- Verify contracts, NOT implementation details
- Mock minimally -- ideally only external API calls
- Use real database -- never mock DB
- Group tests by feature > field so gaps are immediately visible
- Every contract field needs edge case coverage

## Review Workflow

### Step 1: Determine Scope

Resolve `$ARGUMENTS` to find test and source files.

**Parsing rules:** split `$ARGUMENTS` on whitespace. If the first token is `quick`, enable quick mode and use remaining tokens for scope. Otherwise all tokens are scope (file path or directory). Examples: `quick spec/models` → quick mode on `spec/models`; `src/auth/` → full mode on `src/auth/`; empty → PR-scoped or project.

- **`quick` keyword**: If the first argument is `quick`, enable quick mode (abbreviated output). Use remaining arguments for scope, or default to PR-scoped/project.
- **Specific test file** (e.g. `spec/models/user_spec.rb`): review that file, locate its source
- **Source file** (e.g. `src/services/auth.ts`): find corresponding test files
- **Directory** (e.g. `src/auth/`): find all test files in that tree
- **No argument + on a non-default branch**: PR-scoped mode. Use `git diff` against the base branch to find changed source files (filter to code files: `*.rb`, `*.go`, `*.ts`, `*.tsx`, `*.jsx`, `*.js`, `*.py`). Extract contracts from those changed source files, then check the ENTIRE test suite for coverage of those contracts. This catches the key case: source changed but no tests updated.
- **No argument + on default branch**: review the entire project test suite

**Edge cases:**
- If no test files are found for the scope: report score 0/10 and list all extracted contracts as untested gaps.
- If no source files can be located: ask the user to specify paths.
- If the scope exceeds ~50 test files: recommend narrowing to a directory or using PR-scoped mode.
- If a test file has no corresponding source file: skip it or note "source file not found for this test."
- If a test file exists but is empty (no test cases): flag as anti-pattern.

Locate test files by convention:
- Same directory: `foo.test.ts`, `foo.spec.ts`, `foo_test.go`, `foo_spec.rb`
- Parallel directories: `__tests__/`, `test/`, `tests/`, `spec/`
- Go: `foo_test.go` in the same package

### Step 2: Discovery

1. **Find test files.** Glob for:
   - `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}` (Jest/Vitest)
   - `**/*_test.go` (Go)
   - `**/*_spec.rb` (RSpec)
   - `**/*.test.py`, `**/test_*.py` (pytest)

2. **Detect test framework.** Read test files to identify framework from imports and syntax.

3. **Find source files.** Locate source files corresponding to each test file. Include not just controllers/handlers but also jobs (`app/jobs/`, `app/workers/`, `workers/`) and message consumers (`app/consumers/`, `consumers/`).

4. **Check project conventions.** Read config files (CLAUDE.md, jest.config, .rspec, Makefile) for testing rules.

5. **Detect mixed frameworks.** If multiple test frameworks are present, note all of them and analyze each separately.

6. **Detect fintech domain.** Scan source files for fintech indicators: money/amount/balance/currency fields, payment/transaction/ledger/wallet models, payment gateway integrations, decimal/money types (`BigDecimal`, `decimal.Decimal`, `Decimal`, `money` gem, `dinero.js`), idempotency key params, or ledger/double-entry patterns. If detected, enable **fintech mode** which adds domain-specific contract extraction and gap analysis (see Step 3 and Step 6 fintech sections).

### Step 3: Contract Extraction

Read source files to identify all contracts in scope. For each feature/module, extract:

**API Contract (inbound endpoints):**
- Request params: field name, type, required/optional, validation rules
- Response shape: field name, type, possible values
- Status codes: success, validation error, not found, unauthorized, server error

How to extract per framework:
- Rails: read controller actions for `params.require/permit`, serializer fields, `render json:` shapes, status codes
- Go: read handler functions for request struct fields, response struct fields, HTTP status codes
- Express/NestJS: read route handlers for request body/query/param types, response shapes
- Django/FastAPI: read view functions for serializer fields, request body models, response models

**DB Data Contract (models/schemas):**
- Fields: name, type, constraints (NOT NULL, UNIQUE, DEFAULT)
- Data states: possible values for enum/status fields. **Exhaustively list every enum value** -- if a model defines `enum :status, { pending, completed, failed, reversed }`, all four values must appear in the extraction. Missing enum values are the most common source of missed gaps.
- Relationships: foreign keys, associations

How to extract per framework:
- Rails: read migration files + model files for columns, validations, associations, enum definitions
- Go: read struct tags (`db:`, `gorm:`), migration files, SQL schema files
- TypeScript: read Prisma schema, TypeORM entities, Drizzle schema
- Python: read SQLAlchemy models, Django models, Alembic migrations

**Job & Message Consumer Contract (async entry points):**
- Payload fields: name, type, required/optional, validation rules
- Expected behavior: what the job/consumer does on success
- Side effects: DB writes, API calls, enqueuing other jobs, sending notifications
- Error handling: retry strategy, dead letter queue, error reporting
- Idempotency: can the job be safely re-run with the same payload?

How to extract per framework:
- Rails: read `perform` method in ActiveJob/Sidekiq workers for arguments, DB operations, external calls
- Go: read consumer/handler functions for message struct fields, processing logic
- Node.js: read BullMQ/consumer handlers for job data shape, processing logic
- Python: read Celery tasks, RQ workers for task arguments and processing logic
- Message brokers: Kafka consumers, RabbitMQ subscribers, SQS handlers — treat the message schema as the request contract

Jobs and message consumers are contract boundaries just like API endpoints. They have input payloads, expected behavior, side effects, and error paths. Apply the same one-file-per-job convention and sessions pattern.

**API Calls Contract (outbound service calls):**
- External service name and request params
- Expected response shape
- Error handling for external failures

How to extract: read HTTP client calls (`HTTParty`, `Faraday`, `net/http`, `axios`, `fetch`, `requests`, `httpx`), identify request params and expected response shapes.

**UI Props Contract (components):**
- Props: name, type, required/optional, default values
- Rendered states: loading, error, empty, populated
- User interactions and conditional rendering

How to extract: read React/Vue component prop types/interfaces, conditional rendering logic, state-dependent UI.

**Confidence indicators:** For each extracted contract field, assign a confidence level:
- **HIGH**: Explicitly declared in code (e.g. `params.require(:currency)`, struct field with `json:"currency"` tag, TypeScript prop type definition, DB column in migration)
- **MEDIUM**: Inferred from usage patterns (e.g. response body shape from `render json:`, DB query patterns)
- **LOW**: Guessed from naming conventions or indirect references

#### Fintech Contract Extraction (when fintech mode detected)

When fintech domain is detected in Step 2, extract these additional contract dimensions on top of the standard extraction above. **Read `fintech-checklists.md` (in the same directory as this file) for detailed per-field extraction guidance.** The 8 dimensions to extract:

1. **Money & Precision** — field types (must be exact, not float), currency pairing, decimal scale, rounding
2. **Idempotency** — idempotency key fields, unique constraints, which mutating endpoints have them
3. **Transaction State Machine** — all enum values, valid/invalid transitions, terminal states, side effects per transition
4. **Balance & Ledger Integrity** — balance update method, locking strategy, double-entry patterns, check-then-act timing
5. **External Payment Integrations** — gateway calls, webhook contracts, retry/reconciliation, settlement flow
6. **Regulatory & Compliance** — KYC/AML fields, transaction limits, audit trail fields, PII fields
7. **Concurrency & Data Integrity** — TOCTOU paths, locking strategy per resource, multi-resource deadlock prevention, job deduplication, DB transaction isolation
8. **Security & Access Control** — auth requirements per endpoint, authorization/ownership rules, IDOR-vulnerable endpoints, rate limits, sensitive data in responses, payment credential handling

**Fintech Dimension Template (mandatory when fintech mode detected):**

Include this table in the Contract Extraction Summary. Fill in every row — no row may be omitted:

| # | Dimension | Status | Fields Found | Notes |
|---|-----------|--------|-------------|-------|
| 1 | Money & Precision | Extracted / Not detected | [list fields or "—"] | |
| 2 | Idempotency | Extracted / Not detected | [list fields or "—"] | |
| 3 | Transaction State Machine | Extracted / Not detected | [list fields or "—"] | |
| 4 | Balance & Ledger Integrity | Extracted / Not detected | [list fields or "—"] | |
| 5 | External Payment Integrations | Extracted / Not detected / Not applicable | [list fields or "—"] | [if N/A: rationale] |
| 6 | Regulatory & Compliance | Extracted / Not detected | [list fields or "—"] | |
| 7 | Concurrency & Data Integrity | Extracted / Not detected | [list fields or "—"] | |
| 8 | Security & Access Control | Extracted / Not detected | [list fields or "—"] | |

Status rules:
- **Extracted**: Fields found in source code. List them in the Fields Found column.
- **Not detected**: No fields found but the dimension is relevant to financial code. Write: "No fields detected — will be flagged in gap analysis."
- **Not applicable**: Only valid for dimensions where the prerequisite feature doesn't exist in source (e.g., "External Payment Integrations" when no payment gateway code exists at all). Must include rationale in the Notes column.

#### Contract Extraction Summary

After extracting all contracts, produce a summary listing every contract field found BEFORE proceeding to Steps 4-6. This makes the analysis chain auditable and mitigates non-determinism.

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
Framework: Rails/RSpec

API Contract (inbound):
  POST /api/v1/transactions
    Request params:
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max: 500) [HIGH confidence]
      - category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string, decimal-as-string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string, nullable) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (datetime, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401, 500
    Auth: before_action :authenticate_user!

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [MEDIUM confidence]
      - per_page (integer, optional, default: 25) [MEDIUM confidence]
    Response fields:
      - transactions (array) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
    Status codes: 200, 401

DB Contract:
  Transaction model:
    - user_id (integer, NOT NULL, FK) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - status (string, enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, enum: transfer/payment/deposit/withdrawal) [HIGH confidence]

  Business rules:
    - amount must be > 0 and <= 1_000_000 [HIGH confidence]
    - currency must match wallet currency [HIGH confidence]
    - wallet must be active [HIGH confidence]
    - amount constrained by wallet balance (service checks balance >= amount) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (when category == 'payment'):
    - amount (decimal) [HIGH confidence]
    - currency (string) [HIGH confidence]
    - user_id (integer) [HIGH confidence]
    - Expected: { success?: boolean }
    - On success: status → completed [HIGH confidence]
    - On failure: status → failed [HIGH confidence]
    - On ChargeError: returns 422 [HIGH confidence]
============================
```

#### Checkpoint 1 — Contract Type Verification (mandatory)

After extracting all contracts, fill in this table. Every row is mandatory. Do not skip any row.

| # | Contract Type | Status | Fields Found | Source Files Read |
|---|---------------|--------|-------------|-------------------|
| 1 | API (inbound) | [status] | [count] | [files] |
| 2 | DB (models/schema) | [status] | [count] | [files] |
| 3 | Outbound API calls | [status] | [count] | [files] |
| 4 | Jobs/consumers | [status] | [count] | [files] |
| 5 | UI props | [status] | [count] | [files] |

Status rules (three-state enum, same as fintech dimensions):
- **Extracted**: Fields found in source code. List count and source files read.
- **Not detected**: Source files were read but no contracts of this type were found. The dimension is still relevant. Write: "No fields detected — will be flagged in gap analysis if applicable."
- **Not applicable**: The codebase genuinely does not have this contract type (e.g., no background jobs, no UI). Must include rationale naming which files were checked (e.g., "Not applicable — searched app/jobs/, app/workers/, no job files found").

**GATE:** For each row with Status = "Extracted", Fields Found must be > 0. If any "Extracted" row shows 0, re-read the listed source files. A typical single-endpoint Rails controller produces 15-30 fields across all contract types. If total fields across all types is fewer than 10, re-read source files. Do not proceed to Step 4 until every row is filled and verified.

### Step 4: Test Structure Audit

Check whether tests follow the sessions pattern and group by field to make gaps visible.

#### One Endpoint Per Test File

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

Flag test files that contain multiple endpoints as an anti-pattern.

#### Test Sessions Pattern

Each endpoint test file follows this session structure:

```
Feature (top-level describe/context)
|
+-- Test foundation
|   +-- Default constants (DEFAULT_CURRENCY, DEFAULT_AMOUNT, etc.)
|   +-- subject(:run_test) / runTest helper
|   +-- Shared let/setup blocks building from defaults
|   +-- Each test overrides only the one field it tests
|
+-- 1) Happy path (major success scenarios)
|   +-- Returns correct status code
|   +-- Asserts every response field (email, currency, amount, etc.)
|   +-- Asserts every DB field persisted correctly
|   +-- Asserts correct params sent to external APIs
|   +-- (This establishes the baseline -- every field tested here
|        gets its own scenario group below for edge/error cases)
|
+-- 2) Scenarios per field (edge cases, corner cases, error paths)
    |
    |   For each error/invalid scenario, assert the FULL picture:
    |   - correct error response (status code, error message)
    |   - error response does not leak sensitive data (balances, IDs, stack traces)
    |   - no DB records created or updated
    |   - no outbound API calls made
    |   - no side effects (emails, jobs, events)
    |
    +-- request field: email
    |   +-- invalid format -> 422, no DB write, no external API call
    |   +-- null/empty -> 422, no DB write, no external API call
    |   +-- duplicate -> 422, no DB write, no external API call
    +-- request field: currency
    |   +-- each valid value (USD, EUR, GBP, JPY) -> correct tax rate
    |   +-- invalid value -> 422, no DB write
    |   +-- nil -> 422, no DB write
    +-- request field: amount
    |   +-- negative -> 422, no DB write, no external API call
    |   +-- zero (boundary) -> success or 422 depending on rules
    |   +-- very large -> success or 422 depending on rules
    +-- request field: wallet_id
    |   +-- not found -> 422, no external API call
    |   +-- belongs to another user -> 403, no DB write (IDOR)
    +-- request header: Authorization
    |   +-- missing auth token -> 401
    |   +-- expired auth token -> 401
    +-- db field: wallet.status
    |   +-- suspended -> 422, no DB write, no external API call
    |   +-- closed -> 422, no DB write, no external API call
    +-- db field: wallet.balance
    |   +-- amount > balance -> 422, no DB write (when balance-constrained)
    |   +-- amount == balance -> success, balance becomes zero
    |   +-- amount > position -> 422 (when position-constrained, e.g. sell qty > held qty)
    +-- outbound request field: ThirdPartyAPI.call(amount, currency, user_id)
    |   +-- happy path asserts correct params sent to API
    +-- outbound response field: ThirdPartyAPI.call
        +-- success -> db record.status == completed
        +-- error response -> 422, db record.status unchanged
        +-- timeout -> 503, db record.status unchanged
```

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

#### Test Foundation Pattern

The foundation is what makes this structure work. Define defaults, a single `subject`/`runTest` that executes the action, and let blocks that build from defaults. Each test overrides exactly one field.

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

#### Why This Structure

- **Test foundation** with defaults means each test case only overrides what it tests -- gaps per field become immediately visible
- **Happy path** asserts every field's expected value in the success case (response fields, DB state, outbound API params). This establishes the baseline so each scenario in section 2 only overrides one field and checks the delta
- **Scenarios per field** uses typed prefixes to make contract types explicit: `request field:` (user input validation), `request header:` (HTTP headers like auth), `db field:` (pre-existing database state), `outbound request field:` (params sent to external APIs), `outbound response field:` (handling external API responses + asserting DB state after), and `prop:` (UI component props). This makes gap analysis trivial -- if a field exists but has no test group, that's a gap. The prefix tells you which contract type it belongs to

#### Only review contract boundary test files

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

**Flag these problems:**
- Multiple endpoints in one test file (should be one endpoint per file)
- Tests verifying internal method calls or execution order (implementation testing)
- Mocked database (should use real DB)
- Mocked internal modules (only external APIs should be mocked)
- Missing test foundation (no defaults, no subject/runTest helper)
- Flat test structure without grouping by field
- Tests named after implementation rather than behavior
- Model/service specs that should be tested through the API endpoint

### Step 5: Test Case Quality Audit

Evaluate how well each individual test case is written. A test that covers the right field but is poorly written still fails to protect against breaking changes.

#### Assertion Completeness

Each test should assert the **full picture**, not just one side effect:

**For happy path tests:**
- Response status code
- Every response field value
- DB record created/updated with correct values
- Correct params sent to external APIs
- Side effects triggered (emails, jobs, events)

**For error/invalid scenario tests:**
- Error response (status code + error message)
- No DB records created or updated (assert count unchanged)
- No outbound API calls made (assert mock not called)
- No side effects triggered

Flag tests that only assert status code without checking DB or API side effects.

#### Test Readability

- **Test descriptions** state the behavior, not the implementation: "returns 422 when currency is nil" not "test_nil_currency"
- **Test data is meaningful**: `DEFAULT_CURRENCY = 'BTC'` not `currency = 'abc'`. Defaults should be realistic values that a reader can understand without context
- **Magic numbers explained**: if a test uses `999` or `100_00`, the intent should be clear from the constant name or context
- **One assertion focus per test**: each test verifies one scenario. Multiple assertions within a test are fine if they describe the same scenario (status + body + DB state for one happy path)

#### Test Isolation

- No shared mutable state between tests
- Database cleaned/rolled back between tests (transactions, truncation, or factory cleanup)
- Mocks/stubs reset between tests (`clearAllMocks`, `restore`, etc.)
- No test ordering dependencies (tests pass when run individually or in random order)
- No global variables modified in tests

#### Flaky Patterns

Flag these as anti-patterns:
- Time-dependent assertions (`Time.now`, `Date.today`) without frozen/mocked time
- Sleep/wait with fixed duration instead of condition-based waiting
- Tests depending on external network calls (unmocked HTTP)
- Random data without a seed (random failures)
- File system tests without cleanup (`t.TempDir`, `tmpdir`)

### Step 6: Gap Analysis

The primary output. For every contract field discovered in Step 3, check:

1. **Does a test exist for this field?** Search test files for the field name
2. **Is there a test group for this field?** Dedicated describe/context/t.Run
3. **What scenarios are covered?** For each field, check by prefix type:
   - `request field:` — null/nil, empty, zero, boundary, invalid type/format, very large, permission denied
   - `request header:` — missing, expired, malformed
   - `db field:` — record not exists, belongs to another user, suspended/inactive, insufficient balance, already exists (duplicate)
   - `outbound request field:` — correct params sent to external API
   - `outbound response field:` — success, error, timeout + assert DB state after change

Assign priority to each gap:
- **HIGH**: Core contract field with no tests at all
- **MEDIUM**: Field tested but missing important scenarios (edge cases, error paths)
- **LOW**: Rare corner case or defensive scenario

#### Common Field Type Scenarios (always applied)

When checking scenario coverage per field, use these type-specific checklists in addition to the generic edge cases above. Match the field's type to the relevant checklist.

**Pagination fields** (`page`, `limit`, `offset`, `cursor`, `per_page`):
- Zero value: `page=0` or `limit=0` — rejected or treated as default?
- Negative value: `page=-1` — must be rejected
- Very large limit: `limit=999999` — capped or rejected? Must not return unbounded results
- Beyond last page: page number past total pages — empty result set, not error
- Invalid cursor: malformed or expired cursor token — rejected with clear error
- Default values: omitted params use documented defaults

**Date/time fields** (`created_at`, `start_date`, `expires_at`, `scheduled_for`):
- Invalid format: non-ISO-8601 string — rejected with format guidance
- Future date: when only past dates are valid (e.g. `date_of_birth`) — rejected
- Past date: when only future dates are valid (e.g. `scheduled_for`) — rejected
- Timezone handling: dates with and without timezone offset — consistent behavior
- Boundary dates: start of day, end of day, month/year boundaries

**Array fields** (request params that accept lists):
- Empty array: `[]` — allowed or rejected depends on context
- Single item: `[item]` — processes correctly (no off-by-one)
- Max items: at configured limit — succeeds; one above — rejected
- Duplicate items in array: handled or rejected?
- Invalid item within valid array: one bad item in a list of valid ones — partial success or full rejection?

**String fields with format constraints** (`email`, `url`, `phone`, `uuid`):
- Valid format: at least one representative value per format
- Invalid format: structurally wrong (missing `@` in email, no protocol in URL)
- Edge format: technically valid but unusual (`user+tag@domain.com`, unicode domain)
- Max length: at schema limit — succeeds; one over — rejected
- Empty string vs. null: often behave differently — test both

**File upload fields** (`avatar`, `document`, `attachment`):
- File too large: exceeds size limit — rejected with clear error
- Wrong MIME type: `.exe` when only images allowed — rejected
- Empty file: zero-byte upload — rejected or accepted?
- Missing file: required upload field omitted — rejected

#### Fintech Gap Analysis (when fintech mode detected)

When fintech domain is detected, check every extracted fintech contract field against the scenario checklists in `fintech-checklists.md` (section "Gap Analysis Scenario Checklists"). These are HIGH priority by default because financial bugs cause real money loss.

For each category below, produce gap entries in the report. The top scenarios (must-check) are listed inline; read the reference file for the full checklist per category.

**1. Money/amount fields:**
- Precision overflow: amount with more decimals than schema allows → round, truncate, or reject?
- Zero amount: allowed or rejected? (transfers reject, queries allow)
- Boundary at max: exactly at configured limit → 201; one above → 422
- Balance validation: amount > available balance → rejected; amount == balance → success with zero remaining
- Position validation: sell/reduce qty > held position → rejected; qty == position → closes position

**Cross-dimension rule for amount fields:** When an amount field's endpoint has a balance check or position check in its code path (e.g., service validates `balance >= amount`, controller checks `position >= qty`), add "exceeds balance → 422" and/or "exceeds position → 422" as scenarios under a `db field: wallet.balance` or `db field: position.quantity` entry in the Test Structure Tree. Balance and position constraints are database state conditions, not input validation — they belong under `db field:`, not under `request field: amount`.

**2. Idempotency:**
- Duplicate POST with same idempotency key → must return original response, not create second record
- Missing key on mutating financial endpoint → flag as design gap if no key exists

**3. State machine:**
- Every valid transition tested with correct side effects
- At least one invalid transition tested (e.g. `completed → pending` → rejected)
- Terminal states: no further transitions allowed

**4. Balance/ledger:**
- Insufficient balance → rejected
- Exact balance value asserted after operation (not just "changed")

**5. Concurrency** (check even if no tests exist — flag the absence):
- TOCTOU: if code reads balance then writes in separate steps without a lock, flag as HIGH gap. Test: two concurrent requests that both pass balance check individually but together exceed balance — only one should succeed
- Double-submit: two rapid identical POSTs must not create duplicate financial records
- If the code uses `with_lock`, `FOR UPDATE`, or optimistic locking: flag that no test verifies the lock actually prevents concurrent corruption

**6. Security & access control:**
- Authentication: at least one `request header: Authorization` entry per endpoint with missing/expired token → 401
- IDOR: at least one test per `request field:` that accepts a resource ID — access other user's resource → 403/404 (scenario under the resource ID field)
- Sensitive data in error responses: for each error scenario, assert the response body does not leak balances, account numbers, internal user IDs, SQL errors, or stack traces. Error body should contain only an error code and generic message. Flag if no error test asserts response body content

**7. Absence flagging** — flag missing infrastructure when the prerequisite source patterns exist. Only fire each flag when its condition is met (avoids false positives for features that genuinely don't exist in the codebase). Include these in the gap analysis under a "Missing infrastructure" section, separate from per-field gaps.

**HIGH priority:**
- No idempotency key on mutating endpoints → flag when mutating financial endpoints exist ("no idempotency key on mutating endpoints — duplicate requests can create duplicate financial records")
- No concurrency protection on financial write paths → flag when balance updates, transfers, or other financial write paths exist ("no database locking or atomic updates detected on financial write paths — concurrent requests can cause double-debit or overdraw")

**MEDIUM priority:**
- No rate limiting on financial mutation endpoints → flag when financial mutation endpoints exist ("no rate limiting detected — consider adding to prevent brute-force/card testing attacks")
- No audit trail table/fields for financial mutations → flag when financial mutations exist ("no audit trail detected — financial operations should be auditable")
- No explicit state machine or transition guards → flag when financial entities with status/state fields exist ("no explicit state machine or transition guards detected for financial entities — invalid state transitions can corrupt financial data")
- No balance validation or ledger consistency patterns → flag when balance/wallet fields exist ("no balance validation or ledger consistency patterns detected — balance integrity depends on application-level checks")
- No webhook signature verification or payment gateway error handling → flag when payment gateway code is detected ("no webhook signature verification or payment gateway error handling detected — external payment events can be spoofed or silently lost")
- No KYC/AML fields, transaction limits, or compliance validations → flag when financial user accounts or transactions exist ("no KYC/AML fields, transaction limits, or compliance validations detected — financial operations may lack regulatory safeguards")

#### Checkpoint 2 — Gap Analysis Verification (mandatory)

After completing gap analysis (including fintech if applicable), fill in this table. Every contract type from Checkpoint 1 with Status "Extracted" or "Not detected" must have a corresponding row here.

| # | Contract Type | Gaps Checked? | HIGH Gaps | MEDIUM Gaps | LOW Gaps |
|---|---------------|---------------|-----------|-------------|----------|
| 1 | API (inbound) | [Yes/No] | [count] | [count] | [count] |
| 2 | DB (models/schema) | [Yes/No] | [count] | [count] | [count] |
| 3 | Outbound API calls | [Yes/No] | [count] | [count] | [count] |
| 4 | Jobs/consumers | [Yes/No] | [count] | [count] | [count] |
| 5 | UI props | [Yes/No] | [count] | [count] | [count] |

**GATE:** Every contract type from Checkpoint 1 with Status "Extracted" must show "Yes" in Gaps Checked. If any shows "No", go back and analyze gaps for that contract type before proceeding. Types marked "Not applicable" in Checkpoint 1 may be omitted from this table.

### Step 7: Auto-Generate Test Stubs

For each HIGH-priority gap from Step 6, generate test code that follows the project's existing test patterns.

**How to learn patterns:**
1. Read 2-3 existing test files in the project to identify: framework, helper methods, assertion style, factory/fixture usage, file organization
2. Match the existing test foundation pattern (defaults, subject/runTest, let blocks)

**Generation rules:**
- Generated tests MUST verify contract fields, never implementation details
- Follow the sessions pattern: defaults at top, single subject/runTest, each test overrides one field
- Group generated tests by the contract field they cover
- Include a note at the top: "Generated tests follow your project's patterns. Review before committing."

**Cold start (no existing tests):**
If no test files exist for the scope, generate test stubs using framework-specific defaults from the examples in Step 4. Note in the output: "No existing tests found. Generated stubs use default patterns."

**Output format:**
For each HIGH gap, output the generated test as a fenced code block inline in the report, immediately after the gap entry. Use the full gap description as the heading — never use shorthand labels like "Stub H1", "Stub H4", etc. The reader should understand what each stub tests without cross-referencing the gap list.

```
HIGH: request field: currency (POST /api/transactions) -- no test for nil, invalid, empty string, each valid value

Suggested test:
\`\`\`ruby
context 'when currency is nil' do
  let(:currency) { nil }

  it 'returns 422 and does not create a transaction' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'when currency is invalid' do
  let(:currency) { 'INVALID' }

  it 'returns 422 and does not create a transaction' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
\`\`\`
```

### Step 8: Score and Report

**One report per test file, written to separate files.** Each test file gets its own report file with its own contract extraction, test structure tree, gap analysis, and score. A summary file is also written.

**Write reports to `tdd-contract-review/{datetime}-report/`** in the project root (create it if it doesn't exist). Use the current date and time for `{datetime}` in `YYYYMMDD-HHMM` format (e.g. `tdd-contract-review/20260412-1630-report/`). Get the current time by running `date +%Y%m%d-%H%M` via Bash. File naming convention:
- Per-file reports: kebab-case of the test file name, e.g. `tdd-contract-review/20260412-1630-report/post-transactions-spec.md`
- Summary: `tdd-contract-review/20260412-1630-report/summary.md`

Do all analysis (reading files, extracting contracts, auditing tests) first, then write all report files.

**GATE — Report Files Must Be Written:** You MUST write per-file report files using the Write tool before printing any summary to the conversation. The report files are the primary output — the conversation summary is secondary. After writing, verify the files exist by listing the report directory. If no files exist after this step, you have not completed the review — go back and write them. Each per-file report MUST include: Contract Extraction Summary (all contract types: API, DB, outbound, jobs), Test Structure Tree, Contract Map (every extracted field gets a row), Gap Analysis with auto-generated stubs, Anti-Patterns table, Score breakdown.

After writing and verifying report files, print a short summary to the conversation showing the files created and scores.

**If file writes are blocked**, fall back to printing all reports inline in a single response. Do not retry blocked writes.

If a test file contains multiple endpoints (anti-pattern), still produce one report for that file but flag the multi-endpoint issue prominently.

Score each report across 6 categories:

| Category | Weight | Focus |
|---|---|---|
| Contract Coverage | 25% | Are all contract fields tested? |
| Test Grouping | 15% | Grouped by feature > field for visible gaps? |
| Scenario Depth | 20% | Per field: edge cases, corner cases, error paths covered? |
| Test Case Quality | 15% | Assertion completeness, readability, meaningful data? |
| Isolation & Flakiness | 15% | Real DB, no state leakage, no flaky patterns, only external APIs mocked? |
| Anti-Patterns | 10% | Implementation testing, over-mocking, assert-free tests? |

**Verdicts:** STRONG (8-10) / ADEQUATE (6-7.9) / NEEDS IMPROVEMENT (4-5.9) / WEAK (0-3.9)

**Scoring calibration anchors:**
- **9-10 (STRONG):** Every contract field has a test group. Happy paths assert all response fields + DB state. All enum values covered. External API mocked with success/failure/timeout. No anti-patterns. Rare -- most mature codebases top out at 8.
- **7 (ADEQUATE):** Most contract fields tested. Happy paths exist but may miss some response fields. A few enum values or edge cases missing. Minor anti-patterns (e.g., some status-only assertions).
- **5 (NEEDS IMPROVEMENT):** Core fields tested but significant gaps: missing error path coverage, incomplete happy path assertions, untested endpoints, no external API scenarios.
- **2-3 (WEAK):** Minimal tests exist. Most contract fields untested. No test foundation pattern. Status-only assertions throughout. Major features have zero coverage.

#### Full Report Template

```markdown
## TDD Contract Review: [test file path]

**Test file:** [e.g. spec/requests/api/v1/post_transactions_spec.rb]
**Endpoint:** [e.g. POST /api/v1/transactions]
**Source files:** [list of source files this test covers]
**Framework:** [detected framework and language]

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every API endpoint, job, and message consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `✓` = scenario is tested
- `✗` = scenario is missing (potential silent breakage)
- Each entry point (endpoint, job, consumer) gets its own section
- Fields use typed prefixes: `request field:` (user input), `request header:` (HTTP headers), `db field:` (database state), `outbound request field:` (params sent), `outbound response field:` (response handling + DB assertions)
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**One endpoint per file:** Each API endpoint, job, or consumer should have its own test file. This makes gaps immediately visible — if a file doesn't exist, the entire contract is untested.

**Contract boundary:** Tests should verify behavior at the contract boundary (API endpoint, job entry point), not internal implementation. Testing that a service method is called is implementation testing — testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have. A codebase with 100 tests that only check status codes scores lower than one with 20 tests that verify response fields, DB state, and error paths.

### Overall Score: X.X / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | X/10 | 25% | X.XX |
| Test Grouping | X/10 | 15% | X.XX |
| Scenario Depth | X/10 | 20% | X.XX |
| Test Case Quality | X/10 | 15% | X.XX |
| Isolation & Flakiness | X/10 | 15% | X.XX |
| Anti-Patterns | X/10 | 10% | X.XX |
| **Overall** | | | **X.XX** |

### Verdict: [STRONG | ADEQUATE | NEEDS IMPROVEMENT | WEAK]

### Contract Extraction Summary

[Include the full contract extraction summary from Step 3. MUST include ALL contract types found: API (inbound) request/response fields, DB table fields and enum values, outbound API call params and response shapes, job/consumer payloads, UI props. If a contract type was extracted in Step 3, it MUST appear here. Do not omit DB or outbound contracts.]

### Fintech Dimensions Summary

When fintech mode is active, include this table in every per-file report. Copy the status from the Step 3 extraction template. For "Not detected" dimensions, show the gap count from the absence flagging in Step 6. For "Not applicable" dimensions, show "—" in both Fields and Gaps columns.

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | 4 fields | 2 HIGH, 1 MEDIUM |
| 2 | Idempotency | Extracted | 2 fields | 1 HIGH |
| 3 | Transaction State Machine | Not detected — flagged | — | Infrastructure gap |
| 4 | Balance & Ledger Integrity | Extracted | 3 fields | 1 HIGH, 2 MEDIUM |
| 5 | External Payment Integrations | Not applicable | — | — |
| 6 | Regulatory & Compliance | Not detected — flagged | — | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Not detected — flagged | — | Infrastructure gap |
| 8 | Security & Access Control | Extracted | 5 fields | 3 HIGH |

**Fintech mode:** Active — all 8 dimensions evaluated.

### Test Structure Tree

Visual map of contract fields and their test coverage. Each endpoint/model is a root node. Fields are branches with typed prefixes: `request field:` (user input), `request header:` (HTTP headers), `db field:` (pre-existing database state), `outbound request field:` (params sent to external APIs), `outbound response field:` (response handling + DB state assertions), `prop:` (UI component props). Every scenario is its own line — both covered (`✓`) and missing (`✗`) — so gaps are immediately visible.

```
POST /api/v1/transactions
├── request field: amount
│   ├── ✓ happy path → 201, response.amount == "100.50", db transaction.amount == 100.50
│   ├── ✓ nil → 422, no DB write
│   ├── ✓ negative → 422, no DB write
│   ├── ✗ zero (boundary)
│   ├── ✗ max (1_000_000) → should succeed
│   ├── ✗ over max (1_000_001) → 422
│   ├── ✗ non-numeric string → 422
│   └── ✗ precision overflow (0.123456789 when schema is decimal(20,8))
├── request field: currency
│   ├── ✓ nil → 422
│   ├── ✓ invalid → 422
│   ├── ✗ empty string
│   └── ✗ each valid value (USD, EUR, GBP, BTC, ETH) verified
├── request field: wallet_id
│   ├── ✓ not found → 422
│   └── ✗ another user's wallet → 403 (IDOR)
├── request field: description — NO TESTS
│   ├── ✗ nil (optional, should succeed)
│   ├── ✗ max length (500) → should succeed
│   └── ✗ over max length (501) → 422
├── request field: category — NO TESTS
│   ├── ✗ each valid value (transfer/payment/deposit/withdrawal)
│   ├── ✗ invalid value → 422
│   └── ✗ nil (defaults to transfer)
├── request header: Authorization — NO TESTS
│   ├── ✗ missing auth token → 401
│   └── ✗ expired auth token → 401
├── db field: wallet.status — NO TESTS
│   ├── ✗ suspended → 422, no DB write
│   └── ✗ closed → 422, no DB write
├── db field: wallet.balance — NO TESTS
│   ├── ✗ amount > balance → 422, no DB write
│   ├── ✗ amount == balance → success, balance becomes zero
│   └── ✗ currency mismatch with wallet → 422
├── db field: transaction.status — NO TESTS
│   └── ✗ enum pending/completed/failed/reversed transitions untested
├── outbound request field: PaymentGateway.charge(amount, currency, user_id) — NO TESTS
│   └── ✗ happy path asserts correct params sent (amount, currency, user_id)
└── outbound response field: PaymentGateway.charge — NO TESTS
    ├── ✗ success → db transaction.status == completed, db wallet.balance deducted
    ├── ✗ failure → db transaction.status == failed, db wallet.balance unchanged
    └── ✗ ChargeError → 422, no DB status change

GET /api/v1/transactions
├── request field: page (pagination) — NO TESTS
│   ├── ✗ page=0 → rejected or default
│   ├── ✗ page=-1 → rejected
│   └── ✗ beyond last page → empty array
├── request field: per_page (pagination) — NO TESTS
│   ├── ✗ per_page=0 → rejected or default
│   ├── ✗ very large (999999) → capped or rejected
│   └── ✗ default 25 when omitted
├── request header: Authorization — NO TESTS
│   └── ✗ missing auth token → 401
└── db field: user scope — NO TESTS
    └── ✗ only returns current user's transactions

Wallet#deposit!
├── ✓ positive amount → increases balance
├── ✓ negative amount → raises ArgumentError
├── ✓ zero amount → raises ArgumentError
├── ✓ suspended wallet → raises error
└── ✗ closed wallet → raises error
```

Every scenario is its own line. Use `✓` for covered, `✗` for missing. Fields with no tests at all get a `— NO TESTS` label on the field line.

### Contract Map

Every contract field from the extraction summary MUST appear in this table — API request/response fields, DB table fields, outbound API params, job payloads. If a field was extracted, it gets a row. Missing rows mean the report is incomplete. **Cross-reference Checkpoint 1:** the number of rows per contract type in this table must be consistent with the Fields Found count from Checkpoint 1. If Checkpoint 1 shows 8 DB fields extracted but the Contract Map has fewer than 8 DB rows, fields were dropped — go back and add the missing rows.

| Type | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| request field | POST /transactions: amount | HIGH | Yes | nil, negative | HIGH: zero, max, over-max, precision overflow |
| request field | POST /transactions: currency | HIGH | Yes | nil, invalid | MEDIUM: empty string, each valid value |
| request field | POST /transactions: wallet_id | HIGH | Yes | not found | HIGH: another user's wallet (IDOR) |
| request field | POST /transactions: description | HIGH | No | -- | HIGH: untested (nil, max length, over-max) |
| request field | POST /transactions: category | HIGH | No | -- | HIGH: untested (each value, invalid, nil default) |
| request field | GET /transactions: page | MEDIUM | No | -- | MEDIUM: pagination untested (zero, negative, beyond last) |
| request field | GET /transactions: per_page | MEDIUM | No | -- | MEDIUM: untested (very large, default) |
| request header | Authorization (all endpoints) | HIGH | No | -- | HIGH: no 401 test |
| db field | wallet.status | HIGH | Yes | active, suspended | missing: closed |
| db field | wallet.balance | HIGH | No | -- | HIGH: exceeds balance, equals balance untested |
| db field | transaction.status | HIGH | No | -- | HIGH: enum pending/completed/failed/reversed untested |
| outbound request field | PaymentGateway.charge(amount) | HIGH | No | -- | HIGH: not asserted in happy path |
| outbound request field | PaymentGateway.charge(currency) | HIGH | No | -- | HIGH: not asserted in happy path |
| outbound response field | PaymentGateway.charge → success | HIGH | No | -- | HIGH: db transaction.status + wallet.balance untested |
| outbound response field | PaymentGateway.charge → failure | HIGH | No | -- | HIGH: db transaction.status untested |
| outbound response field | PaymentGateway.charge → ChargeError | HIGH | No | -- | HIGH: 422 + no DB change untested |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)
- [ ] `request field: amount` (POST /api/transactions) -- happy path does not assert response.amount or db transaction.amount

  Suggested test:
  [auto-generated test stub from Step 7]

- [ ] `db field: wallet.balance` (POST /api/transactions) -- no test for amount > balance or amount == balance

  Suggested test:
  [auto-generated test stub from Step 7]

- [ ] `outbound request field: PaymentGateway.charge(amount, currency, user_id)` -- happy path does not assert params sent
- [ ] `outbound response field: PaymentGateway.charge` -- success/failure/error paths untested, no DB assertions after response

  Suggested test:
  [auto-generated test stub from Step 7]

**MEDIUM** (tested but missing scenarios)
- [ ] `request field: currency` (POST /api/transactions) -- missing empty string, each valid value
- [ ] `request field: page` (GET /api/transactions) -- missing page=0, page=-1, beyond last page

**LOW** (rare corner cases)
- [ ] ...

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Mocked database | spec/models/user_spec.rb:15 | HIGH | Use real DB |

### Top 5 Priority Actions

1. [Most impactful test to add, with the contract it protects]
2. [Second]
3. [Third]
4. [Fourth]
5. [Fifth]
```

#### Multi-File Summary

When the scope includes multiple test files, write one report file per test file, then write `summary.md` in the same report directory.

**The summary is strictly a rollup.** Every finding, gap, anti-pattern, and recommendation MUST appear in a per-file report first. The summary MUST NOT contain details, findings, or analysis not already in a per-file report. If a finding doesn't belong to a specific test file (e.g. missing infrastructure, cross-cutting concerns), include it in the most relevant per-file report.

```markdown
## TDD Contract Review — Summary

| Test File | Endpoint | Score | Verdict | HIGH Gaps | MEDIUM Gaps |
|---|---|---|---|---|---|
| spec/requests/api/v1/post_transactions_spec.rb | POST /api/v1/transactions | 3.7/10 | WEAK | 8 | 4 |
| spec/requests/api/v1/get_transactions_spec.rb | GET /api/v1/transactions | 5.2/10 | NEEDS IMPROVEMENT | 2 | 3 |
| spec/requests/api/v1/post_wallets_spec.rb | POST /api/v1/wallets | 6.5/10 | ADEQUATE | 1 | 2 |

**Missing test files** (source exists but no test file):
- PATCH /api/v1/wallets/:id — no test file exists
- ProcessPaymentJob — no test file exists

**Overall: X files reviewed, X HIGH gaps, X MEDIUM gaps**

### Fintech Dimensions (aggregated)

When fintech mode is active, aggregate the dimension status across all per-file reports:

| # | Dimension | Status | Files With Gaps | Total Gaps |
|---|-----------|--------|----------------|------------|
| 1 | Money & Precision | Extracted | 2 of 3 | 4 HIGH, 2 MEDIUM |
| 2 | Idempotency | Extracted | 1 of 3 | 1 HIGH |
| 3 | Transaction State Machine | Not detected — flagged | — | Infrastructure gap |
| 4 | Balance & Ledger Integrity | Extracted | 2 of 3 | 1 HIGH, 2 MEDIUM |
| 5 | External Payment Integrations | Not applicable | — | — |
| 6 | Regulatory & Compliance | Not detected — flagged | — | Infrastructure gap |
| 7 | Concurrency & Data Integrity | Not detected — flagged | — | Infrastructure gap |
| 8 | Security & Access Control | Extracted | 3 of 3 | 3 HIGH |
```

#### Quick Mode Template

When quick mode is enabled (user passed `quick` as first argument), output only:

```markdown
## TDD Contract Review -- Quick Summary

**Score: X.X / 10** ([VERDICT])
**Scope:** [scope description]

### HIGH Priority Gaps ([count])
- `[contract]` field `[field]` ([confidence]) -- [gap description]
- ...

### Summary
- MEDIUM gaps: [count]
- LOW gaps: [count]
- Anti-patterns: [count]

Run `/tdd-contract-review [same scope]` for full report with auto-generated test stubs.
```

## Review Principles

1. **Read the source, not just tests.** Identify missing contracts by understanding the source code. Always read source files to extract contracts before checking test coverage.
2. **Be specific.** Every finding references `file:line`. Every gap names the exact field and missing edge case. Never say "needs more tests."
3. **Prioritize by breakage risk.** A missing test for a core API field is HIGH. A missing edge case for an internal utility is LOW.
4. **Respect the mock boundary.** The only acceptable mocks are external API calls. Flag everything else.
5. **Be calibrated.** Most real codebases score 4-7. A score of 9 means genuinely no gaps found. Do not inflate.
6. **Do not run tests.** Static analysis of test quality only, not execution.
