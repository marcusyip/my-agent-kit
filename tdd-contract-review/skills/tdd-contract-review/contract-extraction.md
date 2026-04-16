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

**Only classify as `outbound response field:` if the call crosses a process or network boundary.** This means:

**IS outbound (extract as outbound response field):**
- HTTP requests to 3rd-party APIs (Stripe, Twilio, payment gateways, quote feeds)
- Message queue publishing (Kafka, RabbitMQ, SQS)
- External cache calls (Redis, Memcached) when used as a shared service
- Webhook/callback calls to external systems

**IS NOT outbound — do NOT extract at all (these are implementation, not contract boundaries):**
- Internal domain services injected as interfaces (`orderService`, `validateService`, `userCouponRepo`) — these run in-process in the same codebase. Do NOT list them in the extraction. Their behavior is tested implicitly through the API endpoint.
- Internal repositories that wrap DB queries — the DB fields are already extracted from schema/model files as `db field:`. Do NOT also list the repository as outbound.
- Internal validators, formatters, or utility services — implementation details, invisible to the contract

**How to tell the difference:** trace the service/interface to its implementation. If the implementation makes an HTTP call, sends a message, or calls an external system → outbound. If the implementation queries the DB or runs in-process logic → not outbound. When in doubt, check for HTTP client imports (`HTTParty`, `Faraday`, `net/http`, `axios`, `fetch`, `requests`, `httpx`) in the implementation.

**Priority order for identifying the outbound boundary:**

1. **HTTP endpoint URL** (best) — trace to the actual HTTP call in the wrapper:
   `POST https://api.stripe.com/v1/charges`
2. **SDK/library interface** (good) — when using an SDK that abstracts the HTTP layer:
   `stripe.charges.create(amount:, currency:, source:)`
3. **Never** — internal service wrappers, domain services, repositories:
   ~~`paymentService.process()`~~ ← this is NOT the boundary, it's implementation

Extract from the boundary, not the wrapper:
- **API endpoint or SDK call**: the actual external interface being called
- **Request params**: fields sent in the request body/query/headers (amount, currency, user_id, etc.)
- **Response fields**: fields parsed from the response body (success?, transaction_id, status, amount — upstream is untrusted, each field needs validation)
- **HTTP-level handling**: status codes expected (200, 4xx, 5xx), timeout, malformed response

**How to extract — dig deep, don't stop at the first layer:**

Finding the actual outbound boundary often requires tracing through 2-3 levels of abstraction. Do NOT stop at the handler or the first service method. Follow the call chain until you find the HTTP client call or SDK invocation.

Example trace:
```
handler.CreateOrder()
  → orderService.Create()          ← internal service, keep tracing
    → paymentClient.Charge()       ← wrapper, keep tracing
      → http.Post("https://...")   ← FOUND IT. This is the boundary.
```

Steps:
1. Find the service/client call in the handler
2. Read that service/client file — find the method implementation
3. If it calls another internal method, follow that too
4. Stop when you find: `http.Post()`, `axios.post()`, `HTTParty.post()`, `fetch()`, `requests.post()`, `Stripe::Charge.create()`, or similar
5. Extract the URL, request body fields, response parsing from THAT level

If you cannot find the actual HTTP call (e.g. the SDK completely hides it), use the SDK interface as the boundary (e.g. `stripe.charges.create(amount:, currency:)`).

Both request params and response fields are contract fields — request params are assertions, response fields need validation scenarios (mismatch, null, malformed).

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
  Input (preconditions — set in test setup):
    db field (input): wallet.balance — amount constrained by balance (balance >= amount) [HIGH]
    db field (input): wallet.status — wallet must be active [HIGH]
    db field (input): wallet.currency — currency must match wallet currency [HIGH]

  Assertion (postconditions — verify after request):
    db field (assertion): transaction.user_id (integer, NOT NULL, FK) [HIGH]
    db field (assertion): transaction.wallet_id (integer, NOT NULL, FK) [HIGH]
    db field (assertion): transaction.amount (decimal(20,8), NOT NULL) [HIGH]
    db field (assertion): transaction.currency (string, NOT NULL) [HIGH]
    db field (assertion): transaction.status (string, enum: pending/completed/failed/reversed) [HIGH]
    db field (assertion): transaction.description (string, nullable) [HIGH]
    db field (assertion): transaction.category (string, enum: transfer/payment/deposit/withdrawal) [HIGH]

Outbound API:
  POST https://api.paymentgateway.com/v1/charges
  (wrapper: PaymentGateway.charge, triggered when category == 'payment')
  — OR if SDK-based: stripe.charges.create(amount:, currency:, source:)
    Assertion (verify correct params sent to external API):
      outbound request field: amount (decimal) [HIGH]
      outbound request field: currency (string) [HIGH]
      outbound request field: user_id (integer) [HIGH]
    Input (set via mock — upstream untrusted, validate each):
      outbound response field: status_code (HTTP status) [HIGH] — 200/500/timeout
      outbound response field: success? (boolean) [HIGH] — true/false/ChargeError
      outbound response field: transaction_id (string, nullable) [MEDIUM] — reconciliation
============================
```
