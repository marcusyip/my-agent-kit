---
schema_version: 2
unit: POST /api/v1/transactions
---

# Extraction: POST /api/v1/transactions

## Summary

Contract sources by type:
- API inbound:
  - app/controllers/api/v1/transactions_controller.rb (TransactionsController#create)
- DB:
  - db/schema.rb
  - app/models/transaction.rb
  - app/models/wallet.rb
- Outbound API:
  - config/initializers/payment_gateway.rb (PaymentGateway SDK)
- Jobs: Not detected
- UI Props: Not applicable

- LSP calls: 3 document_symbols, 14 definitions, 0 references
- Critical mode: OFF

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
    [unresolved] rescue_from error handler dispatch at app/controllers/api/v1/transactions_controller.rb:50 -- ApplicationController rescue_from chain; error renderer resolved at runtime
```

### Root set

- db/schema.rb -- migration-snapshot-fallback
- db/migrate/003_create_transactions.rb -- migration-snapshot-fallback
- config/routes.rb:47 -- route-definition
- config/initializers/payment_gateway.rb -- annotation-config
- spec/factories/transactions.rb -- factory
- db/seeds.rb -- seed
- app/controllers/application_controller.rb -- implicitly-invoked (before_action :authenticate_user!)
- app/controllers/application_controller.rb -- dispatched-at-runtime (rescue_from StandardError handler chain)

### Not examined
- app/controllers/api/v1/wallets_controller.rb -- different resource; out of unit scope for POST /api/v1/transactions

## Checkpoint 1: Contract Type Coverage

| Type | Status | Evidence |
|---|---|---|
| API inbound | Extracted | Api::V1::TransactionsController#create |
| DB | Extracted | transactions table; db/schema.rb |
| Outbound API | Extracted | PaymentGateway.charge |
| Jobs | Not detected | no ActiveJob/Sidekiq references |
| UI Props | Not applicable | API-only endpoint |

## Checkpoint 2: File closure

Root set includes the route-definition, migration snapshots, payment gateway
initializer, fixture/seed sources, and application controller whose before_action
chain is implicitly invoked. Unresolved dispatch (rescue_from) is acknowledged
and the responsible file is in the root set. All own-nodes descend from a
declared entry point.
