## TDD Contract Review: POST /api/v1/transactions

**Unit:** POST /api/v1/transactions
**Source file:** app/controllers/api/v1/transactions_controller.rb (create action) + app/services/transaction_service.rb
**Test file(s):** spec/requests/api/v1/transactions_spec.rb, spec/services/transaction_service_spec.rb
**Framework:** Rails / RSpec
**Fintech mode:** yes

### How to Read This Report

**What is a contract?** A contract is the agreement between components about data shape, behavior, and error handling. Every endpoint, job, and consumer has contracts: what fields it accepts, what it returns, what happens on invalid input, and what side effects it triggers. A field without tests means changes to it can break things silently.

**Test Structure Tree** shows your test coverage at a glance:
- `✓` = scenario is tested
- `✗` = scenario is missing (potential silent breakage)
- Fields use typed prefixes: `request field:` (user input), `request header:` (HTTP headers), `db field:` (database state), `outbound response field:` (response handling + outbound params + DB assertions)
- Each field lists every scenario individually so you can see exactly what's covered and what's not

**Contract boundary:** Tests should verify behavior at the contract boundary (endpoint entry, job entry, consumer entry), not internal implementation. Testing that a service method is called is implementation testing. Testing that POST returns 422 when the wallet is suspended is contract testing.

**Scoring:** The score reflects how well your tests protect against breaking changes, not how many tests you have.

### Overall Score: 1.5 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 1/10 | 25% | 0.25 |
| Test Grouping | 2/10 | 15% | 0.30 |
| Scenario Depth | 1/10 | 20% | 0.20 |
| Test Case Quality | 1/10 | 15% | 0.15 |
| Isolation & Flakiness | 4/10 | 15% | 0.60 |
| Anti-Patterns | 0/10 | 10% | 0.00 |
| **Overall** | | | **1.50** |

**Scoring rationale:**

- **Contract Coverage (1/10):** 33 out of 36 contract fields have zero test coverage. The 3 partial fields (amount, currency, wallet_id) assert only status codes and do not verify any response body, DB state, or outbound call assertions. The entire response body, all DB postconditions, and all outbound API parameters are completely untested.
- **Test Grouping (2/10):** The request spec groups by param name which is a step toward correct structure, but groups are shallow, multiple endpoints are combined in one file, and the service spec exists as a parallel non-boundary file duplicating concerns without adding coverage.
- **Scenario Depth (1/10):** Meaningful scenario depth exists only for amount (nil + negative, 2 of 17 needed) and currency (nil + invalid, 2 of 15 needed). Zero scenarios exist for: every response field, every DB postcondition, every outbound call, wallet status enum values, wallet balance preconditions, wallet currency mismatch, description field, category field, and Authorization header.
- **Test Case Quality (1/10):** Every test asserts only `have_http_status`. No response body parsing, no DB assertions, no outbound API assertions, no negative assertions on error paths.
- **Isolation & Flakiness (4/10):** The request spec uses a real DB (correct). PaymentGateway is an external SDK boundary and is never mocked in the request spec — any network call that exists would be uncontrolled. Score restrained by complete absence of outbound mock setup.
- **Anti-Patterns (0/10):** Seven anti-patterns identified — service spec testing private method dispatch, multiple endpoints in one file, implementation testing, missing shared run_test helper, error tests assert status only, happy path asserts status only. These are pervasive across both test files.

### Verdict: WEAK

---

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb (create action)
        app/services/transaction_service.rb
Framework: Rails/RSpec

API Contract (inbound):
  POST /api/v1/transactions

    Input:
      request header: Authorization (bearer token, required)
        — enforced by before_action :authenticate_user!
      request field: transaction.amount (decimal string, required, > 0, <= 1_000_000)
        — validated in Transaction model: numericality greater_than: 0, less_than_or_equal_to: 1_000_000
        — also validated against wallet.balance in TransactionService#validate_sufficient_balance!
      request field: transaction.currency (string, required, in: USD/EUR/GBP/BTC/ETH)
        — validated in Transaction model: inclusion in %w[USD EUR GBP BTC ETH]
        — also validated against wallet.currency in TransactionService#validate_currency_match!
      request field: transaction.wallet_id (integer, required)
        — scoped via current_user.wallets.find_by(id: ...)
        — returns 422 "Wallet not found" if not found or not owned by user
      request field: transaction.description (string, optional, max: 500 chars)
        — validated in Transaction model: length maximum: 500
      request field: transaction.category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer)
        — default set in TransactionService#build_transaction; payment triggers PaymentGateway.charge

    Assertion (verify in happy path):
      response field: transaction.id (integer)
      response field: transaction.amount (decimal-as-string via .to_s)
      response field: transaction.currency (string)
      response field: transaction.status (string, enum: pending/completed/failed/reversed)
      response field: transaction.description (string, nullable)
      response field: transaction.category (string, enum: transfer/payment/deposit/withdrawal)
      response field: transaction.wallet_id (integer)
      response field: transaction.created_at (datetime, ISO8601 via .iso8601)
      response field: transaction.updated_at (datetime, ISO8601 via .iso8601)

    Status codes: 201 (created), 422 (validation / wallet / balance / currency / gateway errors), 401 (unauthenticated)

    Error response shape (422):
      response field: error (string, human-readable)
      response field: details (array of strings)

