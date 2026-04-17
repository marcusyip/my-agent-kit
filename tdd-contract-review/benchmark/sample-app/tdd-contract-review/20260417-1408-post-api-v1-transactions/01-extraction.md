## Files Examined

**Source:**
- `app/controllers/api/v1/transactions_controller.rb` — primary unit handler (create action)
- `app/services/transaction_service.rb` — downstream service invoked by handler; contains all business logic, balance validation, and outbound gateway call

**DB schema:**
- `db/migrate/001_create_users.rb` — users table: email, name, encrypted_password
- `db/migrate/002_create_wallets.rb` — wallets table: user_id, currency, name, balance, status
- `db/migrate/003_create_transactions.rb` — transactions table: user_id, wallet_id, amount, currency, status, description, category
- `app/models/user.rb` — User model validations and associations
- `app/models/wallet.rb` — Wallet model: enum status (active/suspended/closed), withdraw!/deposit! methods, with_lock usage
- `app/models/transaction.rb` — Transaction model: enum status (pending/completed/failed/reversed), enum category (transfer/payment/deposit/withdrawal), validations, after_create callback to PaymentGateway

**Outbound clients:**
- `PaymentGateway.charge` — referenced at `app/models/transaction.rb:28` (after_create callback) and `app/services/transaction_service.rb:78`; no HTTP implementation file found in codebase — SDK-level interface is the boundary

**Other:**
- (none)

---

## Checkpoint 1: Contract Type Coverage

| Contract Type | Status | Fields | Notes |
|---|---|---|---|
| API inbound | Extracted | 14 | 5 request params + 1 request header + 9 response fields (including 2 timestamps) |
| DB | Extracted | 15 | transactions table (7 fields) + wallets table preconditions (3 fields) + users table (2 FK-relevant fields) + wallet status enum (3 values) + transaction status enum (4 values) from migration + model files |
| Outbound API | Extracted | 7 | PaymentGateway.charge SDK interface; no HTTP URL found — SDK is the boundary; 4 request fields + 3 response fields |
| Jobs | Not applicable | — | no async job triggered by this unit; PaymentGateway.charge is called synchronously in-process |
| UI Props | Not applicable | — | server-side API endpoint, no UI component |

---

## Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb (create action)
        app/services/transaction_service.rb
Framework: Rails/RSpec

API Contract (inbound):
  POST /api/v1/transactions

    Input:
      request header: Authorization (bearer token, required) [HIGH]
        — enforced by before_action :authenticate_user!
      request field: transaction.amount (decimal string, required, > 0, <= 1_000_000) [HIGH]
        — validated in Transaction model: numericality greater_than: 0, less_than_or_equal_to: 1_000_000
        — also validated against wallet.balance in TransactionService#validate_sufficient_balance!
      request field: transaction.currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH]
        — validated in Transaction model: inclusion in %w[USD EUR GBP BTC ETH]
        — also validated against wallet.currency in TransactionService#validate_currency_match!
      request field: transaction.wallet_id (integer, required) [HIGH]
        — used to scope wallet lookup: current_user.wallets.find_by(id: ...)
        — returns 422 "Wallet not found" if not found or not owned by user
      request field: transaction.description (string, optional, max: 500 chars) [HIGH]
        — validated in Transaction model: length maximum: 500
      request field: transaction.category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH]
        — default set in TransactionService#build_transaction; payment category triggers PaymentGateway.charge

    Assertion (verify in happy path):
      response field: transaction.id (integer) [HIGH]
      response field: transaction.amount (string, decimal-as-string via .to_s) [HIGH]
      response field: transaction.currency (string) [HIGH]
      response field: transaction.status (string, enum: pending/completed/failed/reversed) [HIGH]
      response field: transaction.description (string, nullable) [HIGH]
      response field: transaction.category (string, enum: transfer/payment/deposit/withdrawal) [HIGH]
      response field: transaction.wallet_id (integer) [HIGH]
      response field: transaction.created_at (datetime, ISO8601 via .iso8601) [HIGH]
      response field: transaction.updated_at (datetime, ISO8601 via .iso8601) [HIGH]

    Status codes: 201 (created), 422 (validation failed / wallet not found / insufficient balance / currency mismatch / payment gateway error), 401 (unauthenticated)

    Error response shape (422):
      response field: error (string, human-readable message) [HIGH]
      response field: details (array of strings) [HIGH]

