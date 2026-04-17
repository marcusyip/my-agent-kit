# Unified Gap Analysis — POST /api/v1/transactions

## Test Structure Tree (unified)

```
POST /api/v1/transactions
│
├── ### API inbound
│   │
│   ├── request header: Authorization — PARTIAL
│   │   ├── ✗ missing token → 401, no DB write, no outbound API call, no data leak
│   │   ├── ✗ malformed token (e.g. "Bearer notarealjwt") → 401, no DB write, no data leak
│   │   ├── ✗ expired token → 401, no DB write, no data leak
│   │   └── ✗ token for deleted/disabled user → 401, no DB write, no data leak
│   │
│   ├── request field: transaction.amount — PARTIAL
│   │   ├── ✓ nil → 422 (transactions_spec.rb:42)  [status only; missing: no DB write / no outbound / no data leak assertions]
│   │   ├── ✓ negative (e.g. -100) → 422 (transactions_spec.rb:51)  [status only; missing: no DB write / no outbound / no data leak assertions]
│   │   ├── ✗ empty string "" → 422, no DB write, no outbound API call, no data leak
│   │   ├── ✗ whitespace-only " " → 422, no DB write, no outbound API call, no data leak
│   │   ├── ✗ zero "0" → 422 (not greater_than: 0), no DB write, no outbound API call, no data leak
│   │   ├── ✗ type violation: non-numeric string ("abc") → 422, no DB write, no data leak
│   │   ├── ✗ type violation: array / object → 422, no DB write, no data leak
│   │   ├── ✗ boundary: just-above-zero "0.00000001" (decimal(20,8) min unit) → 201 if balance sufficient
│   │   ├── ✗ boundary: exactly max 1_000_000 → 201
│   │   ├── ✗ boundary: just-over-max 1_000_000.00000001 → 422, no DB write, no data leak
│   │   ├── ✗ boundary: far-over-max 10_000_000 → 422, no DB write, no data leak
│   │   ├── ✗ precision: amount with 9 decimal places (exceeds scale:8) → document behavior (round/truncate/reject) + assert DB persists scale:8 only
│   │   ├── ✗ float trap: amount sent as JSON float (0.1+0.2 style) → assert decimal precision preserved
│   │   ├── ✗ cross-field: amount == wallet.balance → 201, wallet.balance becomes 0
│   │   ├── ✗ cross-field: amount > wallet.balance (overdraft) → 422, no DB write, no outbound API call, no balance leak in error
│   │   ├── ✗ cross-field: amount == wallet.balance + 0.00000001 (by 1 satoshi) → 422, no DB write, no data leak
│   │   └── ✗ concurrency: two concurrent requests where each amount <= balance but sum > balance → only one succeeds, balance never negative (TOCTOU)
│   │
│   ├── request field: transaction.currency — PARTIAL
│   │   ├── ✓ nil → 422 (transactions_spec.rb:60)  [status only; missing: no DB write / no data leak assertions]
│   │   ├── ✓ invalid value "ZZZ" → 422 (transactions_spec.rb:69)  [status only; missing: no DB write / no data leak assertions]
│   │   ├── ✗ empty string "" → 422, no DB write, no data leak
│   │   ├── ✗ whitespace-only " " → 422, no DB write, no data leak
│   │   ├── ✗ type violation: integer 123 → 422, no DB write, no data leak
│   │   ├── ✗ case sensitivity: "usd" (lowercase) → reject or normalize (assert contract behavior)
│   │   ├── ✗ leading/trailing whitespace: " USD " → reject or trim (assert contract behavior)
│   │   ├── ✗ enum value: USD → 201 (partial — baseline happy path at transactions_spec.rb:32 uses USD but asserts status only)
│   │   ├── ✗ enum value: EUR → 201, response currency == 'EUR'
│   │   ├── ✗ enum value: GBP → 201, response currency == 'GBP'
│   │   ├── ✗ enum value: BTC → 201, response currency == 'BTC'
│   │   ├── ✗ enum value: ETH → 201, response currency == 'ETH'
│   │   ├── ✗ injection: SQL payload "USD'; DROP TABLE" → 422 (not in enum), no DB write, no data leak
│   │   ├── ✗ injection: NULL byte "USD\0EUR" → 422, no DB write, no data leak
│   │   └── ✗ cross-field: request currency 'USD', wallet.currency 'EUR' (mismatch) → 422, no DB write, no outbound API call, no data leak
│   │
│   ├── request field: transaction.wallet_id — PARTIAL
│   │   ├── ✓ wallet does not exist (nonexistent id) → 422 (transactions_spec.rb:78)  [status only; missing: no DB write / no data leak assertions]
│   │   ├── ✗ nil → 422, no DB write, no data leak
│   │   ├── ✗ empty string "" → 422, no DB write, no data leak
│   │   ├── ✗ type violation: string "abc" → 422, no DB write, no data leak
│   │   ├── ✗ type violation: negative integer -1 → 422, no DB write, no data leak
│   │   ├── ✗ type violation: zero 0 → 422, no DB write, no data leak
│   │   ├── ✗ boundary: very large integer (2^63) → 422, no DB write, no data leak; no stack trace leak
│   │   ├── ✗ IDOR: wallet exists but belongs to another user → 422 (find_by scoped to current_user), no DB write, no data leak, response must NOT confirm other user's wallet exists
│   │   ├── ✗ injection: SQL payload in wallet_id "1 OR 1=1" → 422, no DB write, no data leak
│   │   └── ✗ cross-field: wallet.status = 'suspended' → 422, no DB write, no outbound API call, no data leak
│   │
│   ├── request field: transaction.description — NO TESTS
│   │   ├── ✗ omitted (optional) → 201, transaction.description == nil
│   │   ├── ✗ nil explicitly → 201, transaction.description == nil
│   │   ├── ✗ empty string "" → 201 or 422 (document contract), assert DB state matches
│   │   ├── ✗ whitespace-only " " → document contract (trim or persist as-is), assert DB state
│   │   ├── ✗ type violation: integer / array → 422, no DB write, no data leak
│   │   ├── ✗ boundary: exactly 500 chars → 201, persisted verbatim
│   │   ├── ✗ boundary: 501 chars → 422, no DB write, no data leak
│   │   ├── ✗ boundary: 10_000 chars → 422, no DB write, no data leak
│   │   ├── ✗ format: UTF-8 multi-byte chars (emoji, CJK) within 500-char limit → 201, persisted intact
│   │   ├── ✗ injection: SQL payload "'; DROP TABLE transactions; --" → 201, stored verbatim, NOT executed
│   │   ├── ✗ injection: XSS payload "<script>alert(1)</script>" → 201, stored verbatim (assert not rendered in any response path)
│   │   ├── ✗ injection: NULL byte "hello\0world" → 422 or stored (document contract)
│   │   └── ✗ injection: command injection "; rm -rf /" → 201, stored verbatim, no shell execution
│   │
│   ├── request field: transaction.category — NO TESTS
│   │   ├── ✗ omitted → 201, defaults to 'transfer', response.category == 'transfer', db.category == 'transfer'
│   │   ├── ✗ nil → 201, defaults to 'transfer' (document contract — or reject as invalid)
│   │   ├── ✗ empty string "" → 422, no DB write, no data leak
│   │   ├── ✗ type violation: integer 1 → 422, no DB write, no data leak
│   │   ├── ✗ enum value: 'transfer' → 201, balance decremented, NO PaymentGateway.charge call
│   │   ├── ✗ enum value: 'payment' → 201, PaymentGateway.charge invoked exactly once (guard against dual-call path), balance decremented
│   │   ├── ✗ enum value: 'deposit' → 201, wallet.balance NOT decremented (withdraw skipped per deduct_balance!)
│   │   ├── ✗ enum value: 'withdrawal' → 201, balance decremented
│   │   ├── ✗ invalid value 'refund' → 422, no DB write, no outbound API call, no data leak
│   │   ├── ✗ case sensitivity: 'PAYMENT' (uppercase) → reject or normalize (document contract)
│   │   ├── ✗ injection: SQL payload "payment'; DROP TABLE --" → 422, no DB write, no data leak
│   │   └── ✗ cross-field: category 'payment' + PaymentGateway.charge returns failure → 422, status 'failed' persisted, no balance change (or rollback semantics documented)
│   │
│   ├── response field: transaction.id — NO TESTS (happy-path assertion)
│   │   └── ✗ present on 201; integer type; non-nil; matches Transaction.last.id
│   │
│   ├── response field: transaction.amount — NO TESTS (happy-path assertion)
│   │   └── ✗ present on 201; decimal-as-string (via .to_s); value matches request.amount (e.g. "100.00000000"); not a JSON float
│   │
│   ├── response field: transaction.currency — NO TESTS (happy-path assertion)
│   │   └── ✗ present on 201; string; value matches request.currency exactly (including case)
│   │
│   ├── response field: transaction.status — NO TESTS (happy-path assertion)
│   │   ├── ✗ present on 201; string; one of pending/completed/failed/reversed
│   │   ├── ✗ for transfer/deposit/withdrawal: defaults to 'pending'
│   │   ├── ✗ for payment + gateway success: 'completed'
│   │   └── ✗ for payment + gateway failure: 'failed'
│   │
│   ├── response field: transaction.description — NO TESTS (happy-path assertion)
│   │   ├── ✗ present on 201 when provided; echoes input
│   │   └── ✗ nullability: when omitted, field present with null value (contract explicit — present vs. omitted)
│   │
│   ├── response field: transaction.category — NO TESTS (happy-path assertion)
│   │   ├── ✗ present on 201; string; one of transfer/payment/deposit/withdrawal
│   │   └── ✗ when omitted in request, response.category == 'transfer' (default)
│   │
│   ├── response field: transaction.wallet_id — NO TESTS (happy-path assertion)
│   │   └── ✗ present on 201; integer; matches request.wallet_id
│   │
│   ├── response field: transaction.created_at — NO TESTS (happy-path assertion)
│   │   ├── ✗ present on 201; ISO8601 format (via .iso8601)
│   │   └── ✗ string type (not raw Ruby Time object serialization), UTC offset present
│   │
│   ├── response field: transaction.updated_at — NO TESTS (happy-path assertion)
│   │   ├── ✗ present on 201; ISO8601 format (via .iso8601)
│   │   └── ✗ >= created_at
│   │
│   ├── response field: error (error envelope) — NO TESTS
│   │   ├── ✗ present on every 422 response; string; human-readable
│   │   ├── ✗ does NOT leak internal stack traces / SQL errors / class names
│   │   ├── ✗ for insufficient balance: error message is generic (no balance value in error string itself)
│   │   ├── ✗ for IDOR wallet (another user's wallet): error does NOT confirm wallet exists for another user
│   │   └── ✗ for payment gateway ChargeError: error == 'Payment processing failed' (exact match)
│   │
│   └── response field: details (error envelope) — NO TESTS
│       ├── ✗ present on 422; array of strings
│       ├── ✗ FINTECH SECURITY: for InsufficientBalanceError, details currently leak balance ("Current balance: X, requested: Y") — assert balance value is NOT present in details (remediation test)
│       ├── ✗ does NOT leak account numbers, user IDs, internal resource IDs
│       ├── ✗ does NOT leak SQL fragments or stack traces
│       └── ✗ empty array allowed vs. required — document contract
│
├── ### DB
│   │
│   ├── ── Preconditions (db field inputs — set in test setup) ──
│   │
│   ├── db field: wallet.status (input; enum: active/suspended/closed, NOT NULL) — NO TESTS
│   │   ├── ✗ active (happy path precondition) → 201 [PARTIAL: factory default assumed active, never explicitly set]
│   │   ├── ✗ suspended → 422, no transaction row inserted, no outbound call, no data leak
│   │   ├── ✗ closed → 422, no transaction row inserted, no outbound call, no data leak
│   │   └── ✗ concurrent wallet.update(status: 'suspended') between validation and withdraw! → must not process
│   │
│   ├── db field: wallet.balance (input; decimal(20,8), NOT NULL, DEFAULT 0) — NO TESTS
│   │   ├── ✗ balance > amount (happy path) → 201, balance decremented exactly by amount
│   │   ├── ✗ balance == amount (exact match boundary) → 201, balance becomes exactly 0.00000000
│   │   ├── ✗ balance == amount - 0.00000001 (just-under boundary) → 422, no DB write, no outbound call
│   │   ├── ✗ balance < amount (insufficient) → 422, balance unchanged, no transaction row, error details must NOT leak "Current balance: X"
│   │   ├── ✗ balance == 0 → 422
│   │   ├── ✗ balance precision: 8 decimal places preserved through check (e.g. 0.12345678 vs 0.12345679)
│   │   └── ✗ concurrent debit TOCTOU: two simultaneous requests each passing balance check — only one must succeed; final balance must not go negative
│   │
│   ├── db field: wallet.currency (input; string, NOT NULL) — NO TESTS
│   │   ├── ✗ wallet.currency == request.currency (happy path) → 201
│   │   ├── ✗ wallet.currency != request.currency (mismatch: wallet=USD, req=EUR) → 422, no DB write, no outbound call
│   │   ├── ✗ case sensitivity: wallet=USD vs request=usd → behavior asserted
│   │   └── ✗ each valid currency pairing: USD/USD, EUR/EUR, GBP/GBP, BTC/BTC, ETH/ETH — at minimum one non-USD pairing to prove currency is not hardcoded
│   │
│   ├── db field: wallet (existence precondition; FK target) — NO TESTS
│   │   ├── ✗ wallet missing (record does not exist for given wallet_id) → 422 [partial: covered as request field gap, not as DB precondition]
│   │   └── ✗ wallet belongs to different user (IDOR) → 422, no DB write, no outbound call, no data leak of other user's wallet attrs
│   │
│   ├── db field: user (existence precondition; FK target for transaction.user_id) — NO TESTS
│   │   └── ✗ current_user.id is used as transaction.user_id (verified via assertion branch below)
│   │
│   ├── ── Postconditions (db field assertions — verify after request) ──
│   │
│   ├── db field: transaction.user_id (assertion; integer, NOT NULL, FK → users.id) — NO TESTS
│   │   ├── ✗ happy path: transaction.user_id == current_user.id
│   │   ├── ✗ NOT NULL constraint: not bypassable (no code path creates transaction without user)
│   │   └── ✗ FK integrity: transaction is not created under a different user than the authenticated one
│   │
│   ├── db field: transaction.wallet_id (assertion; integer, NOT NULL, FK → wallets.id) — NO TESTS
│   │   ├── ✗ happy path: transaction.wallet_id == request.wallet_id == wallet.id
│   │   ├── ✗ NOT NULL constraint enforced
│   │   └── ✗ FK integrity: wallet_id references a wallet owned by the user
│   │
│   ├── db field: transaction.amount (assertion; decimal(20,8), NOT NULL) — NO TESTS
│   │   ├── ✗ happy path: transaction.amount == request.amount (BigDecimal equality, exact)
│   │   ├── ✗ precision preserved: input "0.12345678" persists as 0.12345678 (no truncation to 2dp)
│   │   ├── ✗ no float anti-pattern: no IEEE-754 drift when amount is "0.1" + "0.2"
│   │   ├── ✗ large amount: exactly 1_000_000.00000000 persists
│   │   └── ✗ NOT NULL enforced: no path creates a transaction with null amount
│   │
│   ├── db field: transaction.currency (assertion; string, NOT NULL, in USD/EUR/GBP/BTC/ETH) — NO TESTS
│   │   ├── ✗ happy path: transaction.currency == request.currency
│   │   ├── ✗ each enum value persists unchanged: USD, EUR, GBP, BTC, ETH
│   │   └── ✗ NOT NULL enforced
│   │
│   ├── db field: transaction.status (assertion; string, NOT NULL, DEFAULT 'pending', enum: pending/completed/failed/reversed) — NO TESTS
│   │   ├── ✗ DEFAULT 'pending' applied when category != 'payment' (transfer/withdrawal) → 201, db status == 'pending'
│   │   ├── ✗ pending → completed transition: category='payment' + PaymentGateway.charge.success? == true → db status == 'completed'
│   │   ├── ✗ pending → failed transition: category='payment' + PaymentGateway.charge.success? == false → db status == 'failed'
│   │   ├── ✗ pending → failed transition: category='payment' + ChargeError raised → db status == 'failed' OR rollback (contract currently ambiguous — must be tested and nailed down)
│   │   ├── ✗ terminal state 'reversed' never set by this endpoint (not reachable from create)
│   │   ├── ✗ invalid enum value at DB layer rejected (enum constraint enforced)
│   │   └── ✗ NOT NULL enforced
│   │
│   ├── db field: transaction.description (assertion; string, nullable, max 500) — NO TESTS
│   │   ├── ✗ happy path when provided: transaction.description == request.description
│   │   ├── ✗ happy path when omitted: transaction.description IS NULL (nullable default)
│   │   └── ✗ 500-char boundary: exactly 500 chars persists; 501 chars rejected (request-layer gap, DB should never hold >500)
│   │
│   ├── db field: transaction.category (assertion; string, NOT NULL, DEFAULT 'transfer', enum: transfer/payment/deposit/withdrawal) — NO TESTS
│   │   ├── ✗ DEFAULT 'transfer' applied when category omitted → db category == 'transfer'
│   │   ├── ✗ each enum value persists: transfer, payment, deposit, withdrawal
│   │   ├── ✗ invalid enum value rejected at DB layer
│   │   └── ✗ NOT NULL enforced
│   │
│   ├── db field: transaction.created_at (assertion; datetime, NOT NULL, auto) — NO TESTS
│   │   ├── ✗ auto-populated on insert (not nil)
│   │   └── ✗ within request wall-clock window (freeze time and assert exact value)
│   │
│   ├── db field: transaction.updated_at (assertion; datetime, NOT NULL, auto) — NO TESTS
│   │   ├── ✗ auto-populated on insert (not nil)
│   │   ├── ✗ equals created_at on insert (happy path, no subsequent update)
│   │   └── ✗ monotonic on status transition: payment category path updates status pending→completed/failed → updated_at > created_at
│   │
│   ├── db field: wallet.balance (assertion — post-state; decimal(20,8), NOT NULL) — NO TESTS
│   │   ├── ✗ non-deposit path (transfer/payment/withdrawal): wallet.balance == initial_balance - request.amount (exact BigDecimal)
│   │   ├── ✗ deposit category: wallet.balance UNCHANGED (current code does not credit on deposit — contract gap also, but behavior must be locked)
│   │   ├── ✗ exact-match debit: initial_balance == amount → final balance == 0.00000000 (not negative, not 1e-9)
│   │   ├── ✗ rollback on PaymentGateway ChargeError: if charge raises after withdraw!, balance state is consistent (either restored or transaction marked failed with explicit accounting)
│   │   ├── ✗ concurrent debit: two requests each debiting half the balance simultaneously — final balance == initial - 2*amount (or one rejected); never negative
│   │   └── ✗ precision: decrement preserves 8 decimal places
│   │
│   └── db field: transaction row presence (assertion; overall row insertion) — NO TESTS
│       ├── ✗ happy path: Transaction.count changes by +1
│       ├── ✗ every 422 error path: Transaction.count unchanged (assert via `expect { run_test }.not_to change(Transaction, :count)`)
│       └── ✗ PaymentGateway ChargeError path: Transaction row state at end is consistent with status field (row exists but marked failed, OR row does not exist — contract must pick one)
│
└── ### Outbound API
    │
    ├── outbound response field: PaymentGateway.charge.success? (input — mock return) — NO TESTS
    │   ├── ✗ success? returns true (category='payment') → 201, db transaction.status='completed', wallet.balance decremented, response transaction.status='completed'
    │   ├── ✗ success? returns false (category='payment') → 422 or transaction.status='failed', no wallet.balance change beyond what service flow did, no data leak
    │   ├── ✗ success? returns non-boolean truthy (e.g. "yes", 1, {}) → must not silently coerce to completed; assert system behavior (accept or reject)
    │   ├── ✗ success? returns nil → transaction.status not left in inconsistent 'pending', no data leak
    │   ├── ✗ upstream response object is nil → NoMethodError not leaked in 500; controller returns 422 or handles gracefully
    │   ├── ✗ upstream response missing .success? method (wrong shape) → not silently passes; 422 with generic error
    │   ├── ✗ partial response: success?=true but no transaction reference/id field parsed → flag as reconciliation gap (source does not parse reference today)
    │   └── ✗ upstream amount/currency mismatch in response (if parsed) — source does not parse; flag as gap [FINTECH]
    │
    ├── outbound response field: PaymentGateway::ChargeError (input — mock raises) — NO TESTS
    │   ├── ✗ ChargeError raised (category='payment') → 422, response error='Payment processing failed', no completed status in DB, no data leak
    │   ├── ✗ ChargeError raised → db transaction.status NOT 'completed' (stays 'pending' or set to 'failed' per service flow)
    │   ├── ✗ ChargeError raised → wallet.balance side effects consistent with service flow (no orphan debit)
    │   └── ✗ ChargeError raised → response body does not leak gateway internals / stack trace
    │
    ├── outbound response field: timeout / network error (input — mock raises Timeout::Error, Net::ReadTimeout, etc.) — NO TESTS
    │   └── ✗ timeout/network error NOT modeled in source; no rescue beyond ChargeError → unhandled exception escapes to 500, leaking class name; assert explicit handling or flag as GAP [FINTECH HIGH]
    │
    ├── outbound request field: amount (assertion — must be sent correctly) — NO TESTS
    │   ├── ✗ called with amount equal to transaction.amount (BigDecimal/decimal, not string) — happy path payment category
    │   ├── ✗ called with correct amount when amount has fractional scale (e.g. 10.12345678) — precision preserved
    │   └── ✗ type correctness: amount argument is Decimal/BigDecimal, not String coerced from params
    │
    ├── outbound request field: currency (assertion — must be sent correctly) — NO TESTS
    │   └── ✗ called with currency equal to transaction.currency — happy path payment category
    │
    ├── outbound request field: user_id (assertion — must be sent correctly) — NO TESTS
    │   └── ✗ called with user_id equal to current_user.id (not params-forgeable) — happy path payment category
    │
    ├── outbound request field: transaction_id (assertion — must be sent correctly) — NO TESTS
    │   ├── ✗ called with transaction_id equal to the created Transaction.id — happy path payment category
    │   └── ✗ transaction_id references a persisted row (transaction.id is not nil — charge happens after create)
    │
    ├── outbound call-count: invoked exactly ONCE on payment category — NO TESTS [FINTECH CRITICAL]
    │   ├── ✗ category='payment' happy path → PaymentGateway.charge received exactly 1 time (NOT 2)
    │   └── ✗ source has dual call paths (TransactionService#charge_payment_gateway line 78 + Transaction#notify_payment_gateway after_create line 28) — double-charge risk; test must pin call count to 1
    │
    ├── outbound call-count: invoked ZERO times on non-payment categories — NO TESTS
    │   ├── ✗ category='transfer' → PaymentGateway.charge NOT called
    │   ├── ✗ category='deposit' → PaymentGateway.charge NOT called
    │   ├── ✗ category='withdrawal' → PaymentGateway.charge NOT called
    │   └── ✗ category omitted (defaults to 'transfer') → PaymentGateway.charge NOT called
    │
    ├── outbound call-count: invoked ZERO times when request validation fails — NO TESTS
    │   ├── ✗ amount nil (422) → PaymentGateway.charge NOT called
    │   ├── ✗ amount negative / zero / >max / non-numeric (422) → PaymentGateway.charge NOT called
    │   ├── ✗ currency nil / invalid / empty (422) → PaymentGateway.charge NOT called
    │   ├── ✗ wallet_id not found / foreign wallet (422) → PaymentGateway.charge NOT called
    │   ├── ✗ description > 500 chars (422) → PaymentGateway.charge NOT called
    │   ├── ✗ category invalid (422) → PaymentGateway.charge NOT called
    │   ├── ✗ wallet.status = suspended/closed (422) → PaymentGateway.charge NOT called
    │   ├── ✗ wallet.currency mismatch (422) → PaymentGateway.charge NOT called
    │   ├── ✗ wallet.balance insufficient (422) → PaymentGateway.charge NOT called
    │   └── ✗ Authorization header missing (401) → PaymentGateway.charge NOT called
    │
    └── outbound call: idempotency key (assertion) — NO TESTS [FINTECH HIGH]
        └── ✗ PaymentGateway.charge does NOT receive an idempotency key today — source does not pass one; flag as gap; retries/duplicates may double-charge upstream
```

