<!-- version: 0.28.0 -->
# Contract Extraction Reference

Detailed guidance for Step 3 of the TDD Contract Review workflow.

## Output File Shape (01-extraction.md)

`$RUN_DIR/01-extraction.md` MUST open with three mandatory sections in this order. Writing these sections verbatim (structure, headings, and row labels) is non-negotiable — the orchestrator greps for literal strings to gate Checkpoint 1. Deviate and the gate fails.

### 1. `## Summary`

Scannable one-screen overview shown at Checkpoint 1 before the user is asked to proceed. Bullets only, 4-8 lines max. No prose.

```
## Summary

- Total fields extracted: <N>
- Contract matrix: API: <N> | DB: <N> | Outbound: <N> | Jobs: <N|N/A> | UI Props: <N|N/A>
- Critical mode: ON (reason: <one-line signal, e.g., "decimal column `balance` in db/schema.rb">) OR OFF
- Files examined: <N> source, <N> DB schema, <N> outbound, <N> other
```

### 2. `## Files Examined`

Bullet list of every file read, grouped into four categories. Always include all four headings; write `- (none)` under any empty category. Never omit a category.

```
## Files Examined

**Source:**
- `path/to/handler.rb` — primary unit handler
- `path/to/service.rb` — downstream helper invoked by handler

**DB schema:**
- `db/schema.rb` (or `db/structure.sql`) — consolidated current state
- `app/models/*.rb` — logical contract (enums, validations, defaults in code)
- `db/migrate/*.rb` — list ONLY if no schema snapshot exists (fallback)

**Outbound clients:**
- `ExternalSDK.method` — referenced at `file:line`, SDK boundary

**Other:**
- (list anything else opened during extraction; '- (none)' if nothing)
```

### 3. `## Checkpoint 1: Contract Type Coverage`

STRICT table. Do NOT rename, reorder, or embellish row labels.

- Row labels MUST be exactly these 5 strings, in this order: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`.
- Do NOT write `API contract (inbound)`, `DB contract`, `Job/message consumer contract`, `UI props contract`, or any variant. Put context in the Notes column only.
- Column header MUST be: `| Contract Type | Status | Fields | Notes |`
- Status MUST be one of exactly: `Extracted` | `Not detected` | `Not applicable`.

```
## Checkpoint 1: Contract Type Coverage

| Contract Type | Status | Fields | Notes |
|---|---|---|---|
| API inbound | Extracted | 8 | request params + headers counted |
| DB | Extracted | 12 | from schema.rb + model files, not handler code |
| Outbound API | Extracted | 6 | actual HTTP URL or SDK interface |
| Jobs | Not applicable | — | no async job triggered by this unit |
| UI Props | Not applicable | — | server-side API, no UI component |
```

Status semantics:
- `Extracted`: this unit interacts with this contract type and fields are listed below.
- `Not detected`: this unit could plausibly use this type but no evidence in source. Investigate before marking.
- `Not applicable`: this contract type cannot apply to this unit (e.g., a consumer has no inbound API).

### After the three mandatory sections

Produce the Contract Extraction Summary (typed field prefixes per field — see "Contract Extraction Summary Example" at the bottom of this file). If critical mode is on, follow the Summary with separate Money-correctness dimensions and API-security dimensions tables (per `money-correctness-checklists.md` and `api-security-checklists.md`).

### Failure handling

If a contract type cannot be identified (e.g., no DB schema found), keep the Checkpoint 1 row with status `Not detected` or `Not applicable` (never leave blank) and note the reason in the Notes column.

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

**Source priority — read the schema snapshot + model files, NOT migrations.** Migrations are a changelog, not a source of truth: a column added then removed across migrations produces a false contract. The snapshot file (`db/schema.rb`, `db/structure.sql`, `schema.prisma`, Drizzle `schema.ts`) is the consolidated current state; it is the authoritative physical contract. The model/entity file carries the logical contract (enum declarations, validations, defaults declared in app code, associations). Read migrations ONLY when no snapshot exists.

How to extract per framework:
- **Rails:** `db/schema.rb` (preferred) or `db/structure.sql` for columns/types/constraints/indexes; `app/models/*.rb` for enums, validations, associations, defaults. Migrations are fallback only.
- **Go:** current-schema SQL dump if the repo has one, plus struct tags (`db:`, `gorm:`). Migration files only if no snapshot exists.
- **TypeScript (Prisma):** `schema.prisma` — single source of truth (both logical and physical in one file).
- **TypeScript (Drizzle / TypeORM):** schema / entity files carry the current shape; no migration read needed.
- **Python (Django):** `models.py` is both snapshot and model — Django has no separate snapshot. Do NOT read Django migrations.
- **Python (SQLAlchemy + Alembic):** SQLAlchemy model files. Alembic migrations only as fallback when models are incomplete.

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
- **HIGH**: Explicitly declared in code (e.g. `params.require(:currency)`, struct field with `json:"currency"` tag, TypeScript prop type definition, DB column in schema snapshot or model file)
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
    Input:
      request field: amount (decimal, required, > 0, <= 1_000_000) [HIGH]
      request field: currency (string, required, in: USD/EUR/GBP/BTC/ETH) [HIGH]
      request field: wallet_id (integer, required) [HIGH]
      request field: description (string, optional, max: 500) [HIGH]
      request field: category (string, optional, enum: transfer/payment/deposit/withdrawal, default: transfer) [HIGH]
      request header: Authorization (bearer token, required) [HIGH]
    Assertion (verify in happy path):
      response field: id (integer) [HIGH]
      response field: amount (string, decimal-as-string) [HIGH]
      response field: currency (string) [HIGH]
      response field: status (string) [HIGH]
      response field: description (string, nullable) [HIGH]
      response field: category (string) [HIGH]
      response field: wallet_id (integer) [HIGH]
      response field: created_at (datetime, ISO8601) [HIGH]
    Status codes: 201, 422, 401, 500

  GET /api/v1/transactions
    Input:
      request field: page (integer, optional) [MEDIUM]
      request field: per_page (integer, optional, default: 25) [MEDIUM]
    Assertion (verify in happy path):
      response field: transactions (array) [HIGH]
      response field: meta.total (integer) [HIGH]
      response field: meta.page (integer) [HIGH]
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
