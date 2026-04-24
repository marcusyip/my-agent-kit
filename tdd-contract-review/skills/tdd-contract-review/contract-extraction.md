<!-- version: 0.37.0 -->
# Contract Extraction Reference

Detailed guidance for Step 3 of the TDD Contract Review workflow.

## Output File Shape (01-extraction.md)

`$RUN_DIR/01-extraction.md` MUST open with YAML front-matter followed by the mandatory sections in this order:

1. `## Summary`
2. `## Entry points`
3. `## Files Examined` (with `### Call trees`, `### Root set`, optional `### Not examined`)
4. `## Checkpoint 1: Contract Type Coverage`
5. `## Checkpoint 2: File closure`

Writing these verbatim (headings, front-matter keys, row labels) is non-negotiable. The orchestrator greps for literal strings to gate Checkpoint 1 and Checkpoint 2. Deviate and the gate fails.

See `benchmark/fixtures/v2-example/01-extraction.md` in the plugin repo for a complete worked example of a critical-mode-off Rails endpoint.

### 0. Front-matter

Every extraction MUST open with YAML front-matter containing `schema_version: 2` and `unit:`.

```
---
schema_version: 2
unit: POST /api/v1/transactions
---
```

- `schema_version: 2` fixes the extraction to the call-tree grammar documented below.
- `unit:` is the unit identifier passed to the orchestrator. Free-form string; must match the verb+path, class name, or file path used to invoke the skill.

### 1. `## Summary`

Scannable one-screen overview shown at Checkpoint 1. Bullets only, no prose. Counts MUST reconcile with the body — every number here must match what the reader can count in the corresponding section.

```
## Summary

- Symbols in call trees: <N>     # count of own-nodes across all ROOT#n trees
- Files in root set: <N>         # count of bullets under ### Root set
- Unresolved dispatches: <N>     # count of [unresolved] lines inside the tree
- External calls: <N>            # count of unique [external -> slug] entries
- Entry points declared: <N>     # count of bullets under ## Entry points
- LSP calls: <D> document_symbols, <F> definitions, <R> references   # scripted tools: equals counts in $RUN_DIR/lsp/; native LSP: self-report
- Critical mode: ON (reason: <one-line signal>) OR OFF
```

### 2. `## Entry points`

One bullet per declared entry point. Each `ROOT#n` referenced in the call trees below MUST appear here.

```
## Entry points
- ROOT#1 -- POST /api/v1/transactions -> Api::V1::TransactionsController#create
```

Format by unit type:
- HTTP: `ROOT#<n> -- <VERB> <path> -> <Class>#<method>`
- Job/consumer: `ROOT#<n> -- <JobClass> -> <Class>#<method>`
- CLI/script: `ROOT#<n> -- <command> -> <Class>#<method>` or `<file>:<line>`

Multiple entry points are allowed when the unit is a class with several public methods reached from the same route tree, but most HTTP endpoints and jobs have exactly one ROOT.

### 3. `## Files Examined`

The body of the extraction. Three subsections, in order.

#### 3a. `### Call trees`

Indent-based hierarchy inside a fenced ` ```tree ` block. One sub-tree per entry point. The ROOT line is the header; children indent by 2 spaces per level.

Five line forms are allowed inside the tree:

| Form | Example | Meaning |
|---|---|---|
| ROOT | `ROOT#1 -- POST /api/v1/transactions` | Entry point header. Must match a bullet in `## Entry points`. |
| own-node | `TransactionService#call @ app/services/transaction_service.rb:12-38` | A method/class you read. `path:start-end` is the file and line range. |
| dup | `[dup -> TransactionService#charge_payment_gateway]` | Reference to an own-node already listed earlier in the tree. Use when the same symbol is reached via two paths — do not list its body twice. |
| external | `[external -> payment-gateway] PaymentGateway.charge` | Call that crosses a process/network boundary. Slug is lowercase-kebab-case and MUST match an `annotation-config` root-set entry. |
| unresolved | `[unresolved] rescue_from error handler dispatch at app/controllers/application_controller.rb:50 -- error renderer resolved at runtime` | Runtime-dispatched call (rescue_from, `send`, `method_missing`, DI lookup). Include a brief reason for why static resolution failed. |

Grammar demo (one line per form; see `benchmark/fixtures/v2-example/01-extraction.md` for a full worked tree):