---

## Contract Map (unified)

| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
|---|---|---|---|---|---|
| request header | Authorization | Input | missing, malformed, expired, wrong-user | 0 | 4 |
| request field | transaction.amount | Input | nil, empty string, whitespace-only, zero, negative, non-numeric, wrong type, min-unit (0.00000001), exactly-max (1_000_000), just-over-max, far-over-max, precision >scale 8, float-trap, amount==balance, amount>balance, amount==balance+1sat, concurrent TOCTOU | nil, negative (status only) | 15 (2 PARTIAL upgrade) |
| request field | transaction.currency | Input | nil, empty string, whitespace-only, wrong type, lowercase, leading/trailing whitespace, USD, EUR, GBP, BTC, ETH, SQL injection, NULL byte, wallet currency mismatch | nil, invalid (status only); USD baseline (status only) | 12 (3 PARTIAL upgrade) |
| request field | transaction.wallet_id | Input | nil, empty string, wrong type (string/negative/zero), very-large int, nonexistent id, IDOR other-user wallet, SQL injection, wallet.status suspended cross-field | nonexistent id (status only) | 9 (1 PARTIAL upgrade) |
| request field | transaction.description | Input | omitted, nil, empty, whitespace, wrong type, exactly 500 chars, 501 chars, 10_000 chars, UTF-8 multibyte, SQL injection, XSS, NULL byte, command injection | 0 | 13 |
| request field | transaction.category | Input | omitted (default), nil, empty, wrong type, transfer, payment, deposit, withdrawal, invalid, case sensitivity, SQL injection, payment+gateway-failure cross-field | 0 | 12 |
| response field | transaction.id | Assertion | presence, integer type, matches DB | 0 | 1 |
| response field | transaction.amount | Assertion | presence, decimal-as-string format, value correctness | 0 | 1 |
| response field | transaction.currency | Assertion | presence, value matches input | 0 | 1 |
| response field | transaction.status | Assertion | presence, enum value correctness per category + gateway outcome | 0 | 1 |
| response field | transaction.description | Assertion | presence, nullability (omitted case) | 0 | 1 |
| response field | transaction.category | Assertion | presence, default value when omitted | 0 | 1 |
| response field | transaction.wallet_id | Assertion | presence, matches request | 0 | 1 |
| response field | transaction.created_at | Assertion | presence, ISO8601 format, string type | 0 | 1 |
| response field | transaction.updated_at | Assertion | presence, ISO8601 format, >= created_at | 0 | 1 |
| response field | error | Assertion | presence on 422, human-readable, no stack trace leak, no balance leak, IDOR non-disclosure, ChargeError exact message | 0 | 1 |
| response field | details | Assertion | presence on 422, array type, FINTECH no balance leak, no account/user leak, no SQL leak | 0 | 1 |
| db field (input) | wallet.status | Input (enum: active/suspended/closed) | 4 (3 enum values + concurrent mutation) | 0 | 4 |
| db field (input) | wallet.balance | Input (boundary + concurrency) | 7 (>,==,just-under,<,zero,precision,TOCTOU) | 0 | 7 |
| db field (input) | wallet.currency | Input (match/mismatch + enum pairings) | 4 (match, mismatch, case, non-USD pairing) | 0 | 4 |
| db field (input) | wallet (record exists) | Input (FK precondition) | 2 (missing, IDOR other-user) | 0 (missing is a request-field gap) | 2 |
| db field (assertion) | transaction.user_id | Assertion (NOT NULL, FK) | 3 (value, NOT NULL, FK integrity) | 0 | 3 |
| db field (assertion) | transaction.wallet_id | Assertion (NOT NULL, FK) | 3 | 0 | 3 |
| db field (assertion) | transaction.amount | Assertion (decimal precision, NOT NULL) | 5 (value, precision, no-float, max, NOT NULL) | 0 | 5 |
| db field (assertion) | transaction.currency | Assertion (NOT NULL, enum) | 3 (value, enum persists, NOT NULL) | 0 | 3 |
| db field (assertion) | transaction.status | Assertion (DEFAULT, enum, state machine) | 7 (default pending, pending→completed, pending→failed via success?=false, pending→failed via ChargeError, reversed unreachable, invalid enum, NOT NULL) | 0 | 7 |
| db field (assertion) | transaction.description | Assertion (nullable, max 500) | 3 (provided, omitted→nil, boundary) | 0 | 3 |
| db field (assertion) | transaction.category | Assertion (DEFAULT 'transfer', enum, NOT NULL) | 4 (default applied, each enum persists, invalid rejected, NOT NULL) | 0 | 4 |
| db field (assertion) | transaction.created_at | Assertion (auto, NOT NULL) | 2 (present, within request window) | 0 | 2 |
| db field (assertion) | transaction.updated_at | Assertion (auto, monotonic) | 3 (present, == created_at on insert, monotonic on transition) | 0 | 3 |
| db field (assertion) | wallet.balance (post-state) | Assertion (side-effect, concurrency, rollback) | 6 (non-deposit decrement, deposit unchanged, exact-match, rollback on ChargeError, concurrent debit, precision) | 0 | 6 |
| db field (assertion) | transaction row presence | Assertion (count-delta on happy + error paths) | 3 (happy +1, 422 unchanged, ChargeError path consistency) | 0 | 3 |
| outbound response field | PaymentGateway.charge.success? | Input (mock return) | 8 (true, false, non-bool truthy, nil, nil response, missing method, partial/no reference, amount/currency mismatch) | 0 | 8 |
| outbound response field | PaymentGateway::ChargeError | Input (mock raises) | 4 (response body, db status, wallet side effect, no leak) | 0 | 4 |
| outbound response field | timeout / network error | Input (mock raises) | 1 (unhandled — flag source gap) | 0 | 1 |
| outbound request field | amount | Assertion | 3 (value match, fractional precision, type Decimal not String) | 0 | 3 |
| outbound request field | currency | Assertion | 1 (value match) | 0 | 1 |
| outbound request field | user_id | Assertion | 1 (value match current_user.id) | 0 | 1 |
| outbound request field | transaction_id | Assertion | 2 (value match, references persisted row) | 0 | 2 |
| outbound call-count | exactly once on payment | Assertion | 1 (CRITICAL — double-charge risk from dual call paths) | 0 | 1 |
| outbound call-count | zero on non-payment categories | Assertion | 4 (transfer, deposit, withdrawal, default) | 0 | 4 |
| outbound call-count | zero on validation failure | Assertion | 10 (all 422/401 scenarios) | 0 | 10 |
| outbound call | idempotency key | Assertion | 1 (absent in source — flag) | 0 | 1 |

