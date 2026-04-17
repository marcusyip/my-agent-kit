# DB Contract Gap Analysis — POST /api/v1/transactions

Scope: DB contract fields ONLY (preconditions on `wallets`, postconditions on `transactions` and `wallets`). API inbound and Outbound sections are analyzed separately.

Source of truth for field inventory: `01-extraction.md` §DB Contract + `db/migrate/002_create_wallets.rb`, `db/migrate/003_create_transactions.rb`, `app/models/wallet.rb`, `app/models/transaction.rb`.

Existing coverage baseline: `02-audit.md` — the request spec `spec/requests/api/v1/transactions_spec.rb` has **zero** DB assertions in any scenario (happy path asserts only `have_http_status(:created)`). All DB-layer input preconditions and postconditions are therefore effectively untested.

---

## 1. Test Structure Tree (DB)

```
POST /api/v1/transactions
│
├── ── Preconditions (db field inputs — set in test setup) ──
│
├── db field: wallet.status (input; enum: active/suspended/closed, NOT NULL) — NO TESTS
│   ├── ✗ active (happy path precondition) → 201 [PARTIAL: factory default assumed active, never explicitly set]
│   ├── ✗ suspended → 422, no transaction row inserted, no outbound call, no data leak
│   ├── ✗ closed → 422, no transaction row inserted, no outbound call, no data leak
│   └── ✗ concurrent wallet.update(status: 'suspended') between validation and withdraw! → must not process
│
├── db field: wallet.balance (input; decimal(20,8), NOT NULL, DEFAULT 0) — NO TESTS
│   ├── ✗ balance > amount (happy path) → 201, balance decremented exactly by amount
│   ├── ✗ balance == amount (exact match boundary) → 201, balance becomes exactly 0.00000000
│   ├── ✗ balance == amount - 0.00000001 (just-under boundary) → 422, no DB write, no outbound call
│   ├── ✗ balance < amount (insufficient) → 422, balance unchanged, no transaction row, error details must NOT leak "Current balance: X"
│   ├── ✗ balance == 0 → 422
│   ├── ✗ balance precision: 8 decimal places preserved through check (e.g. 0.12345678 vs 0.12345679)
│   └── ✗ concurrent debit TOCTOU: two simultaneous requests each passing balance check — only one must succeed; final balance must not go negative
│
├── db field: wallet.currency (input; string, NOT NULL) — NO TESTS
│   ├── ✗ wallet.currency == request.currency (happy path) → 201
│   ├── ✗ wallet.currency != request.currency (mismatch: wallet=USD, req=EUR) → 422, no DB write, no outbound call
│   ├── ✗ case sensitivity: wallet=USD vs request=usd → behavior asserted
│   └── ✗ each valid currency pairing: USD/USD, EUR/EUR, GBP/GBP, BTC/BTC, ETH/ETH — at minimum one non-USD pairing to prove currency is not hardcoded
│
├── db field: wallet (existence precondition; FK target) — NO TESTS
│   ├── ✗ wallet missing (record does not exist for given wallet_id) → 422 [partial: covered as request field gap, not as DB precondition]
│   └── ✗ wallet belongs to different user (IDOR) → 422, no DB write, no outbound call, no data leak of other user's wallet attrs
│
├── db field: user (existence precondition; FK target for transaction.user_id) — NO TESTS
│   └── ✗ current_user.id is used as transaction.user_id (verified via assertion branch below)
│
├── ── Postconditions (db field assertions — verify after request) ──
│
├── db field: transaction.user_id (assertion; integer, NOT NULL, FK → users.id) — NO TESTS
│   ├── ✗ happy path: transaction.user_id == current_user.id
│   ├── ✗ NOT NULL constraint: not bypassable (no code path creates transaction without user)
│   └── ✗ FK integrity: transaction is not created under a different user than the authenticated one
│
├── db field: transaction.wallet_id (assertion; integer, NOT NULL, FK → wallets.id) — NO TESTS
│   ├── ✗ happy path: transaction.wallet_id == request.wallet_id == wallet.id
│   ├── ✗ NOT NULL constraint enforced
│   └── ✗ FK integrity: wallet_id references a wallet owned by the user
│
├── db field: transaction.amount (assertion; decimal(20,8), NOT NULL) — NO TESTS
│   ├── ✗ happy path: transaction.amount == request.amount (BigDecimal equality, exact)
│   ├── ✗ precision preserved: input "0.12345678" persists as 0.12345678 (no truncation to 2dp)
│   ├── ✗ no float anti-pattern: no IEEE-754 drift when amount is "0.1" + "0.2"
│   ├── ✗ large amount: exactly 1_000_000.00000000 persists
│   └── ✗ NOT NULL enforced: no path creates a transaction with null amount
│
├── db field: transaction.currency (assertion; string, NOT NULL, in USD/EUR/GBP/BTC/ETH) — NO TESTS
│   ├── ✗ happy path: transaction.currency == request.currency
│   ├── ✗ each enum value persists unchanged: USD, EUR, GBP, BTC, ETH
│   └── ✗ NOT NULL enforced
│
├── db field: transaction.status (assertion; string, NOT NULL, DEFAULT 'pending', enum: pending/completed/failed/reversed) — NO TESTS
│   ├── ✗ DEFAULT 'pending' applied when category != 'payment' (transfer/withdrawal) → 201, db status == 'pending'
│   ├── ✗ pending → completed transition: category='payment' + PaymentGateway.charge.success? == true → db status == 'completed'
│   ├── ✗ pending → failed transition: category='payment' + PaymentGateway.charge.success? == false → db status == 'failed'
│   ├── ✗ pending → failed transition: category='payment' + ChargeError raised → db status == 'failed' OR rollback (contract currently ambiguous — must be tested and nailed down)
│   ├── ✗ terminal state 'reversed' never set by this endpoint (not reachable from create)
│   ├── ✗ invalid enum value at DB layer rejected (enum constraint enforced)
│   └── ✗ NOT NULL enforced
│
├── db field: transaction.description (assertion; string, nullable, max 500) — NO TESTS
│   ├── ✗ happy path when provided: transaction.description == request.description
│   ├── ✗ happy path when omitted: transaction.description IS NULL (nullable default)
│   └── ✗ 500-char boundary: exactly 500 chars persists; 501 chars rejected (request-layer gap, DB should never hold >500)
│
├── db field: transaction.category (assertion; string, NOT NULL, DEFAULT 'transfer', enum: transfer/payment/deposit/withdrawal) — NO TESTS
│   ├── ✗ DEFAULT 'transfer' applied when category omitted → db category == 'transfer'
│   ├── ✗ each enum value persists: transfer, payment, deposit, withdrawal
│   ├── ✗ invalid enum value rejected at DB layer
│   └── ✗ NOT NULL enforced
│
├── db field: transaction.created_at (assertion; datetime, NOT NULL, auto) — NO TESTS
│   ├── ✗ auto-populated on insert (not nil)
│   └── ✗ within request wall-clock window (freeze time and assert exact value)
│
├── db field: transaction.updated_at (assertion; datetime, NOT NULL, auto) — NO TESTS
│   ├── ✗ auto-populated on insert (not nil)
│   ├── ✗ equals created_at on insert (happy path, no subsequent update)
│   └── ✗ monotonic on status transition: payment category path updates status pending→completed/failed → updated_at > created_at
│
├── db field: wallet.balance (assertion — post-state; decimal(20,8), NOT NULL) — NO TESTS
│   ├── ✗ non-deposit path (transfer/payment/withdrawal): wallet.balance == initial_balance - request.amount (exact BigDecimal)
│   ├── ✗ deposit category: wallet.balance UNCHANGED (current code does not credit on deposit — contract gap also, but behavior must be locked)
│   ├── ✗ exact-match debit: initial_balance == amount → final balance == 0.00000000 (not negative, not 1e-9)
│   ├── ✗ rollback on PaymentGateway ChargeError: if charge raises after withdraw!, balance state is consistent (either restored or transaction marked failed with explicit accounting)
│   ├── ✗ concurrent debit: two requests each debiting half the balance simultaneously — final balance == initial - 2*amount (or one rejected); never negative
│   └── ✗ precision: decrement preserves 8 decimal places
│
└── db field: transaction row presence (assertion; overall row insertion) — NO TESTS
    ├── ✗ happy path: Transaction.count changes by +1
    ├── ✗ every 422 error path: Transaction.count unchanged (assert via `expect { run_test }.not_to change(Transaction, :count)`)
    └── ✗ PaymentGateway ChargeError path: Transaction row state at end is consistent with status field (row exists but marked failed, OR row does not exist — contract must pick one)
```