````
```tree
ROOT#1 -- POST /api/v1/transactions
  Api::V1::TransactionsController#create @ app/controllers/api/v1/transactions_controller.rb:37-53
    TransactionService#charge_payment_gateway @ app/services/transaction_service.rb:77-90
      [external -> payment-gateway] PaymentGateway.charge
    Transaction#notify_payment_gateway @ app/models/transaction.rb:27-34
      [dup -> TransactionService#charge_payment_gateway]
    [unresolved] rescue_from dispatch at app/controllers/api/v1/transactions_controller.rb:50 -- error renderer resolved at runtime
```
````

Rules:
- Every own-node appears exactly once. A second reach uses `[dup -> Symbol]`.
- Indent with spaces only (2 per level). No tabs.
- Line ranges must be inside the file's actual bounds.
- Files that aren't reached via a call (config, fixtures, migrations) do NOT go in the tree — they go in Root set below.

#### 3b. `### Root set`

Bullet list of every file examined that is NOT a call-tree own-node. These are files read for contract context but not directly called by the unit. Each entry gets a tag from the vocabulary below, annotated with `-- <tag>` and optionally a parenthetical detail. See `benchmark/fixtures/v2-example/01-extraction.md` for a full worked root set.

Tag vocabulary:

| Tag | When to use |
|---|---|
| `migration-authoritative` | Migration file is the current source of truth (no schema snapshot exists) |
| `migration-snapshot-fallback` | Migration file read alongside a schema snapshot for historical context |
| `route-definition` | Routes file where the unit's route is declared. Use `path:line` format. |
| `annotation-config` | Config file declaring an external boundary (payment gateway initializer, HTTP client config, API base URL). The slug declared here MUST match the `[external -> slug]` in the tree. |
| `factory` | Test factory / fixture definition for a model this unit touches |
| `seed` | Seed data file referenced by this unit |
| `middleware` | Middleware in the request chain (Rack, Express, Django middleware) |
| `di-config` | DI container wiring (Spring, NestJS module, Guice binding) |
| `dispatched-at-runtime` | File invoked via runtime dispatch (`rescue_from`, `send`, `method_missing`). Annotate with the dispatch mechanism. |
| `implicitly-invoked` | File invoked by framework convention, not direct call (before_action, lifecycle hooks, route concerns). Annotate with the hook name — keep the detail ≥ 10 chars so reviewers can spot what's actually hooked. |
| `generated-from <source>` | Generated code — annotate the source schema/definition (e.g., `generated-from schema.proto`, `generated-from openapi.yaml`). Tagging exempts own-nodes that point at this file from line-range sanity checks. |
| `test-fixture-shared` | Test fixture shared across multiple specs, relevant for this unit's setup |

#### 3c. `### Not examined` (optional)

Bullets for files in the same package/module that a reasonable reviewer might expect to see listed, with a one-line justification for skipping. Prevents false "you forgot to read X" failures at Checkpoint 2.

```
### Not examined
- app/controllers/api/v1/wallets_controller.rb -- different resource; out of unit scope for POST /api/v1/transactions
```

Omit the subsection entirely if there are no candidates worth calling out.

### 4. `## Checkpoint 1: Contract Type Coverage`

STRICT table. Do NOT rename, reorder, or embellish row labels.

- Row labels MUST be exactly these 5 strings, in this order: `API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`.
- Do NOT write `API contract (inbound)`, `DB contract`, `Job/message consumer contract`, `UI props contract`, or any variant. Put context in the Evidence column only.
- Column header MUST be: `| Type | Status | Evidence |` (3 columns).
- Status MUST be one of exactly: `Extracted` | `Not detected` | `Not applicable`.

```
## Checkpoint 1: Contract Type Coverage

| Type | Status | Evidence |
|---|---|---|
| API inbound | Extracted | Api::V1::TransactionsController#create |
| DB | Extracted | transactions table; db/schema.rb |
| Outbound API | Extracted | PaymentGateway.charge |
| Jobs | Not detected | no ActiveJob/Sidekiq references |
| UI Props | Not applicable | API-only endpoint |
```

Status semantics:
- `Extracted`: this unit interacts with this contract type and fields are listed in the Contract Extraction Summary below.
- `Not detected`: this unit could plausibly use this type but no evidence in source. Investigate before marking.
- `Not applicable`: this contract type cannot apply to this unit (e.g., a background consumer has no inbound API).

### 5. `## Checkpoint 2: File closure`

Short prose paragraph (~3 sentences) asserting that the extraction is closed over the unit's dependencies:

- Every own-node in the call trees descends from a declared entry point.
- Every `[unresolved]` dispatch is either resolved elsewhere in the tree or acknowledged with its responsible file present in the Root set.
- Root set covers the contract-relevant environment (routes, schema, external-boundary config, middleware, fixtures).

See `benchmark/fixtures/v2-example/01-extraction.md` for a worked closure paragraph.