---

## Gap Analysis by Priority

### CRITICAL

- **GAPI-001** — `response field: details` — **API inbound**
  - Priority: CRITICAL
  - Description: Error response `details` array currently includes raw balance in the InsufficientBalanceError path (`"Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"`). No test asserts that sensitive financial data is NOT leaked in error responses. This is a FINTECH security gap — error-path contract must forbid balance disclosure. (merged from GAPI-001 + GFIN-005)
  - Stub: REQUIRED

- **GAPI-002** — `request field: transaction.wallet_id` (IDOR) — **API inbound**
  - Priority: CRITICAL
  - Description: No test exercises the IDOR scenario — a valid wallet_id belonging to a different user. Controller uses `current_user.wallets.find_by(...)` which should return 422, but without a test any future refactor (e.g. to `Wallet.find_by`) would silently permit cross-tenant writes. Must also assert the error response does NOT leak that the wallet exists for another user.
  - Stub: REQUIRED

- **GAPI-003** — `request header: Authorization` — **API inbound**
  - Priority: CRITICAL
  - Description: Zero coverage of any 401 path. Missing token, malformed token, expired token, and token for disabled user all unenforced in tests. Without these, a regression in `authenticate_user!` could expose transactions endpoint to the public. (merged from GAPI-003 + GFIN-015)
  - Stub: REQUIRED

- **GDB-001 / GFIN-003** — `db field (input): wallet.balance` (concurrent debit TOCTOU) — **DB / Fintech:Concurrency**
  - Priority: CRITICAL
  - Description: Concurrent debit TOCTOU. `TransactionService#validate_sufficient_balance!` reads balance outside the `with_lock` used by `wallet.withdraw!`. Two concurrent requests can each pass the check and both withdraw, driving balance negative. Balance check must be INSIDE `with_lock` or the flow should use atomic `UPDATE wallets SET balance = balance - ? WHERE balance >= ?`. No test exercises this race. (merged from GDB-001 + GFIN-003)
  - Stub: REQUIRED

- **GDB-002 / GFIN-002** — `db field (assertion): wallet.balance (post-state, rollback)` — **DB / Fintech:BalanceLedger**
  - Priority: CRITICAL
  - Description: On `PaymentGateway::ChargeError`, the service rescues and returns 422, but `wallet.withdraw!` already ran (or not, depending on order). No DB transaction wraps `save! → withdraw! → charge → update!`. No compensating rollback is executed — real money is lost from the wallet view. Money-safety invariant: balance MUST match sum of non-failed transactions. (merged from GDB-002 + GFIN-002)
  - Stub: REQUIRED

- **GDB-003** — `db field (assertion): transaction.status` (state machine) — **DB**
  - Priority: CRITICAL
  - Description: pending → completed and pending → failed transitions are entirely untested. State machine contract is undefended — a code change that leaves every payment stuck in 'pending' would ship green. Each valid transition (including the ChargeError path) must be asserted at the DB layer.
  - Stub: REQUIRED

- **GDB-004** — `db field (assertion): wallet.balance` (deposit category) — **DB**
  - Priority: CRITICAL
  - Description: `deduct_balance!` skips `wallet.withdraw!` for `deposit` category, and no `wallet.deposit!` call is made. The current contract is "deposit does nothing to balance" — this is probably a bug, but must be locked by an explicit test so any future fix is caught. Absent a test, either behavior ships silently.
  - Stub: REQUIRED

- **GDB-005** — `db field (assertion): transaction row presence on error paths` — **DB**
  - Priority: CRITICAL
  - Description: Every 422 error scenario (invalid amount, invalid currency, suspended wallet, insufficient balance, currency mismatch, ChargeError) must assert `Transaction.count` unchanged. Current tests assert only status code — a regression that inserts a 'pending' orphan transaction on validation failure would ship green.
  - Stub: REQUIRED