DB Contract:
  Input (preconditions):
    db field: wallet.status — enum: active/suspended/closed; must be 'active'
    db field: wallet.balance — decimal(20,8), NOT NULL, DEFAULT 0; must be >= requested amount
    db field: wallet.currency — must match request currency

  Assertion (postconditions):
    db field: transaction.user_id (integer, NOT NULL, FK → users.id)
    db field: transaction.wallet_id (integer, NOT NULL, FK → wallets.id)
    db field: transaction.amount (decimal(20,8), NOT NULL)
    db field: transaction.currency (string, NOT NULL, enum: USD/EUR/GBP/BTC/ETH)
    db field: transaction.status (string, NOT NULL, DEFAULT 'pending', enum: pending/completed/failed/reversed)
    db field: transaction.description (string, nullable, max 500)
    db field: transaction.category (string, NOT NULL, DEFAULT 'transfer', enum: transfer/payment/deposit/withdrawal)
    db field: transaction.created_at (datetime, NOT NULL, auto)
    db field: transaction.updated_at (datetime, NOT NULL, auto)
    db field: wallet.balance — decremented by transaction.amount (except deposit category)

Outbound API:
  PaymentGateway.charge(amount:, currency:, user_id:, transaction_id:)
  Triggered only when transaction.category == 'payment'
  CRITICAL: dual call paths — TransactionService#charge_payment_gateway (line 78) AND
  Transaction#notify_payment_gateway after_create callback (model line 28)

    Assertion (verify params sent):
      outbound request field: amount (decimal, matches transaction.amount)
      outbound request field: currency (string, matches transaction.currency)
      outbound request field: user_id (integer, matches current_user.id)
      outbound request field: transaction_id (integer, matches transaction.id)

    Input (set via mock):
      outbound response field: success? (boolean)
        — true → transaction.status = 'completed'
        — false → transaction.status = 'failed'
      outbound response field: PaymentGateway::ChargeError (exception path)
        — rescued → 422, error: 'Payment processing failed'
      outbound response field: no external reference parsed (reconciliation gap)