---

## 2. Contract Map (DB)

| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |
|---|---|---|---|---|---|
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

**Totals:** 15 DB fields / 59 required scenarios / 0 covered / **59 gaps**.

---

## 3. Gap List

### CRITICAL (fintech money-safety / state-machine / concurrency)

- **id:** GDB-001
  **priority:** CRITICAL
  **field:** db field (input): wallet.balance
  **type:** DB
  **description:** Concurrent debit TOCTOU. `TransactionService#validate_sufficient_balance!` reads balance outside the `with_lock` used by `wallet.withdraw!`. Two concurrent requests can each pass the check and both withdraw, driving balance negative. No test exercises this race. Fintech checklist "concurrent debit" (single most common fintech bug).
  **stub:** REQUIRED (see §4 stub GDB-001)

- **id:** GDB-002
  **priority:** CRITICAL
  **field:** db field (assertion): wallet.balance (post-state, rollback)
  **type:** DB
  **description:** On `PaymentGateway::ChargeError`, the service rescues and returns a 422, but `wallet.withdraw!` may already have run (or not, depending on order). No test asserts the final balance is consistent with the final transaction.status. This is a money-safety invariant: balance MUST match the sum of non-failed transactions.
  **stub:** REQUIRED (see §4 stub GDB-002)

- **id:** GDB-003
  **priority:** CRITICAL
  **field:** db field (assertion): transaction.status (state machine)
  **type:** DB
  **description:** pending → completed and pending → failed transitions are entirely untested. State machine contract is undefended — a code change that leaves every payment stuck in 'pending' would ship green. Each valid transition (including the ChargeError path) must be asserted at the DB layer.
  **stub:** REQUIRED (see §4 stub GDB-003)

