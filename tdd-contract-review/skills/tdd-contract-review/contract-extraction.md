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

- External service name and request params (fields sent: amount, currency, user_id, etc.)
- Response fields received (fields returned: success?, transaction_id, status_code, amount, currency — upstream is untrusted, each field needs validation)
- Error handling for external failures (timeout, 500, malformed response)

How to extract: read HTTP client calls (`HTTParty`, `Faraday`, `net/http`, `axios`, `fetch`, `requests`, `httpx`), identify request params sent AND response fields parsed. Both are contract fields — request params are assertions, response fields need validation scenarios (mismatch, null, malformed).

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
    Request params:
      - currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH confidence]
      - amount (decimal, required, > 0, <= 1_000_000) [HIGH confidence]
      - wallet_id (integer, required) [HIGH confidence]
      - description (string, optional, max: 500) [HIGH confidence]
      - category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH confidence]
    Response fields:
      - id (integer) [HIGH confidence]
      - amount (string, decimal-as-string) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - status (string) [HIGH confidence]
      - description (string, nullable) [HIGH confidence]
      - category (string) [HIGH confidence]
      - wallet_id (integer) [HIGH confidence]
      - created_at (datetime, ISO8601) [HIGH confidence]
    Status codes: 201, 422, 401, 500
    Auth: before_action :authenticate_user!

  GET /api/v1/transactions
    Request params:
      - page (integer, optional) [MEDIUM confidence]
      - per_page (integer, optional, default: 25) [MEDIUM confidence]
    Response fields:
      - transactions (array) [HIGH confidence]
      - meta.total (integer) [HIGH confidence]
      - meta.page (integer) [HIGH confidence]
    Status codes: 200, 401

DB Contract:
  Transaction model:
    - user_id (integer, NOT NULL, FK) [HIGH confidence]
    - wallet_id (integer, NOT NULL, FK) [HIGH confidence]
    - amount (decimal(20,8), NOT NULL) [HIGH confidence]
    - currency (string, NOT NULL) [HIGH confidence]
    - status (string, enum: pending/completed/failed/reversed) [HIGH confidence]
    - description (string, nullable) [HIGH confidence]
    - category (string, enum: transfer/payment/deposit/withdrawal) [HIGH confidence]

  Business rules:
    - amount must be > 0 and <= 1_000_000 [HIGH confidence]
    - currency must match wallet currency [HIGH confidence]
    - wallet must be active [HIGH confidence]
    - amount constrained by wallet balance (service checks balance >= amount) [HIGH confidence]

Outbound API:
  PaymentGateway.charge (when category == 'payment'):
    Request params (assert correct values sent):
      - amount (decimal) [HIGH confidence]
      - currency (string) [HIGH confidence]
      - user_id (integer) [HIGH confidence]
    Response fields (upstream untrusted — validate each):
      - success? (boolean) [HIGH confidence]
      - transaction_id (string, nullable) [MEDIUM confidence]
      - status_code (HTTP status) [HIGH confidence]
    Response handling:
      - On success: status → completed [HIGH confidence]
      - On failure: status → failed [HIGH confidence]
      - On ChargeError: returns 422 [HIGH confidence]
============================
```