============================
```

---

### Fintech Dimensions Summary

| # | Dimension | Status | Fields | Gaps |
|---|-----------|--------|--------|------|
| 1 | Money & Precision | Extracted | 4 fields (amount decimal(20,8), balance decimal(20,8), BigDecimal coercion, currency paired with amount) | 1 HIGH (precision beyond scale:8), 1 MEDIUM (float trap) |
| 2 | Idempotency | Gap — absent in source | 0 fields | 1 HIGH (no idempotency key on request or outbound charge) |
| 3 | Transaction State Machine | Extracted | 4 states (pending/completed/failed/reversed); 2 transitions observed | 2 HIGH (transitions untested, invalid-transition guards absent), 1 HIGH (stuck-pending detection) |
| 4 | Balance & Ledger Integrity | Extracted | wallet.balance with_lock; balance check outside lock | 2 CRITICAL (TOCTOU race, rollback absent on ChargeError), 1 CRITICAL (deposit does not credit balance) |
| 5 | External Payment Integration | Extracted | PaymentGateway.charge SDK | 1 CRITICAL (double-charge dual call paths), 2 HIGH (timeout handling absent, reconciliation reference absent) |
| 6 | Regulatory & Compliance | Partial | 1_000_000 cap validated | 3 MEDIUM (no audit trail, no KYC/AML hook, no per-user velocity limits) |
| 7 | Concurrency & Data Integrity | Gap | with_lock on withdraw! only | 1 CRITICAL (balance check outside lock = TOCTOU), 1 MEDIUM (concurrent status mutation) |
| 8 | Security & Access Control | Partial | authenticate_user!, IDOR scoping via current_user.wallets | 1 CRITICAL (IDOR untested), 1 CRITICAL (balance leak in error details), 1 HIGH (no rate limiting), 1 HIGH (Auth header zero coverage) |

---

### Test Structure Tree

```
POST /api/v1/transactions
│
├── request header: Authorization — NO TESTS
│   ├── ✗ missing token → 401, no DB write, no outbound API call, no data leak
│   ├── ✗ malformed token → 401, no DB write, no data leak
│   ├── ✗ expired token → 401, no DB write, no data leak
│   └── ✗ token for deleted/disabled user → 401, no DB write, no data leak
│
├── request field: transaction.amount — PARTIAL (2 scenarios, status-code only)
│   ├── ✓ nil → 422 (transactions_spec.rb:42) [no negative assertions]
│   ├── ✓ negative → 422 (transactions_spec.rb:51) [no negative assertions]
│   ├── ✗ empty string "" → 422, no DB write, no outbound API call, no data leak
│   ├── ✗ zero "0" → 422, no DB write, no outbound API call, no data leak
│   ├── ✗ non-numeric string "abc" → 422, no DB write, no data leak
│   ├── ✗ boundary: exactly max 1_000_000 → 201
│   ├── ✗ boundary: just-over-max 1_000_000.00000001 → 422, no DB write, no data leak
│   ├── ✗ precision: 9 decimal places → document behavior (round/truncate/reject)
│   ├── ✗ float trap: JSON float → assert decimal precision preserved
│   ├── ✗ cross-field: amount == wallet.balance → 201, wallet.balance becomes 0
│   ├── ✗ cross-field: amount > wallet.balance → 422, no DB write, no outbound API call, no balance leak
│   └── ✗ concurrency: two concurrent requests where sum > balance → only one succeeds, balance never negative
│
├── request field: transaction.currency — PARTIAL (2 scenarios, status-code only)
│   ├── ✓ nil → 422 (transactions_spec.rb:60) [no negative assertions]
│   ├── ✓ invalid value "ZZZ" → 422 (transactions_spec.rb:69) [no negative assertions]
│   ├── ✗ empty string "" → 422, no DB write, no data leak
│   ├── ✗ enum value: USD → 201, response currency == 'USD'
│   ├── ✗ enum value: EUR → 201, response currency == 'EUR'
│   ├── ✗ enum value: GBP → 201, response currency == 'GBP'
│   ├── ✗ enum value: BTC → 201, response currency == 'BTC'
│   ├── ✗ enum value: ETH → 201, response currency == 'ETH'
│   └── ✗ cross-field: request currency 'USD', wallet.currency 'EUR' → 422, no DB write, no outbound API call, no data leak
│
├── request field: transaction.wallet_id — PARTIAL (1 scenario, status-code only)
│   ├── ✓ wallet does not exist → 422 (transactions_spec.rb:78) [no negative assertions]
│   ├── ✗ nil → 422, no DB write, no data leak
│   ├── ✗ IDOR: belongs to another user → 422, no DB write, no data leak, response must NOT confirm other user's wallet exists
│   └── ✗ type violation: string "abc" → 422, no DB write, no data leak
│
├── request field: transaction.description — NO TESTS
│   ├── ✗ omitted (optional) → 201, transaction.description == nil
│   ├── ✗ provided → 201, persisted verbatim
│   ├── ✗ boundary: exactly 500 chars → 201
│   └── ✗ boundary: 501 chars → 422, no DB write, no data leak
│
├── request field: transaction.category — NO TESTS
│   ├── ✗ omitted → 201, defaults to 'transfer', response.category == 'transfer', db.category == 'transfer'
│   ├── ✗ enum value: 'transfer' → 201, balance decremented, NO PaymentGateway.charge call
│   ├── ✗ enum value: 'payment' → 201, PaymentGateway.charge invoked exactly once, balance decremented
│   ├── ✗ enum value: 'deposit' → 201, wallet.balance NOT decremented
│   ├── ✗ enum value: 'withdrawal' → 201, balance decremented
│   └── ✗ invalid value 'refund' → 422, no DB write, no outbound API call, no data leak
│
├── response field: transaction.id — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; integer type; non-nil; matches Transaction.last.id
│
├── response field: transaction.amount — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; decimal-as-string (via .to_s); value matches request.amount; not a JSON float
│
├── response field: transaction.currency — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; string; value matches request.currency
│
├── response field: transaction.status — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; one of pending/completed/failed/reversed
│   ├── ✗ for transfer/deposit/withdrawal: defaults to 'pending'
│   ├── ✗ for payment + gateway success: 'completed'
│   └── ✗ for payment + gateway failure: 'failed'
│
├── response field: transaction.description — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201 when provided; echoes input
│   └── ✗ nullability: when omitted, field present with null value
│
├── response field: transaction.category — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; one of transfer/payment/deposit/withdrawal
│   └── ✗ when omitted in request, response.category == 'transfer'
│
├── response field: transaction.wallet_id — NO TESTS (happy-path assertion)
│   └── ✗ present on 201; integer; matches request.wallet_id
│
├── response field: transaction.created_at — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; ISO8601 format
│   └── ✗ string type, UTC offset present
│
├── response field: transaction.updated_at — NO TESTS (happy-path assertion)
│   ├── ✗ present on 201; ISO8601 format
│   └── ✗ >= created_at
│
├── response field: error (error envelope) — NO TESTS
│   ├── ✗ present on every 422; string; human-readable
│   ├── ✗ does NOT leak stack traces / SQL errors / class names
│   ├── ✗ for insufficient balance: error message is generic (no balance value)
│   ├── ✗ for IDOR wallet: does NOT confirm wallet exists for another user
│   └── ✗ for ChargeError: error == 'Payment processing failed' (exact match)
│
├── response field: details (error envelope) — NO TESTS
│   ├── ✗ present on 422; array of strings
│   ├── ✗ FINTECH SECURITY: InsufficientBalanceError currently leaks balance ("Current balance: X, requested: Y") — must NOT be present
│   └── ✗ does NOT leak account numbers, user IDs, SQL fragments, or stack traces
│
├── db field: wallet.status (input; enum: active/suspended/closed) — NO TESTS
│   ├── ✗ active (happy path) → 201 [factory default assumed, never explicitly set or asserted]
│   ├── ✗ suspended → 422, no transaction row, no outbound call, no data leak
│   └── ✗ closed → 422, no transaction row, no outbound call, no data leak
│
├── db field: wallet.balance (input; decimal(20,8)) — NO TESTS
│   ├── ✗ balance > amount (happy path) → 201, balance decremented exactly
│   ├── ✗ balance == amount (exact match) → 201, balance becomes exactly 0.00000000
│   ├── ✗ balance < amount (insufficient) → 422, balance unchanged, no transaction row, no balance leak
│   └── ✗ balance == 0 → 422
│
├── db field: wallet.currency (input) — NO TESTS
│   ├── ✗ wallet.currency == request.currency (happy path) → 201
│   └── ✗ wallet.currency != request.currency (mismatch) → 422, no DB write, no outbound call
│
├── db field: transaction.user_id (assertion; NOT NULL, FK) — NO TESTS
│   └── ✗ happy path: transaction.user_id == current_user.id
│
├── db field: transaction.wallet_id (assertion; NOT NULL, FK) — NO TESTS
│   └── ✗ happy path: transaction.wallet_id == request.wallet_id
│
├── db field: transaction.amount (assertion; decimal(20,8), NOT NULL) — NO TESTS
│   ├── ✗ happy path: transaction.amount == request.amount (BigDecimal equality)
│   └── ✗ precision preserved: "0.12345678" persists as 0.12345678
│
├── db field: transaction.currency (assertion; NOT NULL, enum) — NO TESTS
│   └── ✗ happy path: transaction.currency == request.currency
│
├── db field: transaction.status (assertion; NOT NULL, DEFAULT 'pending', enum) — NO TESTS
│   ├── ✗ DEFAULT 'pending' for non-payment categories
│   ├── ✗ pending → completed: category='payment' + success?=true
│   ├── ✗ pending → failed: category='payment' + success?=false
│   └── ✗ pending → failed: ChargeError raised
│
├── db field: transaction.description (assertion; nullable, max 500) — NO TESTS
│   ├── ✗ provided: persists verbatim
│   └── ✗ omitted: IS NULL
│
├── db field: transaction.category (assertion; NOT NULL, DEFAULT 'transfer', enum) — NO TESTS
│   ├── ✗ DEFAULT 'transfer' when omitted
│   └── ✗ each enum value persists: transfer, payment, deposit, withdrawal
│
├── db field: transaction.created_at (assertion; NOT NULL, auto) — NO TESTS
│   └── ✗ auto-populated; within request wall-clock window
│
├── db field: transaction.updated_at (assertion; NOT NULL, auto) — NO TESTS
│   ├── ✗ auto-populated on insert; equals created_at on insert
│   └── ✗ monotonic on status transition (payment path)
│
├── db field: wallet.balance (assertion — post-state) — NO TESTS
│   ├── ✗ non-deposit: wallet.balance == initial_balance - request.amount (exact BigDecimal)
│   ├── ✗ deposit category: wallet.balance UNCHANGED
│   └── ✗ rollback on ChargeError: no orphan debit
│
├── db field: transaction row presence (assertion) — NO TESTS
│   ├── ✗ happy path: Transaction.count changes by +1
│   └── ✗ every 422 path: Transaction.count unchanged
│
├── outbound response field: PaymentGateway.charge.success? (input — mock return) — NO TESTS
│   ├── ✗ success?=true → 201, db status='completed', wallet.balance decremented, response status='completed'
│   ├── ✗ success?=false → db status='failed', no data leak
│   └── ✗ upstream nil response / missing .success? method → graceful 422, no 500, no class name leak
│
├── outbound response field: PaymentGateway::ChargeError (input — mock raises) — NO TESTS
│   ├── ✗ ChargeError raised → 422, db status != 'completed', response error='Payment processing failed', no data leak
│   └── ✗ wallet.balance side effects consistent (no orphan debit)
│
├── outbound request field: amount (assertion) — NO TESTS
│   ├── ✗ sent as BigDecimal matching transaction.amount
│   └── ✗ fractional scale: 10.12345678 preserved
│
├── outbound request field: currency (assertion) — NO TESTS
│   └── ✗ sent matching transaction.currency
│
├── outbound request field: user_id (assertion) — NO TESTS
│   └── ✗ sent from current_user.id (not params-forgeable)
│
├── outbound request field: transaction_id (assertion) — NO TESTS
│   └── ✗ sent as persisted Transaction.id (non-nil)
│
├── outbound call-count: exactly once on payment — NO TESTS [FINTECH CRITICAL]
│   ├── ✗ category='payment' → PaymentGateway.charge received exactly 1 time (NOT 2)
│   └── ✗ dual call paths (service line 78 + model after_create line 28) — double-charge bug; pin to .once
│
└── outbound call-count: zero on non-payment categories and validation failures — NO TESTS
    ├── ✗ category='transfer' → NOT called
    ├── ✗ category='deposit' → NOT called
    ├── ✗ category='withdrawal' → NOT called
    ├── ✗ amount nil (422) → NOT called
    ├── ✗ currency invalid (422) → NOT called
    ├── ✗ wallet.status suspended (422) → NOT called
    ├── ✗ wallet.balance insufficient (422) → NOT called
    └── ✗ Authorization missing (401) → NOT called
