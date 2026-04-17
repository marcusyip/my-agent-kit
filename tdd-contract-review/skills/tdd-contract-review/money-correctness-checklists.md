<!-- version: 0.29.0 -->
# Money-Correctness Checklists — Contract Extraction & Gap Analysis

Reference file loaded on demand when `critical` mode is detected. Covers the "does the math work right?" domain: amounts, state, concurrency, ledger integrity, and money lifecycle (refunds, fees, holds, settlement, FX).

Companion file: `api-security-checklists.md` covers auth, access control, audit, and webhook trust.

## Contract Extraction Details

### Money & Precision
- Identify all money/amount fields and their type representation (integer cents, BigDecimal, float, string)
- Flag any money field using floating-point type (`float`, `double`, `Float`) as HIGH severity anti-pattern — financial amounts must use exact types (integer cents, BigDecimal, Decimal)
- Extract currency fields paired with each amount — every amount must have a corresponding currency
- Extract decimal precision/scale from DB schema (e.g. `decimal(19,4)`, `numeric(12,2)`)
- Check for rounding rules: how are fractional cents handled? (truncate, round half-up, banker's rounding)
- Extract the minor-unit convention per currency. Not all currencies divide into 100:
  - **Zero-decimal** (JPY, KRW, VND, CLP, ISK, XAF): no fractional unit — `amount=100` means 100 yen, not 1.00
  - **Three-decimal** (BHD, JOD, KWD, OMR, TND): thousandths — `decimal(12,2)` is wrong for these
  - **High-decimal crypto** (BTC 8, ETH 18, USDC 6): requires wider columns or string representation
  - A system with `decimal(12,2)` and currency `JPY` is either storing 100x the real amount or dropping meaningful precision — flag either way
- Check for integer cents overflow: Int32 cents maxes at ~$21M USD. Systems handling institutional volumes or high-decimal crypto must use Int64 or string

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

### External Payment Integrations (money-flow)
- Identify payment gateway/processor integrations (Stripe, Adyen, PayPal, Braintree, Square, etc.)
- Extract retry and reconciliation patterns: how are failed charges retried? How are gateway timeouts resolved?
- Identify settlement/capture flow: authorize vs. capture, hold durations (see also Holds & Authorizations below)
- Identify reconciliation process: end-of-day matching with gateway/bank statements, orphaned transactions (gateway has it / we don't, or vice versa), stuck-pending detection
- (Webhook/signature/replay aspects live in `api-security-checklists.md`)

### Refunds & Reversals
- Identify refund-capable endpoints and their state model (full refund, partial refund, chargeback, reversal)
- Extract refund linkage: every refund references the original transaction (via FK or external transaction_id)
- Extract partial-refund constraint: cumulative refund amount must not exceed original (`sum(refunds) ≤ original.amount`)
- Extract void vs. refund distinction: void (pre-settlement, no money moved) vs. refund (post-settlement, money returned). Different state machines, different gateway endpoints
- Extract fee-reversal rules on refund: platform fee returned to whom? Full vs. proportional reversal on partial refund
- Identify refund state transitions: `pending → succeeded | failed`; interaction with original transaction state (`completed → partially_refunded → fully_refunded`)
- Check for double-refund prevention at code level (idempotency) and DB level (unique constraint on external refund id or original_tx_id + client_reference)
- Identify chargeback handling: dispute lifecycle, funds held, impact on merchant balance

### Fees & Tax
- Identify fee calculation methods: percentage, flat, tiered (volume-based), minimum-fee floor, maximum-fee cap
- Extract fee rounding direction: round-up (conservative for platform), round-half-up, banker's rounding, truncate. Direction matters at boundary values
- Extract fee-on-top vs. fee-inclusive (gross vs. net): does the user pay `amount + fee` or does the platform take fee from `amount`? Different formulas, different receipts
- Identify who bears the fee: sender, receiver, split, absorbed by platform
- Extract tax calculation: percentage, jurisdiction-based (shipping address, merchant address, buyer location), inclusive vs. exclusive
- Extract tax withholding or reporting thresholds if the system must generate statements (e.g. 1099-K in the US, VAT reporting in the EU)
- Check currency of fee: fee in same currency as amount, or converted via FX?

### Holds & Authorizations
- Identify authorization vs. capture flow (card networks): auth holds funds, capture moves them. Distinct from one-shot purchases
- Extract auth expiry duration (7 days typical for card auths, varies by network and card type) and what happens at expiry (automatic release)
- Identify balance types: settled (available) vs. pending (authed but not captured) vs. on-hold. Each has distinct semantics and must not be confused
- Extract incremental authorization (raise hold amount) and reauthorization (extend hold duration) flows if present
- Identify partial capture: capture < auth amount — remaining auth must be released, not left dangling
- Check for double-capture prevention: capturing the same auth twice must fail

### Time, Settlement & Cutoffs
- Identify settlement timing: T+0 (instant), T+1, T+N (business days). For T+N, check which calendar is used (business days excluding weekends + holidays)
- Extract cutoff times: ACH (4pm ET typical), wire (5pm ET), card capture batch (varies). Transactions past cutoff roll to next business day
- Identify timezone for limit windows: "daily limit" — is it UTC-day, user-local-day, or platform-timezone-day? All three are defensible; the contract must be explicit and tested
- Extract business-day calendar source: hardcoded, library (e.g. `businesstime`, `holidays`), or external API. Holiday list staleness is a gap
- Check for month-end, quarter-end, year-end accounting boundaries (reports generated at 23:59:59 on last day of period — DST can shift this)
- Identify DST handling for time-sensitive operations (scheduled payments crossing DST transitions, recurring charges on the day a clock skips an hour)

### FX & Currency Conversion
- Identify FX rate source: live API (e.g. XE, Wise, internal quote service), cached rates, manually-set rates. Extract the TTL/staleness tolerance
- Extract rate locking: does the rate lock at quote time or at execution? How long is the lock valid? What happens when a user executes a stale quote?
- Identify rounding rules at conversion boundaries: rounding compounds across hops (USD → EUR → GBP = two rounding events). Is rounding per-hop or only at the final leg?
- Extract triangulation path: direct pair available, or via a base currency (USD/EUR)? Which path is chosen and whose rate applies?
- Identify FX spread/markup: rate shown to user vs. rate applied — often a user-visible field requiring disclosure (regulatory in some jurisdictions)
- Check for rate expiry behavior: if the rate expired between quote and execute, does the system re-fetch, fail, or use stale rate?

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

### Transaction Limits (amount-math)
- Extract transaction limits: per-transaction, daily, monthly, per-payment-method. Check that limits are validated server-side, not just in the UI
- Identify limit currency: are limits denominated in a base currency? How are multi-currency transactions aggregated into the limit window?
- Extract limit-window timezone (see Time, Settlement & Cutoffs above — critical for "daily" limits)
- (KYC-triggered limit changes and AML thresholds live in `api-security-checklists.md`)

## Gap Analysis Scenario Checklists

For each field type below, check every scenario. These are HIGH priority by default because financial bugs cause real money loss. Tag all findings with `[MONEY]`.

### For every money/amount field
- Precision: test with amounts that have more decimal places than the schema allows (e.g. `0.001` when schema is `decimal(12,2)`) — does it round, truncate, or reject?
- Zero amount: is it allowed or rejected? (context-dependent: transfers usually reject zero, balance queries allow it)
- Negative amount: explicit rejection for credits/deposits, or allowed for adjustments/refunds?
- Very large amount: boundary at configured max (per-transaction limit), and one above it
- Very small amount: minimum monetary unit for the currency (`0.01` USD, `1` JPY, `0.00000001` BTC) — does it process correctly?
- Currency minor-unit: test that zero-decimal currencies (JPY) reject fractional amounts (e.g. `100.50 JPY` must fail or be rounded per contract) and that high-decimal currencies don't silently truncate
- Currency mismatch: amount in USD but wallet/account in EUR — must be rejected or converted (if converted, see FX scenarios)
- Floating-point trap: if a test uses `0.1 + 0.2`, does the assertion account for IEEE 754? (flag as anti-pattern if float comparisons used on money)
- Integer overflow: if the system stores amounts as integer cents in an Int32 column, test at `2_147_483_647` cents (~$21M) — must handle or reject, not silently wrap
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

### For transaction limit fields
- At limit boundary: exactly at daily/monthly limit must succeed
- Over limit: one cent over must be rejected
- Limit reset: transaction after the limit period resets must succeed
- Multi-currency limits: if limits are in a base currency, test with transactions in different currencies
- Limit-window timezone: test a transaction at 23:59 local-time and 00:01 local-time — assert they fall in the correct windows per the documented convention (UTC / user-local / platform tz)

### For refund/reversal fields
- Partial refund below original: refund with amount < original.amount must succeed and update refunded_total correctly
- Partial refund at original: refund with amount == original.amount must succeed and mark original fully refunded
- Partial refund above original: refund with amount > original.amount must be rejected (422)
- Cumulative refunds exceeding original: second refund whose sum pushes total > original must be rejected
- Double refund (same request): calling refund twice with same idempotency key in rapid succession must not refund twice
- Refund of already-fully-refunded transaction: must be rejected with clear error
- Refund of failed/cancelled transaction: state machine must reject (nothing to refund)
- Fee reversal on refund: assert platform fees are reversed per contract (full reverse on full refund, proportional on partial, or zero reversal if fees are non-refundable)
- Refund reaches external gateway: assert outbound refund call is made with correct amount + original charge reference
- Chargeback path: dispute raised by cardholder — assert transaction status transitions correctly and funds are held/reversed per rules
- Void before settlement: assert void succeeds and no money moved (distinguishable from refund)
- Void after settlement: must be rejected — instruct to use refund

### For fees & tax fields
- Fee calculation correctness: for each fee method (percentage, flat, tiered), assert exact fee value, not just "fee applied"
- Fee rounding direction: assert rounding goes the documented way (e.g. round-up favors platform) with a test at the half-cent boundary
- Fee floor and cap: assert min-fee floor triggers on small amounts; max-fee cap triggers on large amounts
- Fee-on-top vs. inclusive: for an amount of 100, fee of 3, assert either (user pays 103, platform receives 3) or (user pays 100, receiver gets 97) per the contract
- Fee on refund: full refund reverses fee fully; partial refund reverses fee proportionally (or per contract)
- Zero-fee edge case: if a pricing plan has zero fee, assert no fee record is created (unless contract specifies zero-amount record)
- Tax calculation per jurisdiction: for jurisdiction-based tax, test with multiple jurisdictions; assert zero-tax jurisdictions produce no tax line
- Fee currency: assert fee is denominated in the expected currency; if FX applies, assert conversion is correct
- Tiered fee boundary: amount at the tier threshold — assert correct tier is applied (document which side of the boundary wins)

### For hold/authorization fields
- Successful auth: assert hold is recorded, available balance decreases by auth amount, pending balance increases
- Capture equal to auth: assert capture succeeds, hold removed, funds moved from pending to settled on recipient
- Capture less than auth (partial capture): assert captured amount moves, unused portion of auth is released
- Capture more than auth: must be rejected (or require incremental auth first — test both paths per contract)
- Capture after auth expiry: expired auth — capture must be rejected with clear error
- Double capture: capturing same auth twice must fail (idempotency)
- Auth expiry cleanup: at expiry, hold is released and available balance restored. Test with a clock-frozen test or background job
- Void of auth: voiding an uncaptured auth releases the hold immediately
- Void after capture: must fail (use refund instead)
- Incremental auth: raising hold amount — assert old hold released and new hold placed (or delta-hold per gateway behavior)
- Pending balance correctness: with an outstanding auth, pending balance = sum(open_auths); test with multiple overlapping auths

### For time/settlement/cutoff fields
- Transaction submitted before cutoff: settles on T+N where N matches the documented SLA (e.g. T+1 for ACH)
- Transaction submitted after cutoff: settles on T+N+1 (rolls over one business day)
- Cutoff boundary: transaction submitted exactly at cutoff time — document which side wins (inclusive or exclusive) and test both
- Weekend submission: Friday-evening transaction settles Monday+N (not Saturday/Sunday)
- Holiday submission: transaction submitted on a bank holiday rolls to next business day
- Daily limit window: transaction at 23:59 and 00:01 in the documented timezone — assert they fall in different windows
- DST transition: a recurring payment scheduled for 02:30 on the day DST skips 02:00–03:00 — document behavior (run once, skip, or run at 03:30) and test it
- Month-end boundary: a transaction at 23:59:59 on the last day of a month is accounted to this month; 00:00:00 next day to next month — including at DST transitions
- Scheduled payment far in the future: assert schedule survives timezone changes (DST) and business-day calendar updates (new holidays added)

### For FX/currency-conversion fields
- Single-hop conversion: USD → EUR with rate 0.92 — assert exact converted amount per rounding rule
- Triangulated conversion: USD → GBP via EUR — assert rounding happens per hop (or once at the end) per documented behavior
- Stale rate: rate older than TTL — must re-fetch or fail, not silently use stale rate
- Rate lock honored: quote generated at time T — execution at T+30s uses locked rate, not current rate. Test with a mocked rate change between quote and execute
- Rate lock expiry: quote older than lock duration — must be re-quoted, not executed at old rate
- Spread/markup disclosure: assert user-visible rate differs from mid-market rate by documented markup
- Zero-amount conversion: converting 0 returns 0 in target currency with no rounding artifacts
- Very small amount with zero-decimal target: converting 1 cent USD → JPY — document and test rounding (0 or 1 yen)
- Unsupported currency: conversion from/to an unsupported currency must be rejected
- Same-currency conversion: USD → USD — rate 1.0, no markup, no conversion record (or pass-through per contract)
- FX rate source failure: rate API down — test fallback behavior (fail, use cached, use configured default)

### For concurrency (every write path on financial data)
- Read-then-write race (TOCTOU): test that two concurrent requests reading the same balance do not both succeed when only one should. This is the single most common money-correctness bug in production. Test pattern: create two threads/processes that both attempt the same operation simultaneously, assert only one succeeds or both succeed with correct final state
- Optimistic lock conflict: test that a stale `lock_version`/`updated_at` causes the update to fail with a conflict error (409 or retry), not silently overwrite
- Pessimistic lock coverage: test that `SELECT ... FOR UPDATE` actually blocks a concurrent reader (two transactions, second waits or fails)
- Deadlock on multi-resource operations: for transfers (debit account A, credit account B), test with simultaneous A→B and B→A transfers — must not deadlock. If lock ordering is used, test that reversed ordering is rejected or reordered
- Double-submit prevention: rapidly submitting the same form/request twice must not create two transactions. This overlaps with idempotency but is a distinct user-facing scenario
- Job/worker concurrency: if the same job can be enqueued twice (e.g. webhook retry), test that processing is idempotent. Two workers picking up the same message must not double-process
- Atomic balance updates: test that balance is updated via `UPDATE wallets SET balance = balance - ? WHERE balance >= ?` (single atomic query) rather than read-check-write. If the code uses read-check-write, flag as HIGH concurrency gap
- Retry after conflict: if the system retries on optimistic lock failure, test that the retry sees fresh data and produces a correct outcome (not stale-data retry loop)