- **GOUT-001 / GFIN-001** — `outbound call-count: PaymentGateway.charge` exactly once per payment transaction — **Outbound API / Fintech:ExternalIntegration**
  - Priority: CRITICAL
  - Description: Source has TWO call paths to `PaymentGateway.charge`: `TransactionService#charge_payment_gateway` (line 78) and `Transaction#notify_payment_gateway` after_create callback (model line 28). For `category='payment'`, the gateway is charged twice per request — customers are double-charged. Only the service-path result is recorded to `transaction.status`. No test pins the call count to exactly 1. Must assert `have_received(:charge).once` on happy path with category='payment'. (merged from GOUT-001 + GFIN-001)
  - Stub: REQUIRED

### HIGH

- **GAPI-004** — `request field: transaction.amount` (overdraft / amount>balance) — **API inbound**
  - Priority: HIGH
  - Description: No test submits an amount larger than wallet.balance. Must assert 422, zero DB writes, no PaymentGateway.charge call, and no balance value in error body (ties to GAPI-001).
  - Stub: REQUIRED

- **GAPI-005** — `request field: transaction.amount` (exact balance boundary) — **API inbound**
  - Priority: HIGH
  - Description: No test submits amount == wallet.balance. This is the critical boundary where the account should drain to exactly zero. Must assert 201 and final wallet.balance == 0.
  - Stub: REQUIRED

- **GAPI-006** — `request field: transaction.amount` (just-over-max 1_000_000) — **API inbound**
  - Priority: HIGH
  - Description: No boundary test at the regulatory limit. `less_than_or_equal_to: 1_000_000` means exactly 1_000_000 should succeed, 1_000_000.00000001 must reject. Neither covered.
  - Stub: REQUIRED

- **GAPI-007** — `request field: transaction.amount` (zero) — **API inbound**
  - Priority: HIGH
  - Description: No test for amount=0. `numericality greater_than: 0` means zero must be rejected with 422. Currently untested; a change to `>= 0` would pass silently.
  - Stub: REQUIRED

- **GAPI-008** — `request field: transaction.amount` (non-numeric string) — **API inbound**
  - Priority: HIGH
  - Description: No test submits "abc" or other non-numeric string. BigDecimal coercion behavior on junk input is undefined without a test pinning it.
  - Stub: REQUIRED

- **GAPI-009** — `request field: transaction.amount` (precision >scale:8) — **API inbound**
  - Priority: HIGH
  - Description: No test submits amount with 9+ decimal places. DB schema is `decimal(20,8)`; the system must either round, truncate, or reject — pin the behavior with a test.
  - Stub: REQUIRED

- **GAPI-010** — `request field: transaction.currency` (cross-field wallet mismatch) — **API inbound**
  - Priority: HIGH
  - Description: No test where request currency does not match wallet currency. `validate_currency_match!` is untested through the endpoint. Must assert 422, no DB write, no outbound call.
  - Stub: REQUIRED

- **GAPI-011** — `request field: transaction.currency` (per-enum coverage) — **API inbound**
  - Priority: HIGH
  - Description: Only USD is exercised (and only for status code). EUR, GBP, BTC, ETH each need their own happy-path test with matching wallet currency and response assertion.
  - Stub: REQUIRED

- **GAPI-012** — `request field: transaction.category` (every enum value) — **API inbound**
  - Priority: HIGH
  - Description: Zero coverage for category field. Each enum value drives different code paths: 'payment' triggers PaymentGateway.charge, 'deposit' skips balance deduction. Each enum must be its own test.
  - Stub: REQUIRED

- **GAPI-013** — `request field: transaction.category` (default 'transfer') — **API inbound**
  - Priority: HIGH
  - Description: No test confirms that omitting category results in 'transfer'. `TransactionService#build_transaction` default is untested.
  - Stub: REQUIRED

- **GAPI-014** — `request field: transaction.category` (invalid value) — **API inbound**
  - Priority: HIGH
  - Description: No test for an invalid category value (e.g. 'refund'). Must return 422 with no DB write and no outbound call.
  - Stub: REQUIRED

- **GAPI-015** — `request field: transaction.description` (length boundary) — **API inbound**
  - Priority: HIGH
  - Description: No test for description field at all. Needs boundary tests at 500 chars (accepted) and 501 chars (422) to guard the `length maximum: 500` validation.
  - Stub: REQUIRED

- **GAPI-016** — `response field: transaction.id / amount / currency / status / wallet_id / category / description / created_at / updated_at` — **API inbound**
  - Priority: HIGH
  - Description: Happy path at transactions_spec.rb:35-40 asserts only status 201 — response body is never parsed. Every response field needs value + type + format assertions. amount must be asserted as decimal-as-string; created_at/updated_at as ISO8601.
  - Stub: REQUIRED

- **GAPI-017** — `response field: error` on 422 paths — **API inbound**
  - Priority: HIGH
  - Description: No error-body assertions in any error test. Each 422 must assert error string is present, human-readable, and free of SQL/stack trace content. ChargeError path must assert exact 'Payment processing failed' message.
  - Stub: REQUIRED

- **GAPI-018** — `request field: transaction.currency` (empty string) — **API inbound**
  - Priority: HIGH
  - Description: nil is covered but empty string "" is not. These take separate controller validation paths.
  - Stub: REQUIRED

- **GAPI-019** — `request field: transaction.wallet_id` (nil) — **API inbound**
  - Priority: HIGH
  - Description: No test for nil wallet_id — the `find_by(id: nil)` path.
  - Stub: REQUIRED

- **GAPI-020** — Existing error tests assert status code only — **API inbound**
  - Priority: HIGH
  - Description: transactions_spec.rb:42, 51, 60, 69, 78 assert only `have_http_status(:unprocessable_entity)`. None assert no DB record created (`expect { run_test }.not_to change(Transaction, :count)`), no PaymentGateway.charge call, and no data leak in body. Upgrade existing PARTIAL tests.
  - Stub: REQUIRED

- **GDB-010** — `db field (input): wallet.status = 'suspended'` — **DB**
  - Priority: HIGH
  - Description: No test creates a wallet with `status: 'suspended'` and asserts 422 + no transaction row + no outbound call. Enum value coverage gap.
  - Stub: REQUIRED

- **GDB-011** — `db field (input): wallet.status = 'closed'` — **DB**
  - Priority: HIGH
  - Description: Same as GDB-010 but for `closed` status.
  - Stub: REQUIRED

- **GDB-012** — `db field (input): wallet.balance` — exact-match boundary — **DB**
  - Priority: HIGH
  - Description: `amount == balance` must succeed and leave balance at exactly 0.00000000. Untested. This is where precision/off-by-one bugs hide.
  - Stub: REQUIRED

- **GDB-013** — `db field (input): wallet.balance` — insufficient — **DB**
  - Priority: HIGH
  - Description: `amount > balance` must 422 and leave balance unchanged + no transaction row. Untested at the boundary level.
  - Stub: REQUIRED

- **GDB-014** — `db field (input): wallet.currency mismatch` — **DB**
  - Priority: HIGH
  - Description: `wallet.currency == 'USD'`, request currency = 'EUR' must 422, no DB write, no outbound call. Factory pins both to USD today.
  - Stub: REQUIRED

- **GDB-015** — `db field (input): wallet ownership (IDOR)` — **DB**
  - Priority: HIGH
  - Description: Request with `wallet_id` belonging to a different user must 422, no DB write, no outbound call, and error response must NOT leak the other user's wallet attributes. Untested.
  - Stub: REQUIRED

- **GDB-020** — `db field (assertion): transaction.user_id` — **DB**
  - Priority: HIGH
  - Description: Happy path never asserts `transaction.user_id == current_user.id`. A regression that pins user_id to the first admin would ship green.
  - Stub: REQUIRED

- **GDB-021** — `db field (assertion): transaction.wallet_id` — **DB**
  - Priority: HIGH
  - Description: Happy path never asserts `transaction.wallet_id == request.wallet_id`. Untested FK value.
  - Stub: REQUIRED

- **GDB-022** — `db field (assertion): transaction.amount precision` — **DB**
  - Priority: HIGH
  - Description: With `decimal(20,8)`, an input of `"0.12345678"` must persist exactly as 0.12345678. No precision assertion exists. Float drift or to_f truncation would ship green.
  - Stub: REQUIRED

- **GDB-023** — `db field (assertion): transaction.currency value` — **DB**
  - Priority: HIGH
  - Description: No test asserts `transaction.currency == request.currency` at the DB layer.
  - Stub: REQUIRED

- **GDB-024** — `db field (assertion): transaction.status DEFAULT 'pending'` — **DB**
  - Priority: HIGH
  - Description: For category=transfer (default), transaction.status must be 'pending' post-create (no PaymentGateway triggered). Untested.
  - Stub: REQUIRED

- **GDB-025** — `db field (assertion): transaction.status pending → completed transition` — **DB**
  - Priority: HIGH
  - Description: category='payment' + mocked `PaymentGateway.charge` returning `success?: true` must leave `transaction.status == 'completed'` in DB. Untested.
  - Stub: REQUIRED

- **GDB-026** — `db field (assertion): transaction.status pending → failed transition (success?=false)` — **DB**
  - Priority: HIGH
  - Description: category='payment' + mocked `PaymentGateway.charge` returning `success?: false` must leave `transaction.status == 'failed'` in DB. Untested.
  - Stub: REQUIRED

- **GDB-027** — `db field (assertion): transaction.status pending → failed transition (ChargeError)` — **DB**
  - Priority: HIGH
  - Description: category='payment' + mocked `PaymentGateway.charge` raising `ChargeError` must leave DB in a consistent state: either no transaction row OR transaction row with status 'failed'. Contract currently unspecified — nail it down.
  - Stub: REQUIRED

- **GDB-028** — `db field (assertion): transaction.description provided + omitted` — **DB**
  - Priority: HIGH
  - Description: Provided description must persist verbatim; omitted must persist as NULL (not empty string). Untested.
  - Stub: REQUIRED

- **GDB-029** — `db field (assertion): transaction.category DEFAULT 'transfer'` — **DB**
  - Priority: HIGH
  - Description: When `category` omitted in request, DB row must have `category == 'transfer'`. Untested.
  - Stub: REQUIRED

- **GDB-030** — `db field (assertion): transaction.category each enum value persists` — **DB**
  - Priority: HIGH
  - Description: Each of `transfer`, `payment`, `deposit`, `withdrawal` must persist to DB unchanged. Untested for all four.
  - Stub: REQUIRED

- **GDB-031** — `db field (assertion): wallet.balance decremented on non-deposit` — **DB**
  - Priority: HIGH
  - Description: Post-create, `wallet.balance` must equal `initial_balance - request.amount` exactly. Untested — this is the core ledger invariant.
  - Stub: REQUIRED

- **GOUT-002** — `outbound response field: PaymentGateway.charge.success?` (input=true) → completion flow — **Outbound API**
  - Priority: HIGH
  - Description: No test stubs `PaymentGateway.charge` to return `double(success?: true)` on a `category='payment'` request and asserts the downstream contract: (1) response 201, (2) db `transaction.status == 'completed'`, (3) response body `transaction.status == 'completed'`, (4) wallet.balance decremented once. This is the core happy path for the payment branch and it is entirely absent from the request spec.
  - Stub: REQUIRED

- **GOUT-003** — `outbound response field: PaymentGateway.charge.success?` (input=false) → transaction.status='failed' — **Outbound API**
  - Priority: HIGH
  - Description: No test stubs gateway to return `double(success?: false)` on payment category. Must assert: response status (422 or 201 per contract — pin current behavior), db `transaction.status == 'failed'` (per TransactionService flow), no data leak in error body.
  - Stub: REQUIRED

- **GOUT-004** — `outbound response field: PaymentGateway::ChargeError` → 422 + "Payment processing failed" + no completed state — **Outbound API**
  - Priority: HIGH
  - Description: No test raises `PaymentGateway::ChargeError` from the mock. Must assert: (1) response 422, (2) response error message equals `"Payment processing failed"` (per source), (3) db `transaction.status != 'completed'`, (4) no gateway internals/stack trace leaked in body.
  - Stub: REQUIRED

