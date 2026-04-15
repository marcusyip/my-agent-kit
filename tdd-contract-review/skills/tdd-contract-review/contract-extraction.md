# Contract Extraction Reference

Detailed guidance for Step 3 of the TDD Contract Review workflow.

## Per-Framework Extraction

### API Contract (inbound endpoints)

- Request params: field name, type, required/optional, validation rules
- Response shape: field name, type, possible values
- Status codes: success, validation error, not found, unauthorized, server error

How to extract per framework:
- Rails: read controller actions for `params.require/permit`, serializer fields, `render json:` shapes, status codes
- Go: read handler functions for request struct fields, response struct fields, HTTP status codes
- Express/NestJS: read route handlers for request body/query/param types, response shapes
- Django/FastAPI: read view functions for serializer fields, request body models, response models

### DB Data Contract (models/schemas)

- Fields: name, type, constraints (NOT NULL, UNIQUE, DEFAULT)
- Data states: possible values for enum/status fields. **Exhaustively list every enum value** -- if a model defines `enum :status, { pending, completed, failed, reversed }`, all four values must appear in the extraction. Missing enum values are the most common source of missed gaps.
- Relationships: foreign keys, associations

How to extract per framework:
- Rails: read migration files + model files for columns, validations, associations, enum definitions
- Go: read struct tags (`db:`, `gorm:`), migration files, SQL schema files
- TypeScript: read Prisma schema, TypeORM entities, Drizzle schema
- Python: read SQLAlchemy models, Django models, Alembic migrations

### Job & Message Consumer Contract (async entry points)

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

### API Calls Contract (outbound service calls)

Extract the actual outbound HTTP API, not just the service layer wrapper:
- **API endpoint**: HTTP method + URL (e.g. `POST https://api.stripe.com/v1/charges`). Find this by reading the HTTP client call inside the wrapper method.
- **Request params**: fields sent in the request body/query/headers (amount, currency, user_id, etc.)
- **Response fields**: fields parsed from the response body (success?, transaction_id, status, amount — upstream is untrusted, each field needs validation)
- **HTTP-level handling**: status codes expected (200, 4xx, 5xx), timeout, malformed response

How to extract: read HTTP client calls (`HTTParty`, `Faraday`, `net/http`, `axios`, `fetch`, `requests`, `httpx`) inside service/wrapper classes. Trace from the wrapper method (e.g. `PaymentGateway.charge`) to the actual HTTP call to find the URL, HTTP method, request body shape, and response parsing. Both request params and response fields are contract fields — request params are assertions, response fields need validation scenarios (mismatch, null, malformed).

### UI Props Contract (components)

- Props: name, type, required/optional, default values
- Rendered states: loading, error, empty, populated
- User interactions and conditional rendering

How to extract: read React/Vue component prop types/interfaces, conditional rendering logic, state-dependent UI.

## Confidence Indicators

For each extracted contract field, assign a confidence level:
- **HIGH**: Explicitly declared in code (e.g. `params.require(:currency)`, struct field with `json:"currency"` tag, TypeScript prop type definition, DB column in migration)
- **MEDIUM**: Inferred from usage patterns (e.g. response body shape from `render json:`, DB query patterns)
- **LOW**: Guessed from naming conventions or indirect references

## Contract Extraction Summary Example

After extracting all contracts, produce a summary listing every contract field found BEFORE proceeding to Steps 4-6. This makes the analysis chain auditable and mitigates non-determinism.

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/controllers/api/v1/transactions_controller.rb
Framework: Rails/RSpec

API Contract (inbound):
  POST /api/v1/transactions
    request field: amount (decimal, required, > 0, <= 1_000_000) [HIGH]
    request field: currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH]
    request field: wallet_id (integer, required) [HIGH]
    request field: description (string, optional, max: 500) [HIGH]
    request field: category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH]
    request header: Authorization (bearer token, required) [HIGH]
    Status codes: 201, 422, 401, 500

  GET /api/v1/transactions
    request field: page (integer, optional) [MEDIUM]
    request field: per_page (integer, optional, default: 25) [MEDIUM]
    Status codes: 200, 401

DB Contract:
  db field: transaction.user_id (integer, NOT NULL, FK) [HIGH]
  db field: transaction.wallet_id (integer, NOT NULL, FK) [HIGH]
  db field: transaction.amount (decimal(20,8), NOT NULL) [HIGH]
  db field: transaction.currency (string, NOT NULL) [HIGH]
  db field: transaction.status (string, enum: pending/completed/failed/reversed) [HIGH]
  db field: transaction.description (string, nullable) [HIGH]
  db field: transaction.category (string, enum: transfer/payment/deposit/withdrawal) [HIGH]

  Business rules:
  db field: wallet.balance — amount constrained by balance (balance >= amount) [HIGH]
  db field: wallet.status — wallet must be active [HIGH]
  db field: wallet.currency — currency must match wallet currency [HIGH]

Outbound API:
  POST https://api.paymentgateway.com/v1/charges (via PaymentGateway.charge, when category == 'payment')
    Request params:
      outbound response field: PaymentGateway.charge.amount (decimal) [HIGH] — assert correct amount sent
      outbound response field: PaymentGateway.charge.currency (string) [HIGH] — assert correct currency sent
      outbound response field: PaymentGateway.charge.user_id (integer) [HIGH] — assert correct user_id sent
    Response:
      outbound response field: PaymentGateway.charge.status_code (HTTP status) [HIGH] — 200/500/timeout
      outbound response field: PaymentGateway.charge.success? (boolean) [HIGH] — true/false/ChargeError
      outbound response field: PaymentGateway.charge.transaction_id (string, nullable) [MEDIUM] — reconciliation
============================
```
