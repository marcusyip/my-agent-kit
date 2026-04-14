# Fintech Checklists — Contract Extraction & Gap Analysis

Reference file loaded on demand when fintech mode is detected. Contains detailed per-field extraction guidance and scenario checklists.

## Contract Extraction Details

### Money & Precision
- Identify all money/amount fields and their type representation (integer cents, BigDecimal, float, string)
- Flag any money field using floating-point type (`float`, `double`, `Float`) as HIGH severity anti-pattern — financial amounts must use exact types (integer cents, BigDecimal, Decimal)
- Extract currency fields paired with each amount — every amount must have a corresponding currency
- Extract decimal precision/scale from DB schema (e.g. `decimal(19,4)`, `numeric(12,2)`)
- Check for rounding rules: how are fractional cents handled? (truncate, round half-up, banker's rounding)

### Idempotency
- Extract idempotency key fields from request params (`idempotency_key`, `request_id`, `client_reference_id`, `X-Idempotency-Key` header)
- Identify which endpoints are state-mutating (POST, PUT, PATCH for financial operations) — these MUST have idempotency handling
- Check for unique constraints on idempotency keys in DB schema

### Transaction State Machine
- Extract all status/state enum values for financial entities (transactions, payments, orders, invoices)
- Map valid state transitions (e.g. `pending → completed`, `pending → failed`, `completed → reversed`) from source code (state machine definitions, guard clauses, update conditions)
- Identify terminal states (no further transitions allowed)
- Identify which transitions trigger side effects (notifications, ledger entries, webhook events)

### Balance & Ledger Integrity
- Identify balance fields and how they are updated (direct update, increment/decrement, ledger-based)
- Check for database-level concurrency control: optimistic locking (`lock_version`, `version` column, `SELECT ... FOR UPDATE`), pessimistic locking, or advisory locks
- Check for double-entry patterns: every debit has a matching credit, ledger entries sum to zero
- Identify balance check timing: is balance validated before or after the operation? (check-then-act race condition)

### External Payment Integrations
- Identify payment gateway/processor integrations (Stripe, Adyen, PayPal, Braintree, Square, etc.)
- Extract webhook/callback endpoint contracts: event types handled, signature verification, payload fields
- Extract retry and reconciliation patterns: how are failed charges retried? How are gateway timeouts resolved?
- Identify settlement/capture flow: authorize vs. capture, hold durations

### Regulatory & Compliance Fields
- Extract KYC/AML-related fields: verification status, risk score, identity document references
- Extract transaction limits: per-transaction, daily, monthly — and whether they are validated server-side
- Extract audit trail fields: `created_by`, `approved_by`, `ip_address`, `user_agent`, timestamps
- Identify PII fields that must be handled carefully in test data: SSN, bank account numbers, card numbers

### Concurrency & Data Integrity
- Identify all write paths that read-then-write (TOCTOU pattern): balance checks before debit, limit checks before transaction, inventory checks before purchase. For each, extract how the code prevents races — DB lock, atomic operation, or nothing (gap)
- Extract locking strategy per resource: optimistic (`lock_version`, `updated_at` check, `WHERE version = ?`), pessimistic (`SELECT ... FOR UPDATE`, `LOCK IN SHARE MODE`), advisory locks, distributed locks (Redis `SETNX`, Redlock), or no locking (gap)
- Identify multi-resource operations: transfers touching two accounts, payments debiting wallet and crediting merchant. Check for deadlock prevention — consistent lock ordering or single-query atomic updates
- Extract queue/job deduplication strategy: unique job keys, DB unique constraints on job args, or no deduplication (gap)
- Identify serialization points: DB transactions wrapping multi-step financial operations. Check isolation level if specified (`SERIALIZABLE`, `REPEATABLE READ`, `READ COMMITTED`)
- Extract retry logic: which operations retry on conflict/deadlock? How many times? With backoff? Does retry preserve idempotency?

### Position & Inventory
- Identify position/holdings fields: `position`, `quantity`, `shares`, `lots`, `holdings`, `inventory`, `units_held`, `open_qty`
- Identify order types that affect positions: buy/sell, open/close, increase/decrease, deposit/withdraw (for non-money assets)
- Extract position lifecycle states: open, partially filled, closed, liquidated
- Check for position constraints: max position size, short-selling allowed or prohibited, margin requirements
- Identify position update method: direct update, ledger-based (trade log → derived position), or event-sourced
- Check for position-balance coupling: does closing a position credit a cash balance? Does opening debit it?

### Security & Access Control
- Extract authentication requirements per endpoint: which endpoints require auth? What auth method (JWT, API key, session, OAuth)?
- Extract authorization rules: who can access which resources? Map resource ownership — user can only access their own wallets/transactions. Look for: `current_user`, `authorize!`, policy objects, middleware guards, `@login_required`, role checks
- Identify IDOR-vulnerable endpoints: any endpoint that accepts a resource ID in params (GET/PATCH/DELETE `/transactions/:id`, `/wallets/:id`). Check if the code verifies ownership/permission before acting
- Extract rate limiting configuration: which endpoints have rate limits? What are the thresholds? Is it per-user, per-IP, or per-API-key?
- Identify sensitive data in responses: do error messages leak account numbers, balances, internal IDs, or stack traces? Do list endpoints expose other users' data?
- Extract input sanitization: are financial fields (amount, currency, description) validated against injection? Is the description field HTML-sanitized for XSS?
- Identify payment credential handling: does the system touch raw card numbers (PAN), or use tokenization (Stripe tokens, vault references)? Raw PANs in the codebase are a critical finding
- Extract API key scoping: are there different permission levels for API keys (read-only vs. read-write vs. admin)? Are financial mutation endpoints restricted to appropriate scopes?
- Identify multi-factor/approval flows for high-value operations: large transfers, withdrawal to new address, adding new beneficiary. Extract the threshold and approval mechanism

## Gap Analysis Scenario Checklists

For each field type below, check every scenario. These are HIGH priority by default because financial bugs cause real money loss. Tag all findings with `[FINTECH]`.

### For every money/amount field
- Precision: test with amounts that have more decimal places than the schema allows (e.g. `0.001` when schema is `decimal(12,2)`) — does it round, truncate, or reject?
- Zero amount: is it allowed or rejected? (context-dependent: transfers usually reject zero, balance queries allow it)
- Negative amount: explicit rejection for credits/deposits, or allowed for adjustments/refunds?
- Very large amount: boundary at configured max (per-transaction limit), and one above it
- Very small amount: `0.01` (minimum monetary unit) — does it process correctly?
- Currency mismatch: amount in USD but wallet/account in EUR — must be rejected or converted
- Floating-point trap: if a test uses `0.1 + 0.2`, does the assertion account for IEEE 754? (flag as anti-pattern if float comparisons used on money)
- Balance validation (when amount is constrained by a balance): amount > available balance must be rejected; amount == balance must succeed and leave zero balance; assert exact balance after operation, not just "decreased". (See also "For balance/ledger fields" below for full concurrency and ledger integrity scenarios — this entry covers the amount-field perspective; avoid double-flagging the same gap.)
- Position validation (when amount affects a held position, e.g. shares, lots, inventory): sell/reduce qty > current position must be rejected; sell/reduce qty == position must succeed and close the position; partial fill must update position to exact remaining quantity; assert position state after operation (open, reduced, closed). (See also "For position/inventory fields" below for full position lifecycle scenarios.)

### For every idempotency key field
- Duplicate request with same key: must return the original response, not create a second record
- Duplicate request with same key but different params: must reject (not silently use old params)
- Missing idempotency key on mutating endpoint: must reject (or auto-generate — test the contract)
- Expired idempotency key (if TTL exists): must treat as new request
- Concurrent requests with same key: must not create duplicates (race condition)

### For every state machine field
- Every valid transition: test that it succeeds and triggers correct side effects
- Every invalid transition: test that it is rejected (e.g. `completed → pending` must fail)
- Terminal state: test that no further transitions are allowed
- Transition side effects: each transition that triggers notifications, ledger entries, or webhooks must have those side effects asserted
- Concurrent transition: two simultaneous transitions on the same record must not corrupt state (optimistic lock test)

### For balance/ledger fields
- Insufficient balance: transfer/withdrawal with amount > balance must be rejected
- Concurrent debit: two simultaneous debits that individually pass balance check but together exceed it — must not overdraw (requires DB-level locking test)
- Balance after operation: assert the exact balance value after credit/debit, not just "changed"
- Negative balance prevention: assert balance cannot go below zero (or below configured minimum)
- Ledger consistency: if double-entry, assert that sum of all entries equals zero after every operation

### For position/inventory fields
- Sell/reduce more than held: sell qty > current position must be rejected (unless short-selling is explicitly allowed — test both paths)
- Sell/reduce exactly held: qty == position must succeed and close the position (position goes to zero, status becomes closed)
- Partial fill: order partially filled must update position to exact remaining quantity, not just "decreased"
- Open new position: buy/deposit creates a position record with correct quantity, asset, and status
- Position after operation: assert exact position quantity after every trade, not just "changed"
- Concurrent trades on same position: two simultaneous sells that individually pass position check but together exceed it — only one should succeed (same pattern as concurrent debit on balance)
- Position-balance coupling: if closing a position credits cash, assert both position closed AND balance increased by correct amount in a single test
- Zero position cleanup: after position reaches zero, is the record marked closed/deleted? Test that subsequent operations on a zero position are rejected

### For outbound response fields (upstream is untrusted)
- Amount mismatch: gateway charged/returned a different amount than requested → must detect and reject/flag/reconcile. Test: mock gateway returning amount + 0.01, assert system catches the discrepancy
- Currency mismatch: gateway responded with a different currency than sent → must detect and reject/flag. Test: send USD, gateway returns EUR
- Missing external reference: gateway returned null/empty transaction_id or reference → flag as reconciliation risk. Test: mock gateway returning success with no transaction_id
- Unexpected status: gateway returned a status value not in the expected set → must not silently accept. Test: mock gateway returning `{ status: "unknown_value" }`
- Malformed response: gateway returned invalid JSON, truncated body, or unexpected structure → must not crash. Test: mock gateway returning `{` or `<html>500</html>`
- Each outbound response field (amount, currency, transaction_id, status) should have: correct value (assertion in happy path), wrong value (mismatch scenario), null/missing (error handling)

### For webhook/callback endpoints
- Signature verification: invalid signature must be rejected (401/403)
- Missing signature header: must be rejected
- Replay attack: duplicate event ID must be idempotent (not process twice)
- Unknown event type: must return 200 (acknowledge) but not process
- Out-of-order events: e.g. `payment_intent.succeeded` arriving before `payment_intent.created` — must handle gracefully

### For transaction limit fields
- At limit boundary: exactly at daily/monthly limit must succeed
- Over limit: one cent over must be rejected
- Limit reset: transaction after the limit period resets must succeed
- Multi-currency limits: if limits are in a base currency, test with transactions in different currencies

### For audit trail fields
- Every financial mutation creates an audit record with: actor, action, timestamp, IP, old value, new value
- Audit records are immutable: no UPDATE or DELETE on audit table (check DB constraints or test that attempts fail)

### For concurrency (every write path on financial data)
- Read-then-write race (TOCTOU): test that two concurrent requests reading the same balance do not both succeed when only one should. This is the single most common fintech bug. Test pattern: create two threads/processes that both attempt the same operation simultaneously, assert only one succeeds or both succeed with correct final state
- Optimistic lock conflict: test that a stale `lock_version`/`updated_at` causes the update to fail with a conflict error (409 or retry), not silently overwrite
- Pessimistic lock coverage: test that `SELECT ... FOR UPDATE` actually blocks a concurrent reader (two transactions, second waits or fails)
- Deadlock on multi-resource operations: for transfers (debit account A, credit account B), test with simultaneous A→B and B→A transfers — must not deadlock. If lock ordering is used, test that reversed ordering is rejected or reordered
- Double-submit prevention: rapidly submitting the same form/request twice must not create two transactions. This overlaps with idempotency but is a distinct user-facing scenario
- Job/worker concurrency: if the same job can be enqueued twice (e.g. webhook retry), test that processing is idempotent. Two workers picking up the same message must not double-process
- Atomic balance updates: test that balance is updated via `UPDATE wallets SET balance = balance - ? WHERE balance >= ?` (single atomic query) rather than read-check-write. If the code uses read-check-write, flag as HIGH concurrency gap
- Retry after conflict: if the system retries on optimistic lock failure, test that the retry sees fresh data and produces a correct outcome (not stale-data retry loop)

### For security & access control (every endpoint handling financial data)
- Authentication required: unauthenticated request to a protected endpoint must return 401. Test with missing token, expired token, malformed token
- Authorization / ownership: accessing another user's resource must return 403 or 404. Test with valid auth but wrong user's wallet ID, transaction ID, account ID. This is IDOR testing — the #1 fintech security bug
- Privilege escalation: regular user calling admin-only endpoints (e.g. manual credit, override limit) must be rejected. Test each role boundary
- Resource enumeration: sequential IDs allow guessing other resources. Test that accessing `transaction_id + 1` belonging to another user returns 403/404, not the other user's data. If UUIDs are used, note as a positive finding
- Amount tampering: test that the server recomputes totals (amount + fee = total) rather than trusting client-submitted totals. Submit a request where amount + fee ≠ total — must be rejected or server must override
- Negative amount bypass: test that submitting a negative amount to a credit/deposit endpoint does not reverse into a debit. Negative amounts on transfer endpoints must be explicitly rejected
- Rate limiting on financial endpoints: test that exceeding the rate limit returns 429. Test that rate limits are per-user (not just per-IP), so one user cannot exhaust limits for another
- Sensitive data in error responses: test that 422/500 responses do not leak account numbers, balances, internal user IDs, SQL errors, or stack traces. Error body should contain only the error code and a generic message
- Sensitive data in list responses: test that `GET /transactions` only returns the authenticated user's transactions, not all transactions. Test pagination boundaries
- Webhook signature validation: test that requests without a valid signature header are rejected (401). Test with tampered payload (valid signature for different body) — must be rejected
- API key scope enforcement: if the API supports scoped keys, test that a read-only key cannot create transactions (403). Test that a key scoped to one merchant cannot access another merchant's data
- High-value operation approval: if the system requires MFA/approval for transfers above a threshold, test at threshold (succeeds without approval), above threshold (requires approval), and that bypassing the approval step is not possible via direct API call