- **GOUT-005** — `outbound request field: amount` sent correctly — **Outbound API**
  - Priority: HIGH
  - Description: No test verifies the amount argument sent to `PaymentGateway.charge`. Must assert `have_received(:charge).with(hash_including(amount: BigDecimal('100.00')))` on payment happy path. Fractional-scale variant also missing (e.g. `10.12345678`).
  - Stub: REQUIRED

- **GOUT-006** — `outbound request field: currency` sent correctly — **Outbound API**
  - Priority: HIGH
  - Description: No test verifies the currency argument sent to `PaymentGateway.charge`. Must assert `have_received(:charge).with(hash_including(currency: 'USD'))` (or whatever default) on payment happy path.
  - Stub: REQUIRED

- **GOUT-007** — `outbound request field: user_id` sent correctly (not forgeable) — **Outbound API**
  - Priority: HIGH
  - Description: No test verifies user_id is taken from `current_user.id` (authenticated identity), not from params. Must assert `have_received(:charge).with(hash_including(user_id: user.id))`.
  - Stub: REQUIRED

- **GOUT-008** — `outbound request field: transaction_id` sent correctly (references persisted row) — **Outbound API**
  - Priority: HIGH
  - Description: No test verifies that the transaction_id sent to the gateway matches the id of the Transaction row just created (non-nil — persisted before call). Must assert `have_received(:charge).with(hash_including(transaction_id: Transaction.last.id))`.
  - Stub: REQUIRED

- **GOUT-009** — `outbound call-count: zero on non-payment categories` — **Outbound API**
  - Priority: HIGH
  - Description: No test asserts that `category='transfer' | 'deposit' | 'withdrawal' | omitted` does NOT invoke `PaymentGateway.charge`. Without this, a regression that extends the gateway call to all categories would pass silently.
  - Stub: REQUIRED

- **GOUT-010** — `outbound call-count: zero on validation failures (422 / 401)` — **Outbound API**
  - Priority: HIGH
  - Description: No error-scenario test asserts `expect(PaymentGateway).not_to have_received(:charge)`. Every 422/401 path (amount invalid, currency invalid, wallet not found, wallet suspended/closed, insufficient balance, currency mismatch, description too long, missing auth) should assert no outbound call.
  - Stub: REQUIRED

- **GOUT-011 / GFIN-004** — `outbound call: idempotency key` absent on outbound charge — **Outbound API / Fintech:Idempotency**
  - Priority: HIGH
  - Description: `PaymentGateway.charge` is called with NO idempotency key (e.g. `idempotency_key: transaction.id.to_s`). No `Idempotency-Key` / `X-Idempotency-Key` header is read by controller; no `idempotency_key` / `client_reference_id` column on `transactions`; no unique index. A retried HTTP POST (network blip, client retry, double-clicked submit, NAT/load-balancer retransmit) creates duplicate transactions AND duplicate debits AND duplicate gateway charges. Source-level gap — add the column + header + key, then test it is passed consistently and stable per transaction. (merged from GOUT-011 + GFIN-004)
  - Stub: REQUIRED

- **GOUT-012** — `outbound response field: timeout / network error` handling missing in source — **Outbound API / Fintech**
  - Priority: HIGH
  - Description: Source only rescues `PaymentGateway::ChargeError`. `Timeout::Error`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, SocketError are not rescued — they bubble to a 500 and leak exception class names. Source-level gap; test must either lock current behavior (500) or drive a fix to graceful 422/503 and then pin.
  - Stub: REQUIRED

- **GFIN-006** — `db field: transaction.status` invalid-transition guards — **Fintech:StateMachine**
  - Priority: HIGH
  - Description: No guard on invalid transitions (`completed → pending`, `failed → completed`, `reversed → *`). Rails enum alone does not enforce transition validity. Terminal state `reversed` lacks a guard to prevent `pending → reversed → pending` replay.
  - Stub: REQUIRED

- **GFIN-007** — Stuck-`pending` detection absent — **Fintech:StateMachine**
  - Priority: HIGH
  - Description: On exception between `withdraw!` and `update!`, the row stays `pending` with wallet already debited and no reconciliation sweeper / stuck-state detection. Couples with GDB-002/GFIN-002; must be tested independently to ensure orphan `pending` rows aren't created when the pipeline faults.
  - Stub: REQUIRED

- **GFIN-008** — No rate limiting on `POST /api/v1/transactions` — **Fintech:Security**
  - Priority: HIGH
  - Description: No Rack::Attack, throttle middleware, or per-user request budget on the money-mutating endpoint. A compromised token can drain a wallet at HTTP speed. Rate limiting is a must-have control on money-mutating endpoints.
  - Stub: REQUIRED

- **GFIN-009** — No reconciliation field (external gateway reference) — **Fintech:ExternalIntegration**
  - Priority: HIGH
  - Description: `PaymentGateway.charge` response is not parsed for an external reference (`gateway_transaction_id`/`charge_id`/`provider_reference`). Without an external handle, a later reconciliation job cannot map local rows to gateway records. Source-level gap — add column, persist after successful charge, test happy path persists a non-nil reference.
  - Stub: REQUIRED

- **GFIN-010** — No retry/backoff on transient gateway failures — **Fintech:ExternalIntegration**
  - Priority: HIGH
  - Description: Every 5xx/timeout becomes immediate `failed` with wallet debited (couples to GFIN-002). No exponential backoff, no retry budget, no dead-letter handling.
  - Stub: REQUIRED

### MEDIUM

- **GAPI-021** — `request field: transaction.description` (injection payloads) — **API inbound**
  - Priority: MEDIUM
  - Description: description is a free-text string persisted to DB. SQL injection, XSS, command injection, NULL-byte payloads should all be stored verbatim (not executed). No tests assert this.
  - Stub: not required

- **GAPI-022** — `request field: transaction.currency` (case sensitivity, whitespace) — **API inbound**
  - Priority: MEDIUM
  - Description: Document contract behavior on "usd" (lowercase) and " USD " (padded). Likely rejected (enum exact-match), but untested.
  - Stub: not required

- **GAPI-023** — `request field: transaction.amount` (type violations: array, object) — **API inbound**
  - Priority: MEDIUM
  - Description: Sending non-string non-number (array `[100]`, object `{}`) should 422 gracefully without 500.
  - Stub: not required

- **GAPI-024** — `response field: transaction.description` nullability — **API inbound**
  - Priority: MEDIUM
  - Description: When description is omitted in request, does the response include `"description": null` or omit the key entirely? Document the contract.
  - Stub: not required

- **GDB-040** — `db field (input): wallet.balance` — just-under boundary — **DB**
  - Priority: MEDIUM
  - Description: `amount > balance` by `0.00000001` must 422. Specific 8dp boundary test.

- **GDB-041** — `db field (input): wallet.balance == 0` — **DB**
  - Priority: MEDIUM
  - Description: Any non-zero amount against zero-balance wallet must 422 with balance unchanged.

- **GDB-042** — `db field (input): wallet.currency` — each valid pairing — **DB**
  - Priority: MEDIUM
  - Description: Parameterized happy path over each of USD/EUR/GBP/BTC/ETH (wallet.currency == request.currency) to prove currency is not hardcoded anywhere.

- **GDB-043** — `db field (assertion): transaction.created_at` auto-populated — **DB**
  - Priority: MEDIUM
  - Description: Not nil on insert; with frozen time, equal to Time.current.

- **GDB-044** — `db field (assertion): transaction.updated_at == created_at on insert` — **DB**
  - Priority: MEDIUM
  - Description: For transfer category (no status transition), updated_at should equal created_at on creation.

- **GDB-045** — `db field (assertion): transaction.updated_at monotonic on status transition` — **DB**
  - Priority: MEDIUM
  - Description: For payment category, after status transition to completed/failed, updated_at > created_at.

- **GDB-046** — `db field (assertion): transaction.amount large boundary` — **DB**
  - Priority: MEDIUM
  - Description: Exactly 1_000_000.00000000 persists unchanged.

- **GDB-047** — `db field (input): wallet.status concurrent mutation` — **DB**
  - Priority: MEDIUM
  - Description: Wallet status flipped to 'suspended' between validation and withdraw! — must not process. Covered partially by locking, but no test.

- **GOUT-013** — Malformed upstream response: nil object / missing .success? method — **Outbound API**
  - Priority: MEDIUM
  - Description: No test for `PaymentGateway.charge` returning `nil` or an object without `.success?`. Current source calls `.success?` unconditionally — would raise `NoMethodError`, 500, leak class name. Test must drive graceful handling.
  - Stub: Not required

- **GOUT-014** — Partial / missing upstream reference (reconciliation risk) — **Outbound API**
  - Priority: MEDIUM
  - Description: Source does not parse a gateway `transaction_id`/reference from the response. Reconciliation between internal transaction and upstream charge is impossible. Source-level gap — add a reference field on transactions, persist it after successful charge, test that happy path persists a non-nil reference.
  - Stub: Not required

- **GOUT-015** — Amount/currency tampering in upstream response (mismatch) — **Outbound API**
  - Priority: MEDIUM
  - Description: Source does not parse/compare returned amount/currency. A gateway that reports a different amount than requested is silently accepted. Source-level gap.
  - Stub: Not required

- **GFIN-011** — No audit trail / event stream — **Fintech:Compliance**
  - Priority: MEDIUM
  - Description: No `audit_log`/`transaction_events` event stream; no `created_by_id` actor, no `client_ip`, no `request_id` captured on the transaction row. Regulators (PCI DSS, PSD2, Reg E, FCA) require demonstrable audit trails.

- **GFIN-012** — No KYC/AML hook — **Fintech:Compliance**
  - Priority: MEDIUM
  - Description: No sanctions/risk-score check before `PaymentGateway.charge`. Exposes platform to sanctions violations.

- **GFIN-013** — Single hard-coded cap; no per-user velocity limits — **Fintech:Compliance**
  - Priority: MEDIUM
  - Description: Only `<= 1_000_000` enforced in model. No per-user daily/monthly velocity limits, no currency-specific limits, no velocity check across recent transactions.

- **GFIN-014** — No HTML/script sanitization on `description` — **Fintech:Security**
  - Priority: MEDIUM
  - Description: Free-text 500-char `description` flows into the DB and is echoed back in the response; no HTML sanitization or script stripping. If any downstream surface (admin panel, email receipt, statement PDF) renders this field without escaping, it's an XSS vector. Controller/service does not sanitize.

### LOW

- **GAPI-025** — UTF-8 multibyte in description — **API inbound**
  - Priority: LOW
  - Description: Emoji/CJK chars within 500-char limit must persist intact.
  - Stub: not required

- **GAPI-026** — `request field: transaction.wallet_id` very-large integer — **API inbound**
  - Priority: LOW
  - Description: 2^63 integer should 422 cleanly, not raise PG::RangeError 500.
  - Stub: not required

- **GDB-050** — `db field (assertion): transaction.user_id` NOT NULL enforced — **DB**
  - Priority: LOW
  - Description: Schema-level NOT NULL constraint — implicit, no code path creates without user. Add defensive model/DB constraint test.

- **GDB-051** — `db field (assertion): transaction.wallet_id` NOT NULL enforced — **DB**
  - Priority: LOW
  - Description: Same as GDB-050 for wallet_id.

- **GDB-052** — `db field (assertion): transaction.amount` NOT NULL enforced — **DB**
  - Priority: LOW
  - Description: Model validation catches this; add defensive schema-level test.

- **GDB-053** — `db field (assertion): transaction.currency` NOT NULL enforced — **DB**
  - Priority: LOW

- **GDB-054** — `db field (assertion): transaction.status` NOT NULL enforced — **DB**
  - Priority: LOW

