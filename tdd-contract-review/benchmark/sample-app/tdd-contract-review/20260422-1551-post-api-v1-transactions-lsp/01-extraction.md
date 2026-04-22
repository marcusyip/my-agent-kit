---
schema_version: 2
unit: POST /api/v1/transactions
---

# Extraction: POST /api/v1/transactions

## Summary

- Symbols in call trees: 13
- Files in root set: 4
- Unresolved dispatches: 2
- External calls: 1
- Entry points declared: 1
- Critical mode: ON (reason: decimal money fields amount/balance and PaymentGateway.charge outbound call)

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
    [unresolved] before_action :authenticate_user! at app/controllers/api/v1/transactions_controller.rb:6 -- ApplicationController not present in repo; current_user/authenticate_user! resolved at runtime
    [unresolved] after_create :notify_payment_gateway at app/models/transaction.rb:23 -- ActiveRecord callback dispatched at runtime
```

### Root set

- db/schema.rb -- migration-snapshot-fallback (authoritative DB snapshot for users/wallets/transactions tables)
- db/migrate/002_create_wallets.rb -- migration-snapshot-fallback (read alongside schema.rb to confirm wallet defaults)
- db/migrate/003_create_transactions.rb -- migration-snapshot-fallback (read alongside schema.rb to confirm transaction defaults)
- app/models/user.rb -- implicitly-invoked (current_user.transactions, current_user.wallets associations consumed by controller before_action chain)

### Not examined

- app/controllers/application_controller.rb -- file does not exist in this stripped sample-app; before_action :authenticate_user! and rescue_from chain resolve at runtime against absent base class. Acknowledged as [unresolved] in tree.
- config/routes.rb -- not present in sample-app; route declaration inferred from RESTful controller naming (POST /api/v1/transactions -> Api::V1::TransactionsController#create)
- config/initializers/payment_gateway.rb -- not present in sample-app; PaymentGateway is referenced but undeclared (stubbed in specs only). External boundary slug `payment-gateway` documented inline in the call tree.
- app/controllers/api/v1/wallets_controller.rb -- different resource; out of unit scope for POST /api/v1/transactions
- spec/factories/ -- directory does not exist in this sample-app

## Checkpoint 1: Contract Type Coverage

| Type | Status | Evidence |
|---|---|---|
| API inbound | Extracted | Api::V1::TransactionsController#create |
| DB | Extracted | transactions, wallets tables; db/schema.rb |
| Outbound API | Extracted | PaymentGateway.charge (SDK-style boundary; no HTTP wrapper present in repo) |
| Jobs | Not detected | no ActiveJob/Sidekiq references in call tree |
| UI Props | Not applicable | API-only endpoint |

## Checkpoint 2: File closure

Every own-node in the call tree descends from ROOT#1, with line ranges confirmed via LSP `document_symbols` against `transactions_controller.rb`, `transaction_service.rb`, `transaction.rb`, and `wallet.rb`. The two `[unresolved]` dispatches (`before_action :authenticate_user!` and the `after_create :notify_payment_gateway` ActiveRecord callback) are acknowledged: ApplicationController is absent from this stripped sample-app and the callback target is `[dup -> TransactionService#charge_payment_gateway]` already in the tree. Root set covers the authoritative DB snapshot, the two relevant migrations, and the User model that backs `current_user.transactions`/`.wallets`; configuration files (routes, initializers, factories) absent from the sample-app are explicitly listed under Not examined.

## CONTRACT EXTRACTION SUMMARY

```
Source: app/controllers/api/v1/transactions_controller.rb
Framework: Rails / RSpec

API Contract (inbound):
  POST /api/v1/transactions
    Input:
      request field: transaction.amount (decimal, required, > 0, <= 1_000_000) [HIGH]
      request field: transaction.currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH]
      request field: transaction.wallet_id (integer, required; must belong to current_user) [HIGH]
      request field: transaction.description (string, optional, max length 500) [HIGH]
      request field: transaction.category (string, optional, enum: transfer/payment/deposit/withdrawal, default 'transfer') [HIGH]
      request header: Authorization (bearer token, required — before_action :authenticate_user!) [MEDIUM — inferred; ApplicationController not in repo]
    Assertion (verify in happy path):
      response field: transaction.id (integer) [HIGH]
      response field: transaction.amount (string, decimal-as-string via .to_s) [HIGH]
      response field: transaction.currency (string) [HIGH]
      response field: transaction.status (string; 'pending'/'completed'/'failed' on create path) [HIGH]
      response field: transaction.description (string, nullable) [HIGH]
      response field: transaction.category (string) [HIGH]
      response field: transaction.wallet_id (integer) [HIGH]
      response field: transaction.created_at (datetime, ISO8601) [HIGH]
      response field: transaction.updated_at (datetime, ISO8601) [HIGH]
      response field: error (string; on 422) [HIGH]
      response field: details (array<string>; on 422) [HIGH]
    Status codes: 201 Created, 422 Unprocessable Entity (validation/wallet-not-found/currency mismatch/insufficient balance/gateway error), 401 Unauthorized (inferred from before_action), 500 Internal Server Error

DB Contract:
  Input (preconditions — set in test setup):
    db field (input): wallet.id — referenced via params[:transaction][:wallet_id] [HIGH]
    db field (input): wallet.user_id — must equal current_user.id (set_wallet scopes to current_user.wallets) [HIGH]
    db field (input): wallet.status — must be 'active' (validate_wallet_active!); enum: active/suspended/closed [HIGH]
    db field (input): wallet.currency — must equal request transaction.currency (validate_currency_match!) [HIGH]
    db field (input): wallet.balance — must be >= request amount (validate_sufficient_balance!); decimal(20,8), default 0.0, NOT NULL, >= 0 validation [HIGH]
    db field (input): user.id — current_user; FK source for transaction.user_id [HIGH]

  Assertion (postconditions — verify after request):
    db field (assertion): transaction.id (bigint, PK) [HIGH]
    db field (assertion): transaction.user_id (bigint, NOT NULL, FK -> users.id) [HIGH]
    db field (assertion): transaction.wallet_id (bigint, NOT NULL, FK -> wallets.id) [HIGH]
    db field (assertion): transaction.amount (decimal(20,8), NOT NULL, > 0, <= 1_000_000) [HIGH]
    db field (assertion): transaction.currency (string, NOT NULL, in USD/EUR/GBP/BTC/ETH) [HIGH]
    db field (assertion): transaction.status (string, NOT NULL, default 'pending'; enum values: pending/completed/failed/reversed; create path can set 'pending' -> 'completed' or 'pending' -> 'failed') [HIGH]
    db field (assertion): transaction.description (string, nullable, max length 500) [HIGH]
    db field (assertion): transaction.category (string, NOT NULL, default 'transfer'; enum values: transfer/payment/deposit/withdrawal) [HIGH]
    db field (assertion): transaction.created_at (datetime, NOT NULL) [HIGH]
    db field (assertion): transaction.updated_at (datetime, NOT NULL) [HIGH]
    db field (assertion): wallet.balance (decimal(20,8), NOT NULL; decremented by amount unless category == 'deposit') [HIGH]
    db field (assertion): wallet.updated_at (datetime; touched by withdraw!) [MEDIUM]

Outbound API:
  PaymentGateway.charge(amount:, currency:, user_id:, transaction_id:)
  (SDK-style call; no HTTP wrapper or initializer present in repo. Triggered when category == 'payment' via TransactionService#charge_payment_gateway; also via Transaction#notify_payment_gateway after_create callback — duplicate path on the same transaction.)
    Assertion (verify correct params sent to external API):
      outbound request field: amount (BigDecimal, mirrors transaction.amount) [HIGH]
      outbound request field: currency (string, mirrors transaction.currency) [HIGH]
      outbound request field: user_id (integer, current_user.id / transaction.user_id) [HIGH]
      outbound request field: transaction_id (integer, persisted transaction.id) [HIGH]
    Input (set via mock — upstream untrusted, validate each):
      outbound response field: success? (boolean) [HIGH] — true => transaction.status='completed'; false => transaction.status='failed'
      outbound response field: PaymentGateway::ChargeError (raised exception) [HIGH] — caught in TransactionService#call rescue chain; returns Result(success?: false, error: 'Payment processing failed', details: [e.message])
      outbound response field: <no transaction_id parsed> [HIGH] — wrapper does NOT capture or persist any external reference id; reconciliation gap
      outbound response field: <no amount echo validated> [HIGH] — wrapper does NOT verify gateway-returned amount matches sent amount; mismatch undetectable
      outbound response field: <no currency echo validated> [HIGH] — wrapper does NOT verify gateway-returned currency
```

## Money-correctness dimensions

| Dimension | Status / Evidence | Notes |
|---|---|---|
| Money & precision | `transaction.amount` and `wallet.balance` both `decimal(20,8)`; service uses `BigDecimal(@params[:amount].to_s)` in balance check; controller serializes amount via `.to_s` (string-as-decimal). NO floats. | Good: exact types. Gap: `decimal(20,8)` is the SAME column for USD (2dp), JPY (0dp), and BTC/ETH (8/18dp) — JPY would store 100x; ETH at 18dp would silently truncate. Currency-aware precision missing. |
| Idempotency | NO idempotency_key field on request; NO unique constraint that could dedupe a retry. POST is fully repeatable. | HIGH gap — duplicate submission creates duplicate charge + duplicate gateway call. |
| Transaction state machine | `transaction.status` enum: `pending/completed/failed/reversed`. Transitions on this path: `pending -> completed` (gateway success), `pending -> failed` (gateway failure). `reversed` never reached on this endpoint. | Gap: no guard against re-entering a terminal state; no test of `reversed` lifecycle. |
| Balance & ledger integrity | `Wallet#withdraw!` uses `with_lock` (SELECT ... FOR UPDATE) and validates `balance < amount` before update — pessimistic lock. BUT `validate_sufficient_balance!` runs OUTSIDE the lock against possibly-stale `@wallet.balance`. Save of transaction is in `TransactionService#call` outside any DB transaction wrapping the whole flow. | HIGH gap: TOCTOU between `validate_sufficient_balance!` and `withdraw!` (re-checked inside `withdraw!` so overdraft is technically prevented, but the resulting error path leaves a persisted `pending` transaction and no balance change). No double-entry ledger. |
| External payment integration | `PaymentGateway.charge` called twice per `category == 'payment'` request: once explicitly in `TransactionService#charge_payment_gateway`, once implicitly in `Transaction#after_create :notify_payment_gateway`. No retry, no reconciliation, no captured external id. | CRITICAL gap: double-charge guaranteed for payments. Status updated by service path only; callback path's response is discarded. |
| Refunds & reversals | Not implemented on this endpoint. `reversed` enum value exists but no path here uses it. | N/A for create. |
| Fees & tax | No fee/tax fields. | N/A. |
| Holds & authorizations | No authorize/capture distinction; charge is one-shot. | N/A. |
| Time, settlement, cutoffs | No cutoff or settlement timing logic. `created_at`/`updated_at` only. | N/A. |
| FX & currency conversion | `validate_currency_match!` rejects mismatch — no conversion ever performed. | Implicit policy: txn currency must equal wallet currency. |
| Concurrency & data integrity | `Wallet#withdraw!` uses `with_lock`. Whole `TransactionService#call` is NOT wrapped in `ActiveRecord::Base.transaction`, so `transaction.save!` + `wallet.withdraw!` + `gateway.charge` are not atomic. Callback `after_create` fires inside the implicit save transaction but gateway call is NOT idempotent. | HIGH gap: partial-failure window — transaction persisted, balance deducted, gateway call fails => leaves DB inconsistent with no rollback because `update!(status: 'failed')` runs in the rescue path. |
| Position & inventory | N/A — money domain only. | |
| Transaction limits | `validates :amount, numericality: { ... less_than_or_equal_to: 1_000_000 }` per-transaction cap only. No daily/monthly aggregate, no per-method limit. | Gap: no aggregate limit; cap is a single bare number with no currency awareness (1_000_000 BTC ≠ 1_000_000 USD). |

## API-security dimensions

| Dimension | Status / Evidence | Notes |
|---|---|---|
| Authentication | `before_action :authenticate_user!` declared; ApplicationController source not in repo — auth implementation runtime-resolved. | MEDIUM confidence on enforcement. Test must cover missing/expired/malformed token => 401. |
| Authorization (ownership / IDOR) | `set_wallet` scopes lookup to `current_user.wallets.find_by(id: ...)` — wallet IDOR is blocked (returns 422 'Wallet not found' for foreign wallet). `TransactionService#build_transaction` builds via `@user.transactions.build`, anchoring user_id to current_user. | Good. Add tests: foreign wallet_id => 422, no DB write, no gateway call. |
| Privilege escalation / role | No role gating; any authenticated user can create a transaction. | N/A unless role model exists upstream. |
| Resource enumeration | Sequential bigint IDs for wallets and transactions; ownership check on wallet only. Transaction.id leaked in response. | LOW risk on create; relevant for show/index endpoints. |
| Amount tampering | Server uses request `amount` directly to debit balance and call gateway; no client-supplied total/fee fields. Validation `> 0` and `<= 1_000_000` enforced server-side at model level. | Good. Add test: negative amount on this credit-shaped operation rejected (model `numericality: greater_than: 0` covers it). |
| Negative-amount bypass | Model validation `greater_than: 0` rejects negatives; `Wallet#withdraw!` raises ArgumentError for non-positive. | Good — assert in tests. |
| Rate limiting | NO rate-limit middleware visible in this sample-app. | HIGH gap — financial mutation endpoint with no throttle. |
| Sensitive data in error responses | 422 body returns `error` (e.g. "Insufficient balance (need X, have Y)") and `details` including `"Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"`. | MEDIUM gap: error message LEAKS current wallet balance back to caller. Even authenticated, this exposes balance in a path that should not. Wrap balance in generic 'Insufficient balance' message. |
| Sensitive data in list responses | Out of scope for create. | N/A. |
| API key scoping | No scopes implemented. | N/A. |
| High-value approval / MFA | No threshold-based MFA; only the `<= 1_000_000` per-tx hard cap. | Gap: large transactions get no extra scrutiny. |
| Injection (SQL / XSS / null bytes) | `description` reaches DB unsanitized; ActiveRecord parameterizes the INSERT, so no SQL injection. No HTML render path on create response. | Good for SQL. XSS deferred to consumer of the description field. |
| Audit trail & immutable records | NO audit table; only `created_at`/`updated_at` on the transaction itself. No actor capture, no IP, no request_id, no failed-attempt log. | HIGH gap — financial mutation with no audit trail. |
| KYC/AML/sanctions gating | No KYC fields, no sanctions screening on this path. | Out-of-scope for sample-app. |
| Webhook trust | This endpoint is an inbound API, not a webhook. PaymentGateway path is outbound only — no webhook handler in scope. | N/A here. |