### After the mandatory sections

Produce the Contract Extraction Summary (typed field prefixes per field — see "Contract Extraction Summary Example" at the bottom of this file). If critical mode is on, follow the Summary with separate Money-correctness dimensions and API-security dimensions tables (per `money-correctness-checklists.md` and `api-security-checklists.md`).

### Failure handling

If a contract type cannot be identified (e.g., no DB schema found), keep the Checkpoint 1 row with status `Not detected` or `Not applicable` (never leave blank) and note the reason in the Evidence column.

## LSP-assisted call-tree construction (mandatory algorithm)

For building the `### Call trees` block, **LSP is mandatory, not optional.** This section is an algorithm, not guidance — sub-agents that skip steps to save time produce shallow trees that pass the markdown-shape gate but miss real branches.

Three tool paths are available. Pick by language + plugin availability:

- **`<plugin-root>/tdd-contract-review/scripts/lsp_tree.py` — preferred for Go, Ruby, TypeScript/TSX.** A standalone one-shot walker: given a seed symbol, it parses the file with an AST helper, walks every outgoing call via `definition`, and emits a nested tree. All LSP queries share a single language-server session, so the cold-start cost (~5–30s) is paid once per invocation, not once per call site. With `--run-dir $RUN_DIR`, every `definition` / `document_symbols` response is persisted under `$RUN_DIR/lsp/` using the same filename scheme `lsp_query.py` uses, giving a flat audit trail of every LSP call.
- **Native `LSP` tool — for other languages** (Python, Java, Rust, C#, Kotlin, Dart, etc.) when the dispatch prompt says `Native LSP tool available: yes` (the orchestrator's Step 2.5 check sets this from `~/.claude/plugins/installed_plugins.json`). Call `definition` / `implementations` / `references` directly on call sites — no scripted wrapper. Artifacts are not persisted under `$RUN_DIR/lsp/`; the `## Summary` LSP-calls line is a self-report in that case.
- **`<plugin-root>/tdd-contract-review/scripts/lsp_query.py`** — two roles: (a) resolve a single ambiguous dispatch mid-walk when `lsp_tree.py` flags `[unresolved]` and you want a targeted `definition` / `references`, or (b) last-resort fallback for non-lsp_tree languages when `Native LSP tool available: no`. Exposes `definition`, `document_symbols`, `references`.

**When in doubt, start with `lsp_tree.py`.** If the language is supported and the target is a standard call-tree walk from a seed symbol, one `lsp_tree.py` invocation replaces dozens of `lsp_query.py` calls. For unsupported languages, prefer the native `LSP` tool; drop to `lsp_query.py` only when the plugin is absent.

`lsp_tree.py` CLI:

```bash
SCRIPT="<plugin-root>/tdd-contract-review/scripts/lsp_tree.py"
# Symbol grammar: Go "(*Type).Method" / "Name"; Ruby "Foo#bar" / "Foo.bar" / "Foo";
# TypeScript "Foo#bar" / "Foo.bar" / "Foo" / "bar" (handles .ts AND .tsx / React / RN).
# ALWAYS pass --scope local — it trims stdlib / gem / node_modules edges from the
# rendered tree without suppressing the underlying LSP query (artifacts still persist).
"$SCRIPT" --lang go   --project <repo-root> --file <rel-path> --symbol "(*Handler).Create"            --scope local --run-dir $RUN_DIR
"$SCRIPT" --lang ruby --project <repo-root> --file <rel-path> --symbol "TransactionsController#create" --scope local --run-dir $RUN_DIR
"$SCRIPT" --lang ts   --project <repo-root> --file <rel-path> --symbol "TransactionScreen"            --scope local --run-dir $RUN_DIR
```

**`--scope local` is the default you want.** Without it, the rendered tree includes every stdlib, gem, or `node_modules` call on the path — `fmt.Sprintf`, `Hash#[]`, `console.log`, React's `useState` — which drowns the unit's real blast radius in noise. The flag trims external edges from the rendered tree only; the LSP `definition` query still runs for each call site and still writes its JSON artifact to `$RUN_DIR/lsp/`. Omit it (`--scope all`, the implicit default) only when you deliberately need to audit a dependency boundary.

Other flags: `--depth N` (cap walk depth, default 7), `--format json` (machine-readable tree in addition to the LSP artifacts).

The walker writes the rendered tree to `$RUN_DIR/tree__<file-slug>__<symbol-slug>.md`. Read it, paste the relevant subtree into the `### Call trees` fenced block of `01-extraction.md`, and proceed with the algorithm below for any parts the walker flagged `[unresolved]` or `[depth-cap]` that need deeper inspection.

**Algorithm — execute every step, in order, for every applicable target:**

1. **Seed.** Run `document_symbols` on the unit's entry source file to get accurate line ranges for the symbols it defines. Promote ONLY the symbol(s) the unit owns (e.g., for `POST /api/v1/transactions` on `TransactionsController#create`, that's `create` plus any `before_action` filters that gate it — not `index`, `show`, etc.). Use the LSP-returned ranges verbatim; do not estimate from a Read.

   **Coordinate convention.** LSP positions are 0-indexed (`line: 9` means file line 10). The own-node format `Symbol @ path:start-end` uses 1-indexed line numbers — add 1 to the LSP `line` field before writing.