- **GDB-055** — `db field (assertion): transaction.category` NOT NULL enforced — **DB**
  - Priority: LOW

- **GDB-056** — `db field (assertion): invalid enum value for transaction.status rejected by DB/model` — **DB**
  - Priority: LOW

- **GDB-057** — `db field (assertion): invalid enum value for transaction.category rejected by DB/model` — **DB**
  - Priority: LOW

- **GDB-058** — `db field (assertion): transaction.status terminal 'reversed' unreachable from POST` — **DB**
  - Priority: LOW
  - Description: Assert that POST /api/v1/transactions cannot produce a row with status 'reversed' under any mocked outbound response.

- **GDB-059** — `db field (input): wallet.currency case sensitivity` — **DB**
  - Priority: LOW
  - Description: Request currency='usd' (lowercase) behavior — reject or normalize? Lock via test.

- **GOUT-016** — Non-boolean truthy from success? (type correctness) — **Outbound API**
  - Priority: LOW
  - Description: If `success?` returns `"yes"` or `1`, Ruby truthiness would accept it as completed. Test should pin expected types.
  - Stub: Not required

---

## Hygiene (from audit)

### Anti-pattern 1: Service spec is not a contract boundary

**File:** `spec/services/transaction_service_spec.rb`

`TransactionService` is an internal implementation detail of the `POST /api/v1/transactions` endpoint. It is not consumed by other teams or systems. This spec should be deleted and its behavioral coverage moved into the request spec.

**Recommendation:** Delete `spec/services/transaction_service_spec.rb` — test through `POST /api/v1/transactions` instead.

---

### Anti-pattern 2: Multiple endpoints in one request spec file

**File:** `spec/requests/api/v1/transactions_spec.rb`

The file contains three `describe` blocks covering three separate endpoints:
- `POST /api/v1/transactions` (line 21)
- `GET /api/v1/transactions/:id` (line 100)
- `GET /api/v1/transactions` (line 119)

Each endpoint must have its own file so gaps are immediately visible per endpoint.

**Recommendation:** Split into `post_transactions_spec.rb`, `get_transaction_spec.rb`, and `get_transactions_spec.rb`.

---

### Anti-pattern 3: Implementation testing in service spec

**File:** `spec/services/transaction_service_spec.rb` lines 12–25

Three tests (`calls build_transaction`, `calls validate_wallet_active!`, `calls validate_currency_match!`) verify that private methods are called, not what behavior is produced. These are implementation tests, not contract tests.

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

### Anti-pattern 4: Implementation testing — gateway method call instead of behavior

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

### Anti-pattern 5: Missing test foundation (no subject / no shared `run_test` helper)

**File:** `spec/requests/api/v1/transactions_spec.rb`

Each test manually calls `post '/api/v1/transactions', params: params, headers: headers` inline (e.g. lines 37, 46, 54, 63, 72, 90). There is no shared `subject` or `run_test` helper that all scenarios share. This means override-one-field isolation is not enforced and the structure is harder to audit.

---

### Anti-pattern 6: Error scenario tests assert only status code — no negative assertions

**File:** `spec/requests/api/v1/transactions_spec.rb` (lines 42–93)

Every error scenario (`amount nil`, `amount negative`, `currency nil`, `currency invalid`, `wallet not found`) asserts only `have_http_status`. None asserts:
- No DB record was created
- No outbound `PaymentGateway.charge` call was made
- No sensitive data leaked in the error response body

---

### Anti-pattern 7: Happy path asserts only status code

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

## Test Stubs for CRITICAL / HIGH Gaps

### GAPI-001 — details MUST NOT leak balance (CRITICAL, merged with GFIN-005)

```ruby
context 'when amount exceeds balance (FINTECH: no balance leak)' do
  let(:amount) { '10000' } # far above WALLET_BALANCE

  it 'returns 422 and does not leak balance in error details' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)

    body = JSON.parse(response.body)
    expect(body['error']).to be_present
    expect(body['details']).to be_an(Array)
    # Balance MUST NOT be disclosed in any string of error payload
    serialized = body.to_json
    expect(serialized).not_to match(/#{Regexp.escape(wallet.balance.to_s)}/)
    expect(serialized).not_to match(/Current balance/i)
  end
end
```

### GAPI-002 — IDOR: wallet owned by another user (CRITICAL)

```ruby
context 'when wallet_id belongs to a different user' do
  let(:other_user)  { create(:user) }
  let!(:other_wallet) { create(:wallet, user: other_user, currency: DEFAULT_CURRENCY, balance: '500') }
  let(:wallet_id) { other_wallet.id }

  it 'returns 422, writes nothing, and does not confirm the other wallet exists' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)

    body = JSON.parse(response.body)
    expect(body['error']).to be_present
    serialized = body.to_json
    expect(serialized).not_to include(other_user.id.to_s)
  end
end
```

### GAPI-003 — Authorization header enforcement (CRITICAL, merged with GFIN-015)

```ruby
context 'when Authorization header is missing' do
  let(:headers) { {} }

  it 'returns 401 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(PaymentGateway).not_to have_received(:charge)
    body = JSON.parse(response.body)
    expect(body.to_json).not_to match(/stack|ActiveRecord|NoMethodError/)
  end
end

context 'when Authorization header is malformed' do
  let(:headers) { { 'Authorization' => 'Bearer not-a-real-token' } }
  it 'returns 401 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unauthorized)
  end
end

context 'when Authorization token is expired' do
  let(:headers) { expired_auth_headers(user) }
  it 'returns 401 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unauthorized)
  end
end
```

### GDB-001 / GFIN-003 — Concurrent debit TOCTOU on wallet.balance (CRITICAL)

```ruby
context 'under concurrent debit requests' do
  it 'rejects the second request when two simultaneous debits would overdraw the wallet' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')

    results = Parallel.map([60, 60], in_threads: 2) do |amount|
      post '/api/v1/transactions',
        params: { transaction: { amount: amount, currency: 'USD', wallet_id: wallet.id, category: 'transfer' } },
        headers: auth_headers
      response.status
    end

    # Exactly one must succeed, one must fail — total debits cannot exceed 100
    expect(results.count(201)).to eq(1)
    expect(results.count(422)).to eq(1)
    expect(wallet.reload.balance).to be >= 0
    expect(Transaction.where(wallet_id: wallet.id, status: 'completed').sum(:amount)).to be <= 100
  end
end
```

### GDB-002 / GFIN-002 — wallet.balance rollback on ChargeError (CRITICAL)

```ruby
context 'when PaymentGateway raises ChargeError after wallet has been debited' do
  it 'rolls back wallet.balance to its pre-request value' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')
    allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError.new('boom'))

    expect {
      post '/api/v1/transactions',
        params: { transaction: { amount: 30, currency: 'USD', wallet_id: wallet.id, category: 'payment' } },
        headers: auth_headers
    }.not_to change { wallet.reload.balance }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Transaction.where(wallet_id: wallet.id, status: 'completed').count).to eq(0)
  end

  it 'does not leave a pending transaction with a debited wallet (no orphan state)' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')
    allow(PaymentGateway).to receive(:charge).and_raise(StandardError.new('network timeout'))

    expect {
      post '/api/v1/transactions',
        params: { transaction: { amount: 30, currency: 'USD', wallet_id: wallet.id, category: 'payment' } },
        headers: auth_headers
    rescue StandardError
      nil
    }.not_to change { wallet.reload.balance }

    orphan = Transaction.where(wallet_id: wallet.id, status: 'pending').any?
    expect(orphan && wallet.balance < 100).to be false
  end
end
```

### GDB-003 — State-machine transitions in DB (CRITICAL)

```ruby
context 'pending → completed transition (payment success)' do
  let(:params) { super().merge(category: 'payment') }
  before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

  it 'persists transaction.status as completed' do
    run_test
    expect(Transaction.last.status).to eq('completed')
  end
end

context 'pending → failed transition (payment success?=false)' do
  let(:params) { super().merge(category: 'payment') }
  before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: false)) }

  it 'persists transaction.status as failed' do
    run_test
    expect(Transaction.last.status).to eq('failed')
  end
end
```

### GDB-004 — deposit category does not decrement balance (CRITICAL)

```ruby
context 'when category = deposit' do
  let(:params) { super().merge(category: 'deposit') }

  it 'does NOT decrement wallet.balance' do
    expect { run_test }.not_to change { wallet.reload.balance }
  end

  it 'persists transaction with category=deposit' do
    run_test
    expect(Transaction.last.category).to eq('deposit')
  end
end
```

### GDB-005 — No transaction row on error paths (CRITICAL)

```ruby
shared_examples 'does not create a transaction row' do
  it 'leaves Transaction.count unchanged' do
    expect { run_test }.not_to change(Transaction, :count)
  end
end

context 'amount nil'              do let(:params) { super().merge(amount: nil) };    include_examples 'does not create a transaction row'; end
context 'currency invalid'        do let(:params) { super().merge(currency: 'XYZ') }; include_examples 'does not create a transaction row'; end
context 'wallet suspended'        do before { wallet.update!(status: 'suspended') };  include_examples 'does not create a transaction row'; end
context 'insufficient balance'    do let(:params) { super().merge(amount: '9999') };  include_examples 'does not create a transaction row'; end
context 'currency mismatch'       do let(:params) { super().merge(currency: 'EUR') }; include_examples 'does not create a transaction row'; end
```

### GOUT-001 / GFIN-001 — Exactly once per payment transaction (CRITICAL)

```ruby
context 'outbound PaymentGateway.charge call count (category=payment)' do
  let(:category) { 'payment' }
  let(:params)   { base_params.merge(category: category) }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'invokes PaymentGateway.charge exactly once per request' do
    run_test
    expect(PaymentGateway).to have_received(:charge).once
    # Regression guard: dual call paths (service#charge_payment_gateway + model after_create)
    # would cause this to fail with .twice.
  end

  it 'sends exactly one charge referring to the persisted transaction id' do
    run_test
    expect(PaymentGateway).to have_received(:charge).with(
      hash_including(transaction_id: Transaction.last.id)
    ).once
  end
end
```

### GAPI-004 — amount > balance: full negative assertions (HIGH)

```ruby
context 'when amount exceeds wallet.balance' do
  let(:amount) { (BigDecimal(WALLET_BALANCE) + 1).to_s }
  it 'returns 422, no DB write, no gateway call' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
    expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE))
  end
end
```

### GAPI-005 — amount == balance drains to zero (HIGH)

```ruby
context 'when amount equals wallet.balance' do
  let(:amount) { WALLET_BALANCE }
  it 'returns 201 and sets wallet.balance to 0' do
    run_test
    expect(response).to have_http_status(:created)
    expect(wallet.reload.balance).to eq(0)
    body = JSON.parse(response.body)
    expect(body['transaction']['amount']).to eq(BigDecimal(WALLET_BALANCE).to_s)
  end
end
```

### GAPI-006 — amount boundary at regulatory cap 1_000_000 (HIGH)

```ruby
context 'when amount is exactly 1_000_000' do
  let!(:wallet) { create(:wallet, user: user, currency: 'USD', balance: '1000000') }
  let(:amount) { '1000000' }
  it 'returns 201' do
    run_test
    expect(response).to have_http_status(:created)
  end
end

context 'when amount is just above 1_000_000' do
  let(:amount) { '1000000.00000001' }
  it 'returns 422, no DB write' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GAPI-007 — zero amount (HIGH)

```ruby
context 'when amount is zero' do
  let(:amount) { '0' }
  it 'returns 422 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GAPI-008 — non-numeric amount (HIGH)

```ruby
context 'when amount is a non-numeric string' do
  let(:amount) { 'abc' }
  it 'returns 422 and writes nothing, no 500' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body.to_json).not_to match(/BigDecimal|ArgumentError|stack/)
  end
end
```