DB Contract:
  Input (preconditions — set in test setup):
    db field: wallet.status — must be 'active'; enum values: active/suspended/closed [HIGH]
      — checked in TransactionService#validate_wallet_active! via wallet.active?
    db field: wallet.balance — must be >= requested amount; decimal(20,8), NOT NULL, DEFAULT 0 [HIGH]
      — checked in TransactionService#validate_sufficient_balance!
    db field: wallet.currency — must match request currency field [HIGH]
      — checked in TransactionService#validate_currency_match!

  Assertion (postconditions — verify after request):
    db field: transaction.user_id (integer, NOT NULL, FK → users.id) [HIGH]
    db field: transaction.wallet_id (integer, NOT NULL, FK → wallets.id) [HIGH]
    db field: transaction.amount (decimal precision:20 scale:8, NOT NULL) [HIGH]
    db field: transaction.currency (string, NOT NULL, in: USD/EUR/GBP/BTC/ETH) [HIGH]
    db field: transaction.status (string, NOT NULL, DEFAULT 'pending'; enum: pending/completed/failed/reversed) [HIGH]
      — set to 'pending' on create; updated to 'completed' or 'failed' after PaymentGateway response
    db field: transaction.description (string, nullable, max: 500) [HIGH]
    db field: transaction.category (string, NOT NULL, DEFAULT 'transfer'; enum: transfer/payment/deposit/withdrawal) [HIGH]
    db field: transaction.created_at (datetime, NOT NULL, auto) [HIGH]
    db field: transaction.updated_at (datetime, NOT NULL, auto) [HIGH]
    db field: wallet.balance — must be decremented by transaction.amount (except for deposit category) [HIGH]
      — TransactionService#deduct_balance! calls wallet.withdraw! unless deposit?

Outbound API:
  PaymentGateway.charge(amount:, currency:, user_id:, transaction_id:)
  Triggered only when transaction.category == 'payment'
  Called synchronously in TransactionService#charge_payment_gateway (line 78) and also via
  Transaction#notify_payment_gateway after_create callback (line 28 in model) — dual call paths present.

    Assertion (verify correct params sent to PaymentGateway.charge):
      outbound request field: amount (decimal, matches transaction.amount) [HIGH]
      outbound request field: currency (string, matches transaction.currency) [HIGH]
      outbound request field: user_id (integer, matches current_user.id) [HIGH]
      outbound request field: transaction_id (integer, matches transaction.id) [HIGH]

    Input (set via mock — upstream untrusted, validate each):
      outbound response field: success? (boolean) [HIGH]
        — true → transaction.status updated to 'completed'
        — false → transaction.status updated to 'failed'
      outbound response field: (implicit: ChargeError exception path) [HIGH]
        — PaymentGateway::ChargeError rescued → Result with error: 'Payment processing failed'
      outbound response field: (no transaction_id/reference in response parsed per source code) [MEDIUM]
        — source code does not parse an external reference from the gateway response; reconciliation field absent

============================
```

---

## Fintech Dimensions

### Money & Precision
- `transaction.amount` uses `decimal(20,8)` — correct exact type, no float anti-pattern detected.
- `wallet.balance` uses `decimal(20,8)` — correct.
- `TransactionService#validate_sufficient_balance!` converts params amount via `BigDecimal(@params[:amount].to_s)` before comparing — correct, avoids float trap.
- Currency field paired with every amount field in both request and DB.

### Idempotency
- No idempotency key found in request params or headers.
- No `X-Idempotency-Key` header handled in controller.
- No unique constraint on transactions table that would prevent duplicate inserts.
- This is a state-mutating POST endpoint on a financial resource — **idempotency handling is absent** [FINTECH HIGH gap].

### Transaction State Machine
- States: `pending`, `completed`, `failed`, `reversed`
- Transitions observed in code:
  - `pending` → `completed`: after PaymentGateway.charge returns success
  - `pending` → `failed`: after PaymentGateway.charge returns failure or raises ChargeError
  - `reversed`: defined in enum, no transition logic found in this unit
- Terminal state `reversed` has no transition guard tested in this unit.

### Balance & Ledger Integrity
- `wallet.withdraw!` uses `with_lock` (pessimistic locking via `SELECT ... FOR UPDATE`) — concurrency control present.
- Balance check (`validate_sufficient_balance!`) is done outside the lock in TransactionService, before `wallet.withdraw!` is called — classic TOCTOU pattern: check happens without holding the lock, creating a race window between check and deduct [FINTECH HIGH gap].
- No double-entry ledger pattern — single balance field updated directly.
- `deduct_balance!` skips withdrawal for `deposit` category — deposit path does not credit balance in this unit (no `wallet.deposit!` call observed for deposit category transactions).

### External Payment Integration
- `PaymentGateway.charge` called twice for payment category transactions: once via `TransactionService#charge_payment_gateway` at line 78, and once via `Transaction#notify_payment_gateway` after_create callback at line 28 in the model — **double-charge risk** [FINTECH CRITICAL gap].
- No webhook/callback endpoint for async gateway responses in this unit.
- No retry or reconciliation pattern for gateway timeouts in this unit.

### Regulatory & Compliance Fields
- No KYC/AML fields in this unit.
- Transaction limit: `amount <= 1_000_000` validated at model level [HIGH].
- No audit trail table or `created_by`/`ip_address` fields found.

### Concurrency & Data Integrity
- `wallet.withdraw!` uses `with_lock` — pessimistic lock present.
- Balance read-then-compare in `validate_sufficient_balance!` is outside the lock — TOCTOU race condition possible [FINTECH HIGH gap].
- No DB transaction wrapping the entire service flow (save! + withdraw! are separate operations — partial failure possible).

### Security & Access Control
- Authentication: `before_action :authenticate_user!` — all actions protected.
- Authorization: wallet scoped to `current_user.wallets.find_by(...)` — IDOR protection present for wallet ownership.
- Transaction responses only expose the creating user's data.
- Error response for insufficient balance leaks current balance value: `details: ["Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"]` — **sensitive data leak in error response** [FINTECH HIGH gap].
```