- **id:** GDB-004
  **priority:** CRITICAL
  **field:** db field (assertion): wallet.balance (deposit category)
  **type:** DB
  **description:** `deduct_balance!` skips `wallet.withdraw!` for `deposit` category, and no `wallet.deposit!` call is made. The current contract is "deposit does nothing to balance" — this is probably a bug, but must be locked by an explicit test so any future fix is caught. Absent a test, either behavior ships silently.
  **stub:** REQUIRED (see §4 stub GDB-004)

- **id:** GDB-005
  **priority:** CRITICAL
  **field:** db field (assertion): transaction row presence on error paths
  **type:** DB
  **description:** Every 422 error scenario (invalid amount, invalid currency, suspended wallet, insufficient balance, currency mismatch, ChargeError) must assert `Transaction.count` unchanged. Current tests assert only status code — a regression that inserts a 'pending' orphan transaction on validation failure would ship green.
  **stub:** REQUIRED (see §4 stub GDB-005)

### HIGH (contract integrity — each branch of the tree)

- **id:** GDB-010
  **priority:** HIGH
  **field:** db field (input): wallet.status = 'suspended'
  **type:** DB
  **description:** No test creates a wallet with `status: 'suspended'` and asserts 422 + no transaction row + no outbound call. Enum value coverage gap.
  **stub:** REQUIRED (see §4 stub GDB-010)

- **id:** GDB-011
  **priority:** HIGH
  **field:** db field (input): wallet.status = 'closed'
  **type:** DB
  **description:** Same as GDB-010 but for `closed` status.
  **stub:** REQUIRED (see §4 stub GDB-011)