### GAPI-009 — precision beyond scale:8 (HIGH)

```ruby
context 'when amount has precision beyond decimal(20,8)' do
  let(:amount) { '100.123456789' } # 9 decimal places
  it 'rounds/truncates/rejects per pinned contract' do
    run_test
    if response.status == 201
      persisted = Transaction.last.amount
      expect(persisted.to_s.split('.').last.length).to be <= 8
    else
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Transaction.count).to eq(0)
    end
  end
end
```

### GAPI-010 — currency mismatch vs wallet.currency (HIGH)

```ruby
context 'when request currency does not match wallet.currency' do
  let(:currency) { 'EUR' } # wallet is USD
  it 'returns 422, no DB write, no gateway call' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GAPI-011 — each currency enum value as its own scenario (HIGH)

```ruby
%w[USD EUR GBP BTC ETH].each do |iso|
  context "when currency is #{iso} (matching wallet)" do
    let!(:wallet) { create(:wallet, user: user, currency: iso, balance: '500') }
    let(:currency) { iso }
    it "returns 201 and response.currency == #{iso}" do
      run_test
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['transaction']['currency']).to eq(iso)
    end
  end
end
```

### GAPI-012 — each category enum value (HIGH)

```ruby
context "when category is 'transfer'" do
  let(:category) { 'transfer' }
  it 'returns 201, debits balance, does not call PaymentGateway' do
    run_test
    expect(response).to have_http_status(:created)
    expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE) - BigDecimal(DEFAULT_AMOUNT))
    expect(PaymentGateway).not_to have_received(:charge)
  end
end

context "when category is 'payment'" do
  let(:category) { 'payment' }
  it 'returns 201 and calls PaymentGateway.charge exactly once' do
    run_test
    expect(response).to have_http_status(:created)
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(amount: BigDecimal(DEFAULT_AMOUNT), currency: DEFAULT_CURRENCY, user_id: user.id))
      .once
  end
end

context "when category is 'deposit'" do
  let(:category) { 'deposit' }
  it 'returns 201 and does NOT decrement wallet.balance' do
    run_test
    expect(response).to have_http_status(:created)
    expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE))
  end
end

context "when category is 'withdrawal'" do
  let(:category) { 'withdrawal' }
  it 'returns 201 and decrements wallet.balance' do
    run_test
    expect(response).to have_http_status(:created)
    expect(wallet.reload.balance).to eq(BigDecimal(WALLET_BALANCE) - BigDecimal(DEFAULT_AMOUNT))
  end
end
```

### GAPI-013 — omitted category defaults to 'transfer' (HIGH)

```ruby
context 'when category is omitted' do
  let(:category) { nil }
  it "defaults to 'transfer'" do
    run_test
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body['transaction']['category']).to eq('transfer')
    expect(Transaction.last.category).to eq('transfer')
  end
end
```

### GAPI-014 — invalid category (HIGH)

```ruby
context "when category is invalid" do
  let(:category) { 'refund' }
  it 'returns 422 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GAPI-015 — description length boundaries (HIGH)

```ruby
context 'when description is exactly 500 chars' do
  let(:description) { 'a' * 500 }
  it 'returns 201 and persists it verbatim' do
    run_test
    expect(response).to have_http_status(:created)
    expect(Transaction.last.description.length).to eq(500)
  end
end

context 'when description is 501 chars' do
  let(:description) { 'a' * 501 }
  it 'returns 422 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

### GAPI-016 — happy-path response body assertions (HIGH)

```ruby
context 'happy path — full response contract' do
  let(:description) { 'coffee' }
  let(:category)    { 'transfer' }

  it 'returns 201 with all response fields correctly typed and formatted' do
    run_test
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    txn  = body['transaction']

    expect(txn['id']).to be_a(Integer).and be > 0
    expect(txn['amount']).to eq(BigDecimal(DEFAULT_AMOUNT).to_s)
    expect(txn['amount']).to be_a(String)
    expect(txn['currency']).to eq(DEFAULT_CURRENCY)
    expect(txn['status']).to eq('pending')
    expect(txn['description']).to eq('coffee')
    expect(txn['category']).to eq('transfer')
    expect(txn['wallet_id']).to eq(wallet.id)
    expect(txn['created_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    expect(txn['updated_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    expect(Time.iso8601(txn['updated_at'])).to be >= Time.iso8601(txn['created_at'])
  end
end
```

### GAPI-017 — error envelope assertions (HIGH)

```ruby
context 'error envelope on every 422 path' do
  let(:amount) { '-1' } # any 422 trigger
  it 'returns { error: String, details: Array } with no stack leak' do
    run_test
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['error']).to be_a(String).and be_present
    expect(body['details']).to be_an(Array)
    expect(body.to_json).not_to match(/ActiveRecord::|NoMethodError|\.rb:\d+/)
  end
end

context 'ChargeError path returns exact error message' do
  let(:category) { 'payment' }
  before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError) }
  it "error == 'Payment processing failed'" do
    run_test
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['error']).to eq('Payment processing failed')
  end
end
```

### GAPI-018 — currency empty string (HIGH)

```ruby
context 'when currency is empty string' do
  let(:currency) { '' }
  it 'returns 422 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

### GAPI-019 — wallet_id nil (HIGH)

```ruby
context 'when wallet_id is nil' do
  let(:wallet_id) { nil }
  it 'returns 422 and writes nothing' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GAPI-020 — upgrade existing PARTIAL tests (HIGH)

```ruby
shared_examples 'a rejected request with no side effects' do
  it 'does not create a transaction, does not call gateway, does not leak' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
    body = JSON.parse(response.body)
    expect(body.to_json).not_to match(/ActiveRecord|stack|BigDecimal/)
  end
end

context 'when amount is nil' do
  let(:amount) { nil }
  it_behaves_like 'a rejected request with no side effects'
end

context 'when amount is negative' do
  let(:amount) { '-100' }
  it_behaves_like 'a rejected request with no side effects'
end

context 'when currency is nil' do
  let(:currency) { nil }
  it_behaves_like 'a rejected request with no side effects'
end

context 'when currency is invalid enum' do
  let(:currency) { 'ZZZ' }
  it_behaves_like 'a rejected request with no side effects'
end

context 'when wallet does not exist' do
  let(:wallet_id) { 0 }
  it_behaves_like 'a rejected request with no side effects'
end
```

### GDB-010 / GDB-011 — wallet.status enum preconditions (HIGH)

```ruby
context 'when wallet.status is suspended' do
  before { wallet.update!(status: 'suspended') }
  it 'returns 422, no transaction row, no outbound call' do
    allow(PaymentGateway).to receive(:charge)
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
    expect(wallet.reload.balance).to eq(INITIAL_BALANCE)
  end
end

context 'when wallet.status is closed' do
  before { wallet.update!(status: 'closed') }
  it 'returns 422, no transaction row, no outbound call' do
    allow(PaymentGateway).to receive(:charge)
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GDB-012 — exact-match balance boundary (HIGH)

```ruby
context 'when amount exactly equals wallet.balance' do
  let(:params) { super().merge(amount: INITIAL_BALANCE.to_s) }

  it 'succeeds and drives wallet.balance to exactly 0' do
    run_test
    expect(response).to have_http_status(:created)
    expect(wallet.reload.balance).to eq(BigDecimal('0'))
  end
end
```

### GDB-013 — insufficient balance (HIGH)

```ruby
context 'when amount exceeds wallet.balance' do
  let(:params) { super().merge(amount: (INITIAL_BALANCE + 1).to_s) }

  it 'returns 422, no transaction row, no balance change, no balance leak' do
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(wallet.reload.balance).to eq(INITIAL_BALANCE)
    body = JSON.parse(response.body)
    expect(body.to_s).not_to include(INITIAL_BALANCE.to_s)
  end
end
```

### GDB-014 — wallet.currency mismatch (HIGH)

```ruby
context 'when wallet.currency != request.currency' do
  let(:params) { super().merge(currency: 'EUR') } # wallet is USD

  it 'returns 422, no transaction row, no outbound call' do
    allow(PaymentGateway).to receive(:charge)
    expect { run_test }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GDB-015 — IDOR: wallet belongs to another user (HIGH)

```ruby
context 'when wallet_id belongs to a different user' do
  let(:other_user)   { create(:user) }
  let!(:other_wallet) { create(:wallet, user: other_user, currency: DEFAULT_CURRENCY, balance: INITIAL_BALANCE) }
  let(:params)       { super().merge(wallet_id: other_wallet.id) }

  it 'returns 422, no DB write, no outbound call, no leak of other wallet attrs' do
    allow(PaymentGateway).to receive(:charge)
    expect { run_test }.not_to change(Transaction, :count)
    expect(other_wallet.reload.balance).to eq(INITIAL_BALANCE)
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body).to_s
    expect(body).not_to include(other_user.email)
    expect(body).not_to include(other_wallet.id.to_s)
  end
end
```

### GDB-020 / GDB-021 / GDB-023 / GDB-024 / GDB-029 / GDB-031 — happy-path DB assertion bundle (HIGH)

```ruby
context 'happy path (category omitted → default transfer)' do
  let(:params) { super().except(:category) }

  it 'persists every assertion field correctly' do
    freeze_time do
      expect { run_test }.to change(Transaction, :count).by(1)
      t = Transaction.last
      expect(t.user_id).to     eq(user.id)                    # GDB-020
      expect(t.wallet_id).to   eq(wallet.id)                  # GDB-021
      expect(t.amount).to      eq(DEFAULT_AMOUNT)
      expect(t.currency).to    eq(DEFAULT_CURRENCY)           # GDB-023
      expect(t.status).to      eq('pending')                  # GDB-024
      expect(t.category).to    eq('transfer')                 # GDB-029
      expect(t.description).to eq('test')
      expect(t.created_at).to  eq(Time.current)               # GDB-043
      expect(t.updated_at).to  eq(t.created_at)               # GDB-044
      expect(wallet.reload.balance).to eq(INITIAL_BALANCE - DEFAULT_AMOUNT) # GDB-031
    end
  end
end
```

### GDB-022 — decimal(20,8) precision preserved (HIGH)

```ruby
context 'amount with 8-decimal precision' do
  let(:params) { super().merge(amount: '0.12345678') }
  it 'persists amount with exact decimal precision' do
    run_test
    expect(Transaction.last.amount).to eq(BigDecimal('0.12345678'))
  end
end
```

### GDB-027 — ChargeError state (HIGH)

```ruby
context 'pending → failed via ChargeError' do
  let(:params) { super().merge(category: 'payment') }
  before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError) }

  it 'leaves DB in consistent state (no row OR row with status=failed)' do
    run_test
    t = Transaction.last
    if t && t.wallet_id == wallet.id
      expect(t.status).to eq('failed')
    else
      expect(Transaction.where(wallet_id: wallet.id)).to be_empty
    end
  end
end
```

### GDB-028 — description provided vs omitted (HIGH)

```ruby
context 'description provided' do
  let(:params) { super().merge(description: 'groceries') }
  it 'persists the description verbatim' do
    run_test
    expect(Transaction.last.description).to eq('groceries')
  end
end

context 'description omitted' do
  let(:params) { super().except(:description) }
  it 'persists description as NULL' do
    run_test
    expect(Transaction.last.description).to be_nil
  end
end
```

### GDB-030 — each category enum value persists (HIGH)

```ruby
%w[transfer payment deposit withdrawal].each do |cat|
  context "category = #{cat}" do
    let(:params) { super().merge(category: cat) }
    before { allow(PaymentGateway).to receive(:charge).and_return(double(success?: true)) }

    it "persists transaction.category as '#{cat}'" do
      run_test
      expect(Transaction.last.category).to eq(cat)
    end
  end