2. **Walk every call site.** For EVERY call site inside EVERY own-node body, run `definition` on the call site's file:line:col. Treat every method invocation, function call, constant reference, and module access as a call site — do not pre-filter by guessing which ones "look interesting".
   - If `definition` returns a target file inside the project: promote the target to an own-node and go to step 3 for that file.
   - If `definition` returns an empty array (`[]`): mark the line `[unresolved]` in the tree with a one-line reason (`-- definition returned empty, runtime dispatch suspected` is a fine default). Do NOT silently substitute Read+Grep here — the empty result is the contract.
   - If `definition` returns a target outside the project (gem, stdlib, external SDK): emit `[external -> slug]` per the tree grammar.
3. **Recurse.** For each newly-promoted own-node file, run `document_symbols` (once per file — the wrapper auto-overwrites, so a repeat is cheap but adds no information). Then loop back to step 2 for every call site inside its own-nodes.
4. **Closure (optional).** Run `references` on the entry-point symbol when Checkpoint 2 needs to confirm test-file scope — the returned callers surface test files that exercise the unit. The gate does not require this call; skip it when the call tree from steps 1–3 is sufficient.

**Read+Grep is NOT an acceptable substitute for `definition`.** It is permitted ONLY for:
- **Contract field semantics** — validation rules, enum values, response shapes, request param keys, default values. LSP returns symbol locations, not what those symbols mean.
- **`definition` returned empty** — and only after you've marked the node `[unresolved]`. Using Grep to "fill in" what `definition` couldn't resolve is non-compliant: the contract is that the node was unresolvable, not that you grepped harder.
- **Runtime dispatch** — `before_action`, `rescue_from`, `send`, `method_missing`, DI container lookups. Mark `[unresolved]` and put the responsible file in the Root set with `dispatched-at-runtime` / `implicitly-invoked`. Solargraph (Ruby) is especially weak here.

A sub-agent that skips `definition` because it could "tell from the code" what the call resolves to is producing an unaudited tree. Run the LSP call.

**Mandatory `## Summary` line.** The Summary block in the extraction MUST report LSP call counts in this exact form:

```
- LSP calls: <D> document_symbols, <F> definitions, <R> references
```

When scripted tools are used (`lsp_tree.py` or `lsp_query.py`), these three counts equal the count of `document_symbols__*.json`, `definition__*.json`, and `references__*.json` files in `$RUN_DIR/lsp/`. When the native `LSP` tool is used for non-lsp_tree languages, there are no on-disk artifacts and the counts are a self-report for human reviewers.

CLI:

```bash
SCRIPT="<plugin-root>/tdd-contract-review/scripts/lsp_query.py"
"$SCRIPT" --lang ruby --project <repo-root> --run-dir $RUN_DIR document_symbols <file>
"$SCRIPT" --lang ruby --project <repo-root> --run-dir $RUN_DIR definition <file> <line> <col>
"$SCRIPT" --lang ruby --project <repo-root> --run-dir $RUN_DIR references <file> <line> <col>
```

**Always pass `--run-dir $RUN_DIR`.** With the flag set, the wrapper writes each query's JSON to `$RUN_DIR/lsp/<op>__<file-slug>__L<line>C<col>.json` and prints `WROTE: <path>` to stdout instead of dumping the body. Filenames are derived deterministically from the operation + file + position, so a repeat query overwrites the same file — that gives you an effective per-run cache and a flat audit trail of every LSP call the run made. Omit the flag only when running the script by hand to inspect a single response on stdout.

Languages: `ruby`, `typescript`, `javascript`, `go`, `python`, `java`, `rust`, `csharp`, `dart`, `kotlin`, `php`, `cpp`. The first call per language pays a one-time install cost (multilspy fetches the language server binary). Cold-start per invocation is ~5–30s; this is acceptable for call-tree work because accuracy beats latency at Step 3.

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