- **id:** GDB-012
  **priority:** HIGH
  **field:** db field (input): wallet.balance — exact-match boundary
  **type:** DB
  **description:** `amount == balance` must succeed and leave balance at exactly 0.00000000. Untested. This is where precision/off-by-one bugs hide.
  **stub:** REQUIRED (see §4 stub GDB-012)

- **id:** GDB-013
  **priority:** HIGH
  **field:** db field (input): wallet.balance — insufficient
  **type:** DB
  **description:** `amount > balance` must 422 and leave balance unchanged + no transaction row. Untested at the boundary level.
  **stub:** REQUIRED (see §4 stub GDB-013)

- **id:** GDB-014
  **priority:** HIGH
  **field:** db field (input): wallet.currency mismatch
  **type:** DB
  **description:** `wallet.currency == 'USD'`, request currency = 'EUR' must 422, no DB write, no outbound call. Factory pins both to USD today.
  **stub:** REQUIRED (see §4 stub GDB-014)

- **id:** GDB-015
  **priority:** HIGH
  **field:** db field (input): wallet ownership (IDOR)
  **type:** DB
  **description:** Request with `wallet_id` belonging to a different user must 422, no DB write, no outbound call, and error response must NOT leak the other user's wallet attributes. Untested.
  **stub:** REQUIRED (see §4 stub GDB-015)

- **id:** GDB-020
  **priority:** HIGH
  **field:** db field (assertion): transaction.user_id
  **type:** DB
  **description:** Happy path never asserts `transaction.user_id == current_user.id`. A regression that pins user_id to the first admin would ship green.
  **stub:** REQUIRED (see §4 stub GDB-020)

- **id:** GDB-021
  **priority:** HIGH
  **field:** db field (assertion): transaction.wallet_id
  **type:** DB
  **description:** Happy path never asserts `transaction.wallet_id == request.wallet_id`. Untested FK value.
  **stub:** REQUIRED (see §4 stub GDB-021)

- **id:** GDB-022
  **priority:** HIGH
  **field:** db field (assertion): transaction.amount precision
  **type:** DB
  **description:** With `decimal(20,8)`, an input of `"0.12345678"` must persist exactly as 0.12345678. No precision assertion exists. Float drift or to_f truncation would ship green.
  **stub:** REQUIRED (see §4 stub GDB-022)

- **id:** GDB-023
  **priority:** HIGH
  **field:** db field (assertion): transaction.currency value
  **type:** DB
  **description:** No test asserts `transaction.currency == request.currency` at the DB layer.
  **stub:** REQUIRED (see §4 stub GDB-023)

- **id:** GDB-024
  **priority:** HIGH
  **field:** db field (assertion): transaction.status DEFAULT 'pending'
  **type:** DB
  **description:** For category=transfer (default), transaction.status must be 'pending' post-create (no PaymentGateway triggered). Untested.
  **stub:** REQUIRED (see §4 stub GDB-024)

- **id:** GDB-025
  **priority:** HIGH
  **field:** db field (assertion): transaction.status pending → completed transition
  **type:** DB
  **description:** category='payment' + mocked `PaymentGateway.charge` returning `success?: true` must leave `transaction.status == 'completed'` in DB. Untested.
  **stub:** REQUIRED (see §4 stub GDB-025)

- **id:** GDB-026
  **priority:** HIGH
  **field:** db field (assertion): transaction.status pending → failed transition (success?=false)
  **type:** DB
  **description:** category='payment' + mocked `PaymentGateway.charge` returning `success?: false` must leave `transaction.status == 'failed'` in DB. Untested.
  **stub:** REQUIRED (see §4 stub GDB-026)

- **id:** GDB-027
  **priority:** HIGH
  **field:** db field (assertion): transaction.status pending → failed transition (ChargeError)
  **type:** DB
  **description:** category='payment' + mocked `PaymentGateway.charge` raising `ChargeError` must leave DB in a consistent state: either no transaction row OR transaction row with status 'failed'. Contract currently unspecified — nail it down.
  **stub:** REQUIRED (see §4 stub GDB-027)