end
```

### GOUT-002 — success?=true happy path (HIGH)

```ruby
context 'when PaymentGateway.charge returns success?=true (category=payment)' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'returns 201 and marks transaction completed' do
    run_test
    expect(response).to have_http_status(:created)

    body = JSON.parse(response.body)
    expect(body['transaction']['status']).to eq('completed')

    db_txn = Transaction.last
    expect(db_txn.status).to eq('completed')
    expect(db_txn.category).to eq('payment')

    expect(db_wallet.reload.balance).to eq(initial_balance - BigDecimal(params[:amount]))
  end
end
```

### GOUT-003 — success?=false failure path (HIGH)

```ruby
context 'when PaymentGateway.charge returns success?=false (category=payment)' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: false))
  end

  it 'marks transaction failed and does not leak gateway internals' do
    run_test
    db_txn = Transaction.last
    expect(db_txn.status).to eq('failed')

    body = JSON.parse(response.body)
    expect(body.to_s).not_to match(/PaymentGateway|stacktrace|ruby/i)
  end
end
```

### GOUT-004 — ChargeError rescued (HIGH)

```ruby
context 'when PaymentGateway.charge raises ChargeError (category=payment)' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge)
      .and_raise(PaymentGateway::ChargeError.new('upstream declined'))
  end

  it 'returns 422 with generic error and does not mark completed' do
    run_test
    expect(response).to have_http_status(:unprocessable_entity)

    body = JSON.parse(response.body)
    expect(body['error']).to eq('Payment processing failed')
    expect(body.to_s).not_to include('upstream declined')

    expect(Transaction.last.status).not_to eq('completed')
  end
end
```

### GOUT-005 — outbound amount sent correctly (HIGH)

```ruby
context 'outbound request field: amount' do
  let(:params) { base_params.merge(category: 'payment', amount: '100.00') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends amount as BigDecimal matching transaction.amount' do
    run_test
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(amount: BigDecimal('100.00')))
  end

  context 'with fractional scale (8 decimals)' do
    let(:params) { base_params.merge(category: 'payment', amount: '10.12345678') }

    it 'preserves full decimal precision' do
      run_test
      expect(PaymentGateway).to have_received(:charge)
        .with(hash_including(amount: BigDecimal('10.12345678')))
    end
  end
end
```

### GOUT-006 — outbound currency sent correctly (HIGH)

```ruby
context 'outbound request field: currency' do
  let(:params) { base_params.merge(category: 'payment', currency: 'USD') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends currency matching transaction.currency' do
    run_test
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(currency: 'USD'))
  end
end
```

### GOUT-007 — outbound user_id sent correctly (HIGH)

```ruby
context 'outbound request field: user_id' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends user_id from current_user.id (not forgeable via params)' do
    run_test
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(user_id: user.id))
  end
end
```

### GOUT-008 — outbound transaction_id sent correctly (HIGH)

```ruby
context 'outbound request field: transaction_id' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'sends transaction_id referring to the persisted Transaction row' do
    run_test
    created = Transaction.last
    expect(created.id).not_to be_nil
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(transaction_id: created.id))
  end
end
```

### GOUT-009 — zero calls on non-payment categories (HIGH)

```ruby
%w[transfer deposit withdrawal].each do |non_payment_category|
  context "outbound call-count: zero when category=#{non_payment_category}" do
    let(:params) { base_params.merge(category: non_payment_category) }

    before { allow(PaymentGateway).to receive(:charge) }

    it 'does not call PaymentGateway.charge' do
      run_test
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end
end

context 'outbound call-count: zero when category omitted (defaults to transfer)' do
  let(:params) { base_params.except(:category) }

  before { allow(PaymentGateway).to receive(:charge) }

  it 'does not call PaymentGateway.charge' do
    run_test
    expect(PaymentGateway).not_to have_received(:charge)
  end
end
```

### GOUT-010 — zero calls on validation failure (HIGH)

```ruby
shared_examples 'does not call PaymentGateway' do
  before { allow(PaymentGateway).to receive(:charge) }

  it 'does not invoke the outbound gateway' do
    run_test
    expect(PaymentGateway).not_to have_received(:charge)
  end
end

context 'when amount is nil (422)' do
  let(:params) { base_params.merge(category: 'payment', amount: nil) }
  include_examples 'does not call PaymentGateway'
end

context 'when currency is invalid (422)' do
  let(:params) { base_params.merge(category: 'payment', currency: 'ZZZ') }
  include_examples 'does not call PaymentGateway'
end

context 'when wallet is not owned by user (422)' do
  let(:other_user_wallet) { create(:wallet) }
  let(:params) { base_params.merge(category: 'payment', wallet_id: other_user_wallet.id) }
  include_examples 'does not call PaymentGateway'
end

context 'when wallet.status is suspended (422)' do
  before { db_wallet.update!(status: 'suspended') }
  let(:params) { base_params.merge(category: 'payment') }
  include_examples 'does not call PaymentGateway'
end

context 'when wallet.balance is insufficient (422)' do
  before { db_wallet.update!(balance: 0) }
  let(:params) { base_params.merge(category: 'payment', amount: '100') }
  include_examples 'does not call PaymentGateway'
end

context 'when Authorization header is missing (401)' do
  let(:headers) { {} }
  let(:params)  { base_params.merge(category: 'payment') }
  include_examples 'does not call PaymentGateway'
end
```

### GOUT-011 / GFIN-004 — idempotency key on outbound charge (HIGH)

```ruby
context 'with repeated requests carrying the same Idempotency-Key' do
  it 'creates only one transaction and charges the gateway only once' do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
    headers_with_key = auth_headers.merge('Idempotency-Key' => 'client-req-abc-123')

    2.times do
      post '/api/v1/transactions',
        params: { transaction: valid_params.merge(category: 'payment') },
        headers: headers_with_key
    end

    expect(Transaction.count).to eq(1)
    expect(PaymentGateway).to have_received(:charge).once
  end

  it 'rejects a request with same key but different params' do
    headers_with_key = auth_headers.merge('Idempotency-Key' => 'client-req-xyz')

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(amount: 10) },
      headers: headers_with_key
    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(amount: 999) },
      headers: headers_with_key

    expect(response).to have_http_status(:unprocessable_entity)
  end
end

context 'outbound idempotency key forwarded to gateway' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
  end

  it 'passes a stable idempotency_key derived from transaction.id' do
    run_test
    created = Transaction.last
    expect(PaymentGateway).to have_received(:charge)
      .with(hash_including(idempotency_key: created.id.to_s))
  end
end
```

### GOUT-012 — timeout / network error handling (HIGH)

```ruby
context 'when PaymentGateway.charge raises Timeout::Error' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_raise(Timeout::Error)
  end

  it 'returns a controlled error, not a 500 leaking internals' do
    run_test
    expect(response.status).to be_in([422, 503])
    body = JSON.parse(response.body)
    expect(body.to_s).not_to match(/Timeout::Error|backtrace|\/gems\//)
    expect(Transaction.last.status).not_to eq('completed')
  end
end

context 'when PaymentGateway.charge raises Errno::ECONNREFUSED' do
  let(:params) { base_params.merge(category: 'payment') }

  before do
    allow(PaymentGateway).to receive(:charge).and_raise(Errno::ECONNREFUSED)
  end

  it 'returns a controlled error, not a 500 leaking internals' do
    run_test
    expect(response.status).to be_in([422, 503])
    expect(Transaction.last.status).not_to eq('completed')
  end
end
```

### GFIN-006 — Invalid state transitions (HIGH)

```ruby
context 'state machine integrity' do
  it 'cannot transition a completed transaction back to pending via direct update' do
    txn = create(:transaction, user: user, wallet: wallet, status: 'completed')
    expect { txn.update!(status: 'pending') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'cannot transition a failed transaction to completed' do
    txn = create(:transaction, user: user, wallet: wallet, status: 'failed')
    expect { txn.update!(status: 'completed') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'cannot transition from a reversed terminal state' do
    txn = create(:transaction, user: user, wallet: wallet, status: 'reversed')
    %w[pending completed failed].each do |target|
      expect { txn.update!(status: target) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
```

### GFIN-007 — Stuck-pending detection (HIGH)

```ruby
context 'when gateway call raises an unexpected exception' do
  it 'does not leave the transaction in pending with wallet debited' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')
    allow(PaymentGateway).to receive(:charge).and_raise(Net::ReadTimeout.new)

    post '/api/v1/transactions',
      params: { transaction: { amount: 30, currency: 'USD', wallet_id: wallet.id, category: 'payment' } },
      headers: auth_headers
    rescue StandardError
      nil

    pending_orphan = Transaction.where(wallet_id: wallet.id, status: 'pending').last
    if pending_orphan
      expect(wallet.reload.balance).to eq(100)
    end
  end
end
```

### GFIN-008 — Rate limiting (HIGH)

```ruby
context 'rate limiting on money-mutating endpoint' do
  it 'returns 429 after exceeding the per-user rate threshold' do
    threshold = 60  # placeholder — must match configured limit
    (threshold + 1).times do
      post '/api/v1/transactions', params: { transaction: valid_params }, headers: auth_headers
    end
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'applies the limit per user, not per IP' do
    other_user_headers = auth_headers_for(create(:user))
    60.times { post '/api/v1/transactions', params: { transaction: valid_params }, headers: auth_headers }
    post '/api/v1/transactions', params: { transaction: valid_params }, headers: other_user_headers
    expect(response).not_to have_http_status(:too_many_requests)
  end
end
```

### GFIN-009 — Reconciliation reference missing (HIGH)

```ruby
context 'when PaymentGateway.charge succeeds' do
  it 'persists the external gateway reference for reconciliation' do
    allow(PaymentGateway).to receive(:charge).and_return(
      double(success?: true, transaction_id: 'pg_ref_abc123')
    )

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(Transaction.last.gateway_reference).to eq('pg_ref_abc123')
  end

  it 'flags transactions missing a gateway reference as a reconciliation risk' do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true, transaction_id: nil))

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:accepted)
  end
end
```

### GFIN-010 — Retry absent on transient gateway failure (HIGH)

```ruby
context 'transient gateway 5xx' do
  it 'retries with backoff before marking the transaction failed' do
    call_count = 0
    allow(PaymentGateway).to receive(:charge) do
      call_count += 1
      call_count < 3 ? raise(PaymentGateway::ChargeError.new('503')) : double(success?: true)
    end

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(response).to have_http_status(:created)
    expect(call_count).to eq(3)
    expect(Transaction.last.status).to eq('completed')
  end
end
```

---

## Checkpoint 2: Gap Coverage

| Contract Type | Gaps Checked | Count | Notes |
|---|---|---|---|
| API inbound | Yes | 26 | 3 CRITICAL (GAPI-001 auth, GAPI-002 IDOR, GAPI-003 balance-leak), 17 HIGH, 4 MEDIUM, 2 LOW from 03a-gaps-api.md |
| DB | Yes | 37 | 5 CRITICAL (GDB-001 TOCTOU, GDB-002 rollback, GDB-003 state machine, GDB-004 deposit, GDB-005 no-row-on-error), 22 HIGH, 8 MEDIUM, 10 LOW from 03b-gaps-db.md (note: 4 HIGH GDB-025/026 were consolidated under GDB-003 in 03b, but listed separately in contract map) |
| Outbound API | Yes | 16 | 1 CRITICAL (GOUT-001 double-charge), 11 HIGH (GOUT-002..012), 3 MEDIUM, 1 LOW from 03c-gaps-outbound.md |
| Jobs | N/A | 0 | No background jobs in POST /api/v1/transactions flow (per Checkpoint 1); all processing is synchronous within request |
| UI Props | N/A | 0 | JSON API endpoint only; no UI component props in this unit (per Checkpoint 1) |
