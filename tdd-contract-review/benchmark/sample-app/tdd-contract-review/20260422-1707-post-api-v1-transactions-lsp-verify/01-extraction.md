---
schema_version: 2
unit: POST /api/v1/transactions
---

# Extraction: POST /api/v1/transactions

## Summary

- Symbols in call trees: 11
- Files in root set: 4
- Unresolved dispatches: 2
- External calls: 1
- Entry points declared: 1
- Critical mode: ON (reason: decimal(20,8) money columns on wallets.balance + transactions.amount; multi-currency state; outbound PaymentGateway charge)

## Entry points

- ROOT#1 -- POST /api/v1/transactions -> Api::V1::TransactionsController#create

## Files Examined

### Call trees

```tree
ROOT#1 -- POST /api/v1/transactions
  Api::V1::TransactionsController#create @ app/controllers/api/v1/transactions_controller.rb:37-53
    Api::V1::TransactionsController#set_wallet @ app/controllers/api/v1/transactions_controller.rb:66-72
    Api::V1::TransactionsController#transaction_params @ app/controllers/api/v1/transactions_controller.rb:74-76
    TransactionService#call @ app/services/transaction_service.rb:12-38
      TransactionService#validate_wallet_active! @ app/services/transaction_service.rb:42-44
      TransactionService#validate_currency_match! @ app/services/transaction_service.rb:46-50
      TransactionService#validate_sufficient_balance! @ app/services/transaction_service.rb:52-58
      TransactionService#build_transaction @ app/services/transaction_service.rb:66-75
      TransactionService#deduct_balance! @ app/services/transaction_service.rb:60-64
        Wallet#withdraw! @ app/models/wallet.rb:25-33
      TransactionService#charge_payment_gateway @ app/services/transaction_service.rb:77-90
        [external -> payment-gateway] PaymentGateway.charge
      Transaction#notify_payment_gateway @ app/models/transaction.rb:27-34
        [dup -> TransactionService#charge_payment_gateway]
    Api::V1::TransactionsController#serialize_transaction @ app/controllers/api/v1/transactions_controller.rb:78-90
    [unresolved] before_action :authenticate_user! at app/controllers/api/v1/transactions_controller.rb:6 -- ApplicationController auth chain not present in fixture; current_user resolved at runtime
    [unresolved] rescue chain on Transaction#save! / Wallet#withdraw! validations -- ActiveRecord::RecordInvalid raised at runtime; rescue blocks resolve message text dynamically (transaction_service.rb:27-37)
```

### Root set

- db/schema.rb -- migration-snapshot-fallback (authoritative current schema for users/wallets/transactions; decimal precision and constraints read here)
- db/migrate/003_create_transactions.rb -- migration-snapshot-fallback (cross-checked transactions column defaults: status='pending', category='transfer')
- db/migrate/002_create_wallets.rb -- migration-snapshot-fallback (cross-checked wallets defaults: balance=0, status='active', unique [user_id,currency])
- db/migrate/001_create_users.rb -- migration-snapshot-fallback (FK target for transactions.user_id and wallets.user_id)

### Not examined