- **id:** GDB-028
  **priority:** HIGH
  **field:** db field (assertion): transaction.description provided + omitted
  **type:** DB
  **description:** Provided description must persist verbatim; omitted must persist as NULL (not empty string). Untested.
  **stub:** REQUIRED (see §4 stub GDB-028)

- **id:** GDB-029
  **priority:** HIGH
  **field:** db field (assertion): transaction.category DEFAULT 'transfer'
  **type:** DB
  **description:** When `category` omitted in request, DB row must have `category == 'transfer'`. Untested.
  **stub:** REQUIRED (see §4 stub GDB-029)

- **id:** GDB-030
  **priority:** HIGH
  **field:** db field (assertion): transaction.category each enum value persists
  **type:** DB
  **description:** Each of `transfer`, `payment`, `deposit`, `withdrawal` must persist to DB unchanged. Untested for all four.
  **stub:** REQUIRED (see §4 stub GDB-030)

- **id:** GDB-031
  **priority:** HIGH
  **field:** db field (assertion): wallet.balance decremented on non-deposit
  **type:** DB
  **description:** Post-create, `wallet.balance` must equal `initial_balance - request.amount` exactly. Untested — this is the core ledger invariant.
  **stub:** REQUIRED (see §4 stub GDB-031)

### MEDIUM (lower-risk invariants / defensive assertions)

- **id:** GDB-040
  **priority:** MEDIUM
  **field:** db field (input): wallet.balance — just-under boundary
  **type:** DB
  **description:** `amount > balance` by `0.00000001` must 422. Specific 8dp boundary test.

- **id:** GDB-041
  **priority:** MEDIUM
  **field:** db field (input): wallet.balance == 0
  **type:** DB
  **description:** Any non-zero amount against zero-balance wallet must 422 with balance unchanged.

- **id:** GDB-042
  **priority:** MEDIUM
  **field:** db field (input): wallet.currency — each valid pairing
  **type:** DB
  **description:** Parameterized happy path over each of USD/EUR/GBP/BTC/ETH (wallet.currency == request.currency) to prove currency is not hardcoded anywhere.

- **id:** GDB-043
  **priority:** MEDIUM
  **field:** db field (assertion): transaction.created_at auto-populated
  **type:** DB
  **description:** Not nil on insert; with frozen time, equal to Time.current.

- **id:** GDB-044
  **priority:** MEDIUM
  **field:** db field (assertion): transaction.updated_at == created_at on insert
  **type:** DB
  **description:** For transfer category (no status transition), updated_at should equal created_at on creation.

- **id:** GDB-045
  **priority:** MEDIUM
  **field:** db field (assertion): transaction.updated_at monotonic on status transition
  **type:** DB
  **description:** For payment category, after status transition to completed/failed, updated_at > created_at.

- **id:** GDB-046
  **priority:** MEDIUM
  **field:** db field (assertion): transaction.amount large boundary
  **type:** DB
  **description:** Exactly 1_000_000.00000000 persists unchanged.

- **id:** GDB-047
  **priority:** MEDIUM
  **field:** db field (input): wallet.status concurrent mutation
  **type:** DB
  **description:** Wallet status flipped to 'suspended' between validation and withdraw! — must not process. Covered partially by locking, but no test.

### LOW (defensive / schema-level)

- **id:** GDB-050
  **priority:** LOW
  **field:** db field (assertion): transaction.user_id NOT NULL enforced
  **type:** DB
  **description:** Schema-level NOT NULL constraint — implicit, no code path creates without user. Add defensive model/DB constraint test.

- **id:** GDB-051
  **priority:** LOW
  **field:** db field (assertion): transaction.wallet_id NOT NULL enforced
  **type:** DB
  **description:** Same as GDB-050 for wallet_id.

- **id:** GDB-052
  **priority:** LOW
  **field:** db field (assertion): transaction.amount NOT NULL enforced
  **type:** DB
  **description:** Model validation catches this; add defensive schema-level test.

- **id:** GDB-053
  **priority:** LOW
  **field:** db field (assertion): transaction.currency NOT NULL enforced
  **type:** DB

- **id:** GDB-054
  **priority:** LOW
  **field:** db field (assertion): transaction.status NOT NULL enforced
  **type:** DB