```

---

### Contract Map

| Type | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| request header | Authorization | HIGH | NO | 0 | 4 |
| request field | transaction.amount | HIGH | PARTIAL | 2 (nil, negative — status only) | 15 |
| request field | transaction.currency | HIGH | PARTIAL | 2 (nil, invalid — status only) | 12 |
| request field | transaction.wallet_id | HIGH | PARTIAL | 1 (not found — status only) | 9 |
| request field | transaction.description | HIGH | NO | 0 | 13 |
| request field | transaction.category | HIGH | NO | 0 | 12 |
| response field | transaction.id | HIGH | NO | 0 | 1 |
| response field | transaction.amount | HIGH | NO | 0 | 1 |
| response field | transaction.currency | HIGH | NO | 0 | 1 |
| response field | transaction.status | HIGH | NO | 0 | 1 |
| response field | transaction.description | HIGH | NO | 0 | 1 |
| response field | transaction.category | HIGH | NO | 0 | 1 |
| response field | transaction.wallet_id | HIGH | NO | 0 | 1 |
| response field | transaction.created_at | HIGH | NO | 0 | 1 |
| response field | transaction.updated_at | HIGH | NO | 0 | 1 |
| response field | error (422 envelope) | HIGH | NO | 0 | 1 |
| response field | details (422 envelope) | HIGH | NO | 0 | 2 |
| db field (input) | wallet.status | HIGH | NO | 0 | 4 |
| db field (input) | wallet.balance | HIGH | NO | 0 | 7 |
| db field (input) | wallet.currency | HIGH | NO | 0 | 4 |
| db field (assertion) | transaction.user_id | HIGH | NO | 0 | 3 |
| db field (assertion) | transaction.wallet_id | HIGH | NO | 0 | 3 |
| db field (assertion) | transaction.amount | HIGH | NO | 0 | 5 |
| db field (assertion) | transaction.currency | HIGH | NO | 0 | 3 |
| db field (assertion) | transaction.status | HIGH | NO | 0 | 7 |
| db field (assertion) | transaction.description | HIGH | NO | 0 | 3 |
| db field (assertion) | transaction.category | HIGH | NO | 0 | 4 |
| db field (assertion) | transaction.created_at | HIGH | NO | 0 | 2 |
| db field (assertion) | transaction.updated_at | HIGH | NO | 0 | 3 |
| db field (assertion) | wallet.balance (post-state) | HIGH | NO | 0 | 6 |
| db field (assertion) | transaction row presence | HIGH | NO | 0 | 3 |
| outbound response field | PaymentGateway.charge.success? | HIGH | NO | 0 | 8 |
| outbound response field | PaymentGateway::ChargeError | HIGH | NO | 0 | 4 |
| outbound request field | amount | HIGH | NO | 0 | 3 |
| outbound request field | currency | HIGH | NO | 0 | 1 |
| outbound request field | user_id | HIGH | NO | 0 | 1 |
| outbound request field | transaction_id | HIGH | NO | 0 | 2 |
| outbound call-count | exactly once on payment | HIGH | NO | 0 | 1 |
| outbound call-count | zero on non-payment/validation failures | HIGH | NO | 0 | 14 |

---

### Gap Analysis by Priority

**CRITICAL** (immediate risk — money, security, data integrity)

- [ ] `outbound call-count: PaymentGateway.charge exactly once per payment` (GOUT-001/GFIN-001) — Dual call paths: service line 78 AND model after_create line 28. For category='payment', gateway charged twice per request. Customers double-charged today. No test pins call count to 1.

  Suggested test:
  ```ruby
  context 'outbound PaymentGateway.charge call count (category=payment)' do
    before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }
    it 'invokes PaymentGateway.charge exactly once per request' do
      run_test
      expect(PaymentGateway).to have_received(:charge).once
    end
  end
  ```

- [ ] `response field: details` balance leak (GAPI-001/GFIN-005) — InsufficientBalanceError detail includes raw balance value. No test asserts sensitive financial data is NOT in error responses.

- [ ] `request field: transaction.wallet_id` IDOR (GAPI-002) — No test with a valid wallet_id belonging to a different user. Any refactor to Wallet.find_by would silently permit cross-tenant writes.

- [ ] `request header: Authorization` (GAPI-003/GFIN-015) — Zero coverage for any 401 path. A regression in authenticate_user! would expose the endpoint publicly.

- [ ] `db field (input): wallet.balance` concurrent TOCTOU (GDB-001/GFIN-003) — validate_sufficient_balance! reads balance outside the with_lock used by withdraw!. Two concurrent requests can each pass the check and both withdraw, driving balance negative.

- [ ] `db field (assertion): wallet.balance` rollback on ChargeError (GDB-002/GFIN-002) — On ChargeError, withdraw! may already have run with no DB transaction wrapping service flow. No compensating rollback. Real money lost.

- [ ] `db field (assertion): transaction.status` state machine (GDB-003) — pending → completed and pending → failed transitions entirely untested. A change leaving every payment stuck in 'pending' ships green.

- [ ] `db field (assertion): wallet.balance` deposit category silent bug (GDB-004) — deduct_balance! skips withdraw! for deposit with no credit either. Current contract is "deposit does nothing to balance" — must be locked by test.

- [ ] `db field (assertion): transaction row presence on error paths` (GDB-005) — Every 422 asserts only status code. A regression inserting orphan 'pending' rows on validation failure ships green.

**HIGH** (core contract fields missing tests — stubs required)

- [ ] `request field: transaction.amount` overdraft (GAPI-004) — No test for amount > wallet.balance. Must assert 422, no DB write, no gateway call, no balance leak.
- [ ] `request field: transaction.amount` exact balance boundary (GAPI-005) — No test for amount == wallet.balance. Account should drain to exactly 0.
- [ ] `request field: transaction.amount` just-over-max (GAPI-006) — No boundary test at the 1_000_000 regulatory cap.
- [ ] `request field: transaction.amount` zero (GAPI-007) — numericality greater_than: 0 means zero must reject; untested.
- [ ] `request field: transaction.amount` non-numeric (GAPI-008) — BigDecimal coercion on "abc" is undefined without a pinning test.
- [ ] `request field: transaction.amount` precision beyond scale:8 (GAPI-009) — Must pin round/truncate/reject behavior.
- [ ] `request field: transaction.currency` wallet mismatch (GAPI-010) — validate_currency_match! is untested through the endpoint.
- [ ] `request field: transaction.currency` per-enum value (GAPI-011) — Only USD exercised; EUR, GBP, BTC, ETH need happy-path + response assertion.
- [ ] `request field: transaction.category` every enum value (GAPI-012) — Zero coverage; each enum drives different code paths.
- [ ] `request field: transaction.category` default 'transfer' (GAPI-013) — No test confirms omitting category results in 'transfer'.
- [ ] `request field: transaction.category` invalid value (GAPI-014) — No test for 'refund'; must 422, no DB write, no outbound call.
- [ ] `request field: transaction.description` length boundary (GAPI-015) — No tests at all; needs 500-char and 501-char boundary tests.
- [ ] `response field: transaction.id/amount/currency/status/wallet_id/category/description/created_at/updated_at` (GAPI-016) — Happy path asserts only 201; response body never parsed.
- [ ] `response field: error` on 422 paths (GAPI-017) — No error-body assertions in any error test.
- [ ] `request field: transaction.currency` empty string (GAPI-018) — nil covered; "" takes a separate validation path.
- [ ] `request field: transaction.wallet_id` nil (GAPI-019) — No test for nil wallet_id; find_by(id: nil) path.
- [ ] Upgrade existing PARTIAL error tests (GAPI-020) — transactions_spec.rb:42,51,60,69,78 assert status only; add no-DB-write + no-gateway + no-data-leak assertions.
- [ ] `db field (input): wallet.status = 'suspended'` (GDB-010) — Must assert 422 + no row + no outbound call.
- [ ] `db field (input): wallet.status = 'closed'` (GDB-011) — Same as suspended.
- [ ] `db field (input): wallet.balance` exact-match boundary (GDB-012) — amount == balance must succeed; balance becomes exactly 0.00000000.
- [ ] `db field (input): wallet.balance` insufficient (GDB-013) — amount > balance must 422; balance unchanged, no row.
- [ ] `db field (input): wallet.currency mismatch` (GDB-014) — wallet=USD, request=EUR must 422, no write, no outbound.
- [ ] `db field (input): wallet ownership IDOR` (GDB-015) — DB-level: wallet_id for another user must 422, no write, no attribute leak.
- [ ] `db field (assertion): transaction.user_id` (GDB-020) — Never asserted as current_user.id.
- [ ] `db field (assertion): transaction.wallet_id` (GDB-021) — Never asserted as request.wallet_id.
- [ ] `db field (assertion): transaction.amount precision` (GDB-022) — decimal(20,8) precision must be verified.
- [ ] `db field (assertion): transaction.currency value` (GDB-023) — Never asserted at DB layer.
- [ ] `db field (assertion): transaction.status DEFAULT 'pending'` (GDB-024) — For non-payment, status must be 'pending'.
- [ ] `db field (assertion): transaction.status pending → completed` (GDB-025) — payment + success?=true must leave status='completed'.
- [ ] `db field (assertion): transaction.status pending → failed (success?=false)` (GDB-026) — payment + success?=false must leave status='failed'.
- [ ] `db field (assertion): transaction.status pending → failed (ChargeError)` (GDB-027) — Must leave DB in consistent state.
- [ ] `db field (assertion): transaction.description provided + omitted` (GDB-028) — Provided persists verbatim; omitted is NULL.
- [ ] `db field (assertion): transaction.category DEFAULT 'transfer'` (GDB-029) — Omitted category must persist as 'transfer'.
- [ ] `db field (assertion): transaction.category each enum value` (GDB-030) — transfer, payment, deposit, withdrawal must each persist.
- [ ] `db field (assertion): wallet.balance decremented on non-deposit` (GDB-031) — Core ledger invariant: balance == initial - amount.
- [ ] `outbound response field: PaymentGateway.charge.success?=true` (GOUT-002) — Core payment happy path absent from request spec.
- [ ] `outbound response field: PaymentGateway.charge.success?=false` (GOUT-003) — Failure path; must pin db status='failed'.
- [ ] `outbound response field: PaymentGateway::ChargeError` (GOUT-004) — 422 + exact message + no completed state.
- [ ] `outbound request field: amount` sent correctly (GOUT-005) — No test verifies amount argument sent to gateway.
- [ ] `outbound request field: currency` sent correctly (GOUT-006) — No test verifies currency argument.
- [ ] `outbound request field: user_id` sent correctly (GOUT-007) — Must come from current_user.id, not params.
- [ ] `outbound request field: transaction_id` sent correctly (GOUT-008) — Must reference persisted Transaction row.
- [ ] `outbound call-count: zero on non-payment categories` (GOUT-009) — No assertion that transfer/deposit/withdrawal do not call gateway.
- [ ] `outbound call-count: zero on validation failures` (GOUT-010) — No error test asserts not_to have_received(:charge).
- [ ] `outbound call: idempotency key absent` (GOUT-011/GFIN-004) — No idempotency key passed to gateway; retried HTTP POST creates duplicate charges.
- [ ] `outbound response field: timeout/network error` (GOUT-012) — Only ChargeError rescued; Timeout::Error/ECONNREFUSED bubble to 500 leaking class names.
- [ ] `db field: transaction.status` invalid-transition guards (GFIN-006) — No guard on completed→pending, failed→completed, reversed→*.
- [ ] Stuck-pending detection (GFIN-007) — Exception between withdraw! and update! leaves row 'pending' with wallet debited.
- [ ] Rate limiting (GFIN-008) — No Rack::Attack or per-user throttle on money-mutating endpoint.
- [ ] Reconciliation reference (GFIN-009) — PaymentGateway response not parsed for external reference.
- [ ] Retry/backoff absent (GFIN-010) — Every timeout becomes immediate 'failed' with wallet debited; no backoff.

**MEDIUM** (missing scenarios)

- [ ] `request field: transaction.description` injection payloads (GAPI-021)
- [ ] `request field: transaction.currency` case sensitivity, whitespace (GAPI-022)
- [ ] `request field: transaction.amount` type violations: array, object (GAPI-023)
- [ ] `response field: transaction.description` nullability contract (GAPI-024)
- [ ] `db field (input): wallet.balance` just-under boundary (GDB-040)
- [ ] `db field (input): wallet.balance == 0` (GDB-041)
- [ ] `db field (input): wallet.currency` each valid pairing (GDB-042)
- [ ] `db field (assertion): transaction.created_at` auto-populated (GDB-043)
- [ ] `db field (assertion): transaction.updated_at == created_at` on insert (GDB-044)
- [ ] `db field (assertion): transaction.updated_at` monotonic on status transition (GDB-045)
- [ ] `db field (assertion): transaction.amount` large boundary 1_000_000 (GDB-046)
- [ ] `db field (input): wallet.status` concurrent mutation (GDB-047)
- [ ] Malformed upstream response: nil / missing .success? method (GOUT-013)
- [ ] Partial/missing upstream reference (GOUT-014)
- [ ] Amount/currency tampering in upstream response (GOUT-015)
- [ ] No audit trail / event stream (GFIN-011)
- [ ] No KYC/AML hook (GFIN-012)
- [ ] Single hard-coded cap; no per-user velocity limits (GFIN-013)
- [ ] No HTML/script sanitization on description (GFIN-014)

**LOW** (rare corner cases)

- [ ] UTF-8 multibyte in description (GAPI-025)
- [ ] `request field: transaction.wallet_id` very-large integer (GAPI-026)
- [ ] `db field (assertion): transaction.user_id` NOT NULL enforced (GDB-050)
- [ ] `db field (assertion): transaction.wallet_id` NOT NULL enforced (GDB-051)
- [ ] `db field (assertion): transaction.amount` NOT NULL enforced (GDB-052)
- [ ] `db field (assertion): transaction.currency` NOT NULL enforced (GDB-053)
- [ ] `db field (assertion): transaction.status` NOT NULL enforced (GDB-054)
- [ ] `db field (assertion): transaction.category` NOT NULL enforced (GDB-055)
- [ ] `db field (assertion): invalid enum for transaction.status` rejected (GDB-056)
- [ ] `db field (assertion): invalid enum for transaction.category` rejected (GDB-057)
- [ ] `db field (assertion): transaction.status terminal 'reversed'` unreachable from POST (GDB-058)
- [ ] `db field (input): wallet.currency case sensitivity` (GDB-059)
- [ ] Non-boolean truthy from success? (GOUT-016)

---

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Service spec tests internal implementation, not contract boundary | spec/services/transaction_service_spec.rb | HIGH | Delete file; move behavioral coverage to request spec |
| Multiple endpoints in one request spec file | spec/requests/api/v1/transactions_spec.rb lines 21, 100, 119 | HIGH | Split into post_transactions_spec.rb, get_transaction_spec.rb, get_transactions_spec.rb |
| Implementation testing — private method dispatch asserted | spec/services/transaction_service_spec.rb lines 12–25 | HIGH | Replace with behavior-based request spec scenarios |
| Implementation testing — internal gateway wrapper asserted instead of outbound params | spec/services/transaction_service_spec.rb lines 47–51 | HIGH | Assert PaymentGateway.charge params + transaction.status in request spec |
| No shared run_test helper — each test manually calls post inline | spec/requests/api/v1/transactions_spec.rb lines 37, 46, 54, 63, 72, 90 | MEDIUM | Extract a subject or run_test helper; use let overrides for field isolation |
| Error scenario tests assert only status code — no negative assertions | spec/requests/api/v1/transactions_spec.rb lines 42–93 | HIGH | Add: not_to change(Transaction, :count), not_to have_received(:charge), no data leak assertion |
| Happy path asserts only status code — no body, no DB, no outbound | spec/requests/api/v1/transactions_spec.rb lines 35–40 | HIGH | Add full response body, DB postcondition, and outbound call assertions |

---

### Hygiene

The following structural anti-patterns were identified during the audit. They must be addressed before contract gaps can be efficiently filled — adding tests into the current structure will not produce auditable coverage.

#### Anti-pattern 1: Service spec is not a contract boundary

**File:** `spec/services/transaction_service_spec.rb`

`TransactionService` is an internal implementation detail of `POST /api/v1/transactions`. It is not consumed by other teams or systems. This spec should be deleted and its behavioral coverage moved into the request spec.

**Recommendation:** Delete `spec/services/transaction_service_spec.rb` — test through `POST /api/v1/transactions` instead.

---

#### Anti-pattern 2: Multiple endpoints in one request spec file

**File:** `spec/requests/api/v1/transactions_spec.rb`

The file contains three `describe` blocks covering three separate endpoints:
- `POST /api/v1/transactions` (line 21)
- `GET /api/v1/transactions/:id` (line 100)
- `GET /api/v1/transactions` (line 119)

Each endpoint must have its own file so gaps are immediately visible per endpoint.

**Recommendation:** Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, and `get_transactions_spec.rb`.

---

#### Anti-pattern 3: Implementation testing in service spec

**File:** `spec/services/transaction_service_spec.rb` lines 12–25

Three tests verify that private methods are called, not what behavior is produced. These are implementation tests, not contract tests.

```ruby
# lines 12–25
it 'calls build_transaction' do
  expect(service).to receive(:build_transaction).and_call_original
  service.call