- config/routes.rb -- not present in fixture; route assumed conventional `POST /api/v1/transactions -> Api::V1::TransactionsController#create` per controller path/action
- app/controllers/application_controller.rb -- not present in fixture; `before_action :authenticate_user!` and `current_user` referenced but framework parent stubbed; treated as `[unresolved]`
- config/initializers/payment_gateway.rb -- not present in fixture; PaymentGateway constant has no in-repo definition (LSP `definition` for PaymentGateway returned []), confirming SDK/library is the outbound boundary
- spec/factories/* -- no FactoryBot factory files present in fixture
- app/models/user.rb -- read for FK relationship verification only; out of unit's contract surface (no fields written by this endpoint)
- app/controllers/api/v1/wallets_controller.rb -- different resource; out of unit scope for POST /api/v1/transactions

## Checkpoint 1: Contract Type Coverage

| Type | Status | Evidence |
|---|---|---|
| API inbound | Extracted | Api::V1::TransactionsController#create (app/controllers/api/v1/transactions_controller.rb:37-53); params.require(:transaction).permit(...); render json shapes at lines 47, 50; serialize_transaction at lines 78-90 |
| DB | Extracted | transactions table (db/schema.rb:32-46); wallets table (db/schema.rb:20-30) read for preconditions; Transaction model enums (app/models/transaction.rb:7-13); Wallet model enum (app/models/wallet.rb:7) |
| Outbound API | Extracted | PaymentGateway.charge (transaction_service.rb:77-83 + transaction.rb:27-34); LSP definition returned []; no in-repo client — SDK interface is the boundary |
| Jobs | Not detected | no ActiveJob/Sidekiq/perform_later references in call tree; PaymentGateway.charge is invoked synchronously |
| UI Props | Not applicable | server-side JSON API; no React/Vue component props |

## Checkpoint 2: File closure

Every own-node in the call tree descends from ROOT#1 (POST /api/v1/transactions -> Api::V1::TransactionsController#create); LSP `references` on TransactionService#call returned a single caller (transactions_controller.rb:44), confirming the unit's reach. Both `[unresolved]` lines are acknowledged: the `before_action :authenticate_user!` chain has no ApplicationController file in this fixture (called out explicitly under "Not examined"), and the ActiveRecord rescue chain inside TransactionService#call is dispatched at runtime by Rails validation framework. The Root set covers the contract-relevant environment available in this fixture: db/schema.rb (authoritative current schema) plus migrations for column-default cross-checks; absent infrastructure (routes.rb, ApplicationController, PaymentGateway initializer, FactoryBot factories) is enumerated under "Not examined" so reviewers can verify nothing reachable was skipped.

## Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb (create action, lines 37-53)
        app/services/transaction_service.rb
        app/models/transaction.rb
        app/models/wallet.rb
Framework: Rails 7.1 / RSpec

API Contract (inbound):
  POST /api/v1/transactions

    Input:
      request header: Authorization (bearer token, required) [HIGH]
        — enforced by before_action :authenticate_user! (transactions_controller.rb:6)
      request field: transaction.amount (decimal-as-string or numeric, required, > 0, <= 1_000_000) [HIGH]
        — Transaction model: numericality { greater_than: 0, less_than_or_equal_to: 1_000_000 } (transaction.rb:15)
        — TransactionService coerces via BigDecimal(@params[:amount].to_s) before balance compare (transaction_service.rb:53)
        — also constrained by wallet.balance via validate_sufficient_balance! (transaction_service.rb:52-58)
      request field: transaction.currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH]
        — Transaction model: inclusion in %w[USD EUR GBP BTC ETH] (transaction.rb:16)
        — must equal wallet.currency per validate_currency_match! (transaction_service.rb:46-50)
      request field: transaction.wallet_id (integer, required) [HIGH]
        — set_wallet scopes lookup to current_user.wallets.find_by(id: ...) (transactions_controller.rb:67)
        — 422 "Wallet not found" if missing or not owned by current_user
      request field: transaction.description (string, optional, max: 500 chars) [HIGH]
        — Transaction model: length { maximum: 500 } (transaction.rb:18)
      request field: transaction.category (string, optional, enum: transfer/payment/deposit/withdrawal, default: 'transfer') [HIGH]
        — default applied in TransactionService#build_transaction (transaction_service.rb:72)
        — when 'payment' triggers TransactionService#charge_payment_gateway (transaction_service.rb:22-24)
        — when 'deposit' skips wallet.withdraw! in deduct_balance! (transaction_service.rb:60-64)

    Assertion (verify in happy path):
      response field: transaction.id (integer) [HIGH]
      response field: transaction.amount (string, decimal-as-string via .to_s) [HIGH]
      response field: transaction.currency (string) [HIGH]
      response field: transaction.status (string, enum: pending/completed/failed/reversed) [HIGH]
      response field: transaction.description (string, nullable) [HIGH]
      response field: transaction.category (string, enum: transfer/payment/deposit/withdrawal) [HIGH]
      response field: transaction.wallet_id (integer) [HIGH]
      response field: transaction.created_at (string, ISO8601 via .iso8601) [HIGH]
      response field: transaction.updated_at (string, ISO8601 via .iso8601) [HIGH]

    Error response shape (422):
      response field: error (string, human-readable message) [HIGH]
      response field: details (array<string>) [HIGH]
        — InsufficientBalance variant emits "Current balance: #{@wallet.balance}, requested: #{@params[:amount]}" (transaction_service.rb:35)

    Status codes: 201 (created), 422 (validation failed / wallet not found / insufficient balance / currency mismatch / wallet inactive / payment gateway error), 401 (unauthenticated)

DB Contract:

  Input (preconditions — set in test setup):
    db field (input): wallet.status — must be 'active' (enum values: active/suspended/closed) [HIGH]
      — checked by TransactionService#validate_wallet_active! via @wallet.active? (transaction_service.rb:42-44)
      — Wallet model enum (wallet.rb:7); schema.rb:25 default 'active', NOT NULL
    db field (input): wallet.balance — must be >= requested amount; decimal(20,8), NOT NULL, DEFAULT 0 [HIGH]
      — checked by TransactionService#validate_sufficient_balance! (transaction_service.rb:52-58)
      — schema.rb:24
    db field (input): wallet.currency — must equal request currency; string NOT NULL; in: USD/EUR/GBP/BTC/ETH [HIGH]
      — checked by TransactionService#validate_currency_match! (transaction_service.rb:46-50)
      — schema.rb:22; Wallet model inclusion (wallet.rb:9); unique [user_id, currency] index (schema.rb:28)
    db field (input): wallet.user_id — must equal current_user.id (FK) [HIGH]
      — set_wallet scopes via current_user.wallets.find_by (transactions_controller.rb:67)
      — schema.rb:21 NOT NULL, indexed, FK to users
    db field (input): user.id — current_user must exist [HIGH]
      — schema.rb:11-18 (id, email, name, encrypted_password, timestamps)

  Assertion (postconditions — verify after request):
    db field (assertion): transaction.id (bigint, PK, auto) [HIGH]
    db field (assertion): transaction.user_id (bigint, NOT NULL, FK -> users.id) [HIGH]
      — set via @user.transactions.build (transaction_service.rb:67); schema.rb:33, FK schema.rb:48
    db field (assertion): transaction.wallet_id (bigint, NOT NULL, FK -> wallets.id) [HIGH]
      — set via wallet: @wallet (transaction_service.rb:68); schema.rb:34, FK schema.rb:49
    db field (assertion): transaction.amount (decimal precision:20 scale:8, NOT NULL) [HIGH]
      — schema.rb:35
    db field (assertion): transaction.currency (string, NOT NULL; in: USD/EUR/GBP/BTC/ETH) [HIGH]
      — schema.rb:36; Transaction model inclusion (transaction.rb:16)
    db field (assertion): transaction.status (string, NOT NULL, DEFAULT 'pending'; enum: pending/completed/failed/reversed) [HIGH]
      — schema.rb:37; Transaction model enum (transaction.rb:7)
      — written 'pending' on create; updated to 'completed' (success) or 'failed' (gateway non-success) in charge_payment_gateway (transaction_service.rb:85-89); ChargeError exception aborts before update (status remains 'pending')
    db field (assertion): transaction.description (string, nullable, max length 500) [HIGH]
      — schema.rb:38 (no NOT NULL); Transaction model length (transaction.rb:18)
    db field (assertion): transaction.category (string, NOT NULL, DEFAULT 'transfer'; enum: transfer/payment/deposit/withdrawal) [HIGH]
      — schema.rb:39; Transaction model enum (transaction.rb:8-13)
    db field (assertion): transaction.created_at (datetime, NOT NULL, auto) [HIGH]
      — schema.rb:40
    db field (assertion): transaction.updated_at (datetime, NOT NULL, auto) [HIGH]
      — schema.rb:41
    db field (assertion): wallet.balance — decremented by transaction.amount (only when category != 'deposit') [HIGH]
      — TransactionService#deduct_balance! -> Wallet#withdraw! within with_lock (wallet.rb:25-33)
      — assert exact post-balance value, not "decreased"
    db field (assertion): wallet.updated_at — must change after withdraw! [MEDIUM]
      — Wallet#withdraw! calls update! which touches updated_at

Outbound API:
  PaymentGateway.charge(amount:, currency:, user_id:, transaction_id:)
    — SDK/library interface (no in-repo HTTP client; LSP `definition` on PaymentGateway returned [])
    — Treated as the outbound boundary
    — Triggered when transaction.category == 'payment'
    — Two call sites in this unit (DOUBLE-CALL HAZARD):
        a) TransactionService#charge_payment_gateway (transaction_service.rb:77-83) — invoked from #call when transaction.payment?
        b) Transaction#notify_payment_gateway (transaction.rb:27-34) — after_create callback when payment?
      Both fire on the same payment transaction within one request → likely double charge unless gated by external idempotency

    Assertion (verify correct params sent to PaymentGateway.charge):
      outbound request field: amount (decimal, equals transaction.amount) [HIGH]
      outbound request field: currency (string, equals transaction.currency) [HIGH]
      outbound request field: user_id (integer, equals current_user.id) [HIGH]
      outbound request field: transaction_id (integer, equals persisted transaction.id) [HIGH]

    Input (set via mock — upstream untrusted, validate each):
      outbound response field: success? (boolean) [HIGH]
        — true → transaction.update!(status: 'completed') (transaction_service.rb:86)
        — false → transaction.update!(status: 'failed') (transaction_service.rb:88)
      outbound response field: PaymentGateway::ChargeError (exception path) [HIGH]
        — rescued at transaction_service.rb:36-37 → Result error: 'Payment processing failed'
        — note: thrown exception leaves transaction.status as 'pending' (no update applied)
      outbound response field: (no transaction_id / external reference parsed) [MEDIUM]
        — code reads only response.success?; reconciliation reference field absent
============================
```

## Money-Correctness Dimensions (critical mode)

| Dimension | Finding | Severity |
|---|---|---|
| Money & Precision | wallets.balance and transactions.amount both `decimal(20,8)` — exact type, no float anti-pattern. TransactionService coerces param via `BigDecimal(@params[:amount].to_s)` before compare (transaction_service.rb:53). | HIGH-coverage (good) |
| Currency pairing | Every amount has a paired currency (request, transaction row, wallet row). Inclusion list `%w[USD EUR GBP BTC ETH]` mixes zero-decimal? No — none of the listed currencies are zero-decimal, but `decimal(20,8)` is wider than fiat needs and may silently truncate beyond 8 dp for high-precision crypto inputs. | MEDIUM |
| Minor-unit convention | Schema uses one global `decimal(20,8)` regardless of currency. JPY (zero-decimal) would accept fractional amounts up to 8 dp without rejection — contract gap. | MEDIUM (ETH/BTC OK at 8dp; JPY/KRW would silently store fractions if added later) |
| Idempotency | No idempotency_key / X-Idempotency-Key handled in controller. State-mutating financial POST without idempotency. | HIGH gap |
| State machine | Statuses: `pending`, `completed`, `failed`, `reversed`. Transitions found: `pending → completed` (gateway success), `pending → failed` (gateway non-success). `reversed` defined but no transition logic in this unit. ChargeError leaves status at `pending` (orphan-pending risk). | HIGH gap (orphan-pending + missing reversed transition guards) |
| Balance & Ledger | `Wallet#withdraw!` uses `with_lock` (pessimistic) but `validate_sufficient_balance!` reads balance OUTSIDE the lock (transaction_service.rb:54) — classic TOCTOU; concurrent debits can both pass the check. No double-entry ledger; balance updated directly. No DB transaction wrapping `transaction.save!` + `wallet.withdraw!` + `PaymentGateway.charge` — partial-failure money loss risk. | HIGH gap |
| External payment integration | DOUBLE-CALL: PaymentGateway.charge fires both from `TransactionService#charge_payment_gateway` and `Transaction#notify_payment_gateway` after_create callback for the same payment transaction. No retry/reconciliation logic. No webhook intake. | CRITICAL gap |
| Refunds & reversals | `reversed` status enum exists; no refund/reverse endpoint or transition logic in this unit. | OUT OF UNIT (informational) |
| Fees & Tax | No fee or tax fields. Server stores raw amount only. | N/A for this endpoint |
| Holds & Authorizations | No auth/capture distinction; one-shot charge. No `pending_balance` separate from `balance`. | N/A |
| Time, Settlement & Cutoffs | No settlement window logic. `created_at`/`updated_at` are wall-clock; no business-day handling. | N/A for this endpoint |
| FX & Currency Conversion | Hard-rejected via `validate_currency_match!`; no FX path. | N/A |
| Concurrency & Data Integrity | TOCTOU on balance check (above). Withdraw! is locked but the surrounding service flow is not transactional. No deadlock prevention for multi-resource ops. No queue dedup (PaymentGateway has no idempotency key passed). | HIGH gap |
| Position & Inventory | Not applicable (cash wallet, not asset position). | N/A |
| Transaction limits | `amount <= 1_000_000` validated at model. No daily/monthly aggregate limit; no per-user limit. Currency of limit not normalized (1_000_000 BTC ≠ 1_000_000 USD). | HIGH gap (currency-blind limit) |

## API-Security Dimensions (critical mode)

| Dimension | Finding | Severity |
|---|---|---|
| Authentication | `before_action :authenticate_user!` enforced (transactions_controller.rb:6). Unauthenticated → 401. ApplicationController not present in fixture — auth method dispatch is `[unresolved]`. | HIGH-coverage (assuming standard Devise/JWT chain) |
| Authorization (IDOR) | Wallet ownership scoped via `current_user.wallets.find_by(id: ...)` (transactions_controller.rb:67) — IDOR-safe for wallet_id. Transaction is built off `@user.transactions.build` (transaction_service.rb:67) — IDOR-safe for transaction creation. | HIGH-coverage (good) |
| Privilege escalation | No role/scope checks; all authenticated users can create transactions. No admin-only path. | LOW (no roles defined in fixture) |
| Resource enumeration | bigint sequential PKs for transactions/wallets — IDs are guessable; offset by ownership check. | MEDIUM (mitigated by ownership) |
| Amount tampering | Server stores client-submitted `amount` directly without recomputing fees/totals (no fees in this endpoint). | LOW (no derived totals) |
| Negative-amount bypass | Transaction model: `numericality { greater_than: 0 }` (transaction.rb:15) — rejected. | HIGH-coverage (good) |
| Rate limiting | No rate-limit middleware referenced in unit; no Rack::Attack config in fixture. | HIGH gap (financial endpoint without rate limit) |
| Sensitive data in error responses | `InsufficientBalanceError` details include raw wallet.balance: `"Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"` (transaction_service.rb:35) — leaks live balance to caller in 422 body. | HIGH gap (PII-adjacent leak) |
| Sensitive data in list responses | (Out of unit scope — see GET /api/v1/transactions.) | OUT OF UNIT |
| API key scoping | No API key abstraction observed; auth is bearer-token user-level. | N/A |
| High-value approval | `amount <= 1_000_000` enforced; no MFA/approval threshold for high-value transfers. | MEDIUM gap |
| Injection | `description` permitted as freeform string, length-limited to 500. No HTML sanitization (returned as-is in JSON — XSS risk only if downstream renders unsanitized). Amount/currency are typed/whitelisted — safe from SQLi via ActiveRecord. | MEDIUM (description echo) |
| Audit trail | No audit table, no `created_by`/`ip_address`/`request_id` columns on transactions. Failed mutations (422) not persisted. | HIGH gap (financial mutation without audit record) |
| KYC/AML | No KYC fields, no sanctions screening hook. | OUT OF UNIT (informational) |
| PII in test data | Not assessable from extraction; check fixtures (none present). | INFORMATIONAL |
| Webhook trust | No webhook intake in this unit; PaymentGateway is only outbound. | N/A |