- **id:** GDB-055
  **priority:** LOW
  **field:** db field (assertion): transaction.category NOT NULL enforced
  **type:** DB

- **id:** GDB-056
  **priority:** LOW
  **field:** db field (assertion): invalid enum value for transaction.status rejected by DB/model
  **type:** DB

- **id:** GDB-057
  **priority:** LOW
  **field:** db field (assertion): invalid enum value for transaction.category rejected by DB/model

- **id:** GDB-058
  **priority:** LOW
  **field:** db field (assertion): transaction.status terminal 'reversed' unreachable from POST
  **type:** DB
  **description:** Assert that POST /api/v1/transactions cannot produce a row with status 'reversed' under any mocked outbound response.

- **id:** GDB-059
  **priority:** LOW
  **field:** db field (input): wallet.currency case sensitivity
  **type:** DB
  **description:** Request currency='usd' (lowercase) behavior — reject or normalize? Lock via test.

---

## 4. Test Stubs

RSpec pseudocode. All stubs assume the foundation pattern from `test-patterns.md` (shared `subject(:run_test)`, `let(:params)`, factories). Assumes real DB (no DB mocking) per skill convention.

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
require 'rails_helper'

RSpec.describe 'POST /api/v1/transactions', type: :request do
  DEFAULT_AMOUNT    = BigDecimal('100')
  DEFAULT_CURRENCY  = 'USD'
  DEFAULT_CATEGORY  = 'transfer'
  INITIAL_BALANCE   = BigDecimal('1000')

  subject(:run_test) { post '/api/v1/transactions', params: { transaction: params }, headers: headers }

  let(:user)      { create(:user) }
  let(:headers)   { auth_headers(user) }
  let!(:wallet)   { create(:wallet, user: user, currency: DEFAULT_CURRENCY, balance: INITIAL_BALANCE, status: 'active') }
  let(:params) do
    {
      wallet_id:   wallet.id,
      amount:      DEFAULT_AMOUNT.to_s,
      currency:    DEFAULT_CURRENCY,
      category:    DEFAULT_CATEGORY,
      description: 'test'
    }
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-001 — CRITICAL — concurrent debit TOCTOU on wallet.balance
  # ──────────────────────────────────────────────────────────────
  context 'concurrent debits that each pass the balance check individually' do
    let(:params) { super().merge(amount: '600') }  # two debits of 600 against 1000 balance

    it 'never drives wallet.balance negative' do
      threads = 2.times.map do
        Thread.new { post '/api/v1/transactions', params: { transaction: params }, headers: headers }
      end
      threads.each(&:join)

      wallet.reload
      expect(wallet.balance).to be >= 0
      # Either one succeeded and one rejected, or both locked serially — both outcomes must sum consistently
      completed = Transaction.where(wallet_id: wallet.id, status: %w[pending completed]).sum(:amount)
      expect(wallet.balance).to eq(INITIAL_BALANCE - completed)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-002 — CRITICAL — wallet.balance rollback on ChargeError
  # ──────────────────────────────────────────────────────────────
  context 'when PaymentGateway.charge raises ChargeError mid-flow' do
    let(:params) { super().merge(category: 'payment') }

    before { allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError.new('timeout')) }

    it 'keeps wallet.balance consistent with final transaction.status' do
      expect { run_test }.not_to raise_error
      wallet.reload
      failed_or_missing = Transaction.where(wallet_id: wallet.id).where.not(status: 'failed').sum(:amount)
      expect(wallet.balance).to eq(INITIAL_BALANCE - failed_or_missing)
      # Contract: failed transactions must NOT be counted as debits; balance invariant must hold
    end
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-003 — CRITICAL — state machine transitions in DB
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-004 — CRITICAL — deposit category does not decrement balance
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-005 — CRITICAL — no transaction row on error paths
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-010 / GDB-011 — HIGH — wallet.status enum preconditions
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-012 — HIGH — exact-match balance boundary
  # ──────────────────────────────────────────────────────────────
  context 'when amount exactly equals wallet.balance' do
    let(:params) { super().merge(amount: INITIAL_BALANCE.to_s) }

    it 'succeeds and drives wallet.balance to exactly 0' do
      run_test
      expect(response).to have_http_status(:created)
      expect(wallet.reload.balance).to eq(BigDecimal('0'))
    end
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-013 — HIGH — insufficient balance
  # ──────────────────────────────────────────────────────────────
  context 'when amount exceeds wallet.balance' do
    let(:params) { super().merge(amount: (INITIAL_BALANCE + 1).to_s) }

    it 'returns 422, no transaction row, no balance change, no balance leak' do
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(wallet.reload.balance).to eq(INITIAL_BALANCE)
      body = JSON.parse(response.body)
      expect(body.to_s).not_to include(INITIAL_BALANCE.to_s) # no balance value leak
    end
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-014 — HIGH — wallet.currency mismatch
  # ──────────────────────────────────────────────────────────────
  context 'when wallet.currency != request.currency' do
    let(:params) { super().merge(currency: 'EUR') } # wallet is USD

    it 'returns 422, no transaction row, no outbound call' do
      allow(PaymentGateway).to receive(:charge)
      expect { run_test }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PaymentGateway).not_to have_received(:charge)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-015 — HIGH — IDOR: wallet belongs to another user
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-020 / GDB-021 / GDB-023 / GDB-024 / GDB-029 / GDB-031
  # HIGH — happy-path DB assertion bundle
  # ──────────────────────────────────────────────────────────────
  context 'happy path (category omitted → default transfer)' do
    let(:params) { super().except(:category) }

    it 'persists every assertion field correctly' do
      freeze_time do
        expect { run_test }.to change(Transaction, :count).by(1)
        t = Transaction.last
        expect(t.user_id).to     eq(user.id)                    # GDB-020
        expect(t.wallet_id).to   eq(wallet.id)                  # GDB-021
        expect(t.amount).to      eq(DEFAULT_AMOUNT)             # (core)
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

  # ──────────────────────────────────────────────────────────────
  # GDB-022 — HIGH — decimal(20,8) precision preserved
  # ──────────────────────────────────────────────────────────────
  context 'amount with 8-decimal precision' do
    let(:params) { super().merge(amount: '0.12345678') }
    it 'persists amount with exact decimal precision' do
      run_test
      expect(Transaction.last.amount).to eq(BigDecimal('0.12345678'))
    end
  end

  # ──────────────────────────────────────────────────────────────
  # GDB-025 / GDB-026 — covered under GDB-003 above
  # GDB-027 — HIGH — ChargeError state
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-028 — HIGH — description provided vs omitted
  # ──────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────
  # GDB-030 — HIGH — each category enum value persists
  # ──────────────────────────────────────────────────────────────
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
end
```

---

## Summary

- **DB fields extracted:** 15 (3 wallet input preconditions + 1 existence precondition + 1 FK existence + 10 transaction assertion fields + 1 wallet balance post-state assertion + 1 row-presence meta-assertion)
- **Scenarios required:** 59
- **Scenarios covered:** 0 (the request spec has zero DB assertions in any block; wallet factory defaults give implicit coverage of "wallet is active" only)
- **Gap count:** 59
- **CRITICAL gaps:** 5 (GDB-001..005) — concurrency TOCTOU, balance rollback, state machine transitions, deposit balance behavior, no-row-on-error
- **HIGH gaps:** 21 (GDB-010..031) — enum preconditions, boundary, IDOR, per-field assertions, state-machine coverage
- **MEDIUM gaps:** 8
- **LOW gaps:** 10
- **Fintech flags:** TOCTOU race (GDB-001), rollback consistency (GDB-002), deposit ledger behavior (GDB-004), state-machine coverage (GDB-003/025/026/027), balance leak in error details (cross-referenced with API gap analysis)

WROTE: /Users/marcusyip/Sources/continuously-working-with-claude-code/personal-workspace/my-agent-kit/tdd-contract-review/benchmark/sample-app/tdd-contract-review/20260417-1408-post-api-v1-transactions/03b-gaps-db.md