end
it 'calls validate_wallet_active!' do
  expect(service).to receive(:validate_wallet_active!).and_call_original
  service.call
end
it 'calls validate_currency_match!' do
  expect(service).to receive(:validate_currency_match!).and_call_original
  service.call
end
```

---

#### Anti-pattern 4: Implementation testing — gateway method call instead of behavior

**File:** `spec/services/transaction_service_spec.rb` lines 47–51

The test asserts that `charge_payment_gateway` (an internal private method) is called, not that the correct params were sent to `PaymentGateway.charge` or that the transaction status was updated correctly.

```ruby
# lines 47–51
it 'calls charge_payment_gateway' do
  allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  expect(service).to receive(:charge_payment_gateway).and_call_original
  service.call
end
```

---

#### Anti-pattern 5: Missing test foundation (no shared `run_test` helper)

**File:** `spec/requests/api/v1/transactions_spec.rb`

Each test manually calls `post '/api/v1/transactions', params: params, headers: headers` inline (e.g. lines 37, 46, 54, 63, 72, 90). There is no shared `subject` or `run_test` helper. This means override-one-field isolation is not enforced and the structure is harder to audit.

---

#### Anti-pattern 6: Error scenario tests assert only status code — no negative assertions

**File:** `spec/requests/api/v1/transactions_spec.rb` (lines 42–93)

Every error scenario asserts only `have_http_status`. None asserts:
- No DB record was created
- No outbound `PaymentGateway.charge` call was made
- No sensitive data leaked in the error response body

---

#### Anti-pattern 7: Happy path asserts only status code

**File:** `spec/requests/api/v1/transactions_spec.rb` lines 35–40

```ruby
context 'with valid params' do
  it 'returns 201' do
    post '/api/v1/transactions', params: params, headers: headers
    expect(response).to have_http_status(:created)
  end
end
```

No response body fields, no DB assertions, no outbound API call assertions.

---

### Top 5 Priority Actions

1. **Fix the double-charge source bug and add a call-count test (GOUT-001/GFIN-001)** — The after_create callback at `app/models/transaction.rb:28` and the explicit service call at `app/services/transaction_service.rb:78` both invoke `PaymentGateway.charge` for payment-category transactions. This double-charges customers in production today. Add `expect(PaymentGateway).to have_received(:charge).once` in a payment happy-path test — it will immediately fail and expose the bug for remediation.

2. **Add full negative assertions to all existing error tests (GAPI-020/GDB-005)** — Five tests at transactions_spec.rb:42–93 assert only `have_http_status`. Each needs: `not_to change(Transaction, :count)`, `not_to have_received(:charge)`, and a body assertion that no sensitive data is leaked. This upgrades five weak tests to contract tests with a minimal diff.

3. **Add full happy-path response + DB + outbound assertions (GAPI-016, GDB-020/021/023/024/029/031, GOUT-002/005–008)** — Replace the single-line happy-path test with a test that parses the response body (all 9 fields), asserts DB postconditions (user_id, wallet_id, amount precision, currency, status='pending', category='transfer', wallet.balance decremented), and asserts PaymentGateway.charge NOT called for transfer category. This one test closes 15+ gaps.

4. **Add Authorization header scenarios and wallet status enum tests (GAPI-003, GDB-010/011)** — Add missing→401, malformed→401 for Authorization header, and suspended→422, closed→422 for wallet status. Six scenarios covering the authentication and access-control contracts that currently have zero coverage and represent the highest security regression risk.

5. **Add full payment-category test suite (GOUT-001–004)** — Add a payment-category context: stub success?=true and assert completed status + wallet debit + response body; stub success?=false and assert failed status; stub ChargeError and assert 422 + exact "Payment processing failed" + no completed state. The payment flow is entirely absent from the request spec despite being the endpoint's primary fintech-sensitive code path.
