# LSP vs Read vs Grep — when each is the right tool (study note)

For Step 3 call-tree construction in `tdd-contract-review`, the three tools answer
different question types. Using the wrong one is either slow (Grep where LSP
would be precise) or wrong (LSP where semantics are what's actually asked).

---

## The three-way split

### LSP (`document_symbols` / `definition` / `references`) — **structural**

| Op | "What question does this answer?" | Editor equivalent |
|---|---|---|
| `document_symbols(file)` | What named things are declared in this file? | Outline / breadcrumbs |
| `definition(file, line, col)` | Where is this identifier declared? | Cmd-click / F12 |
| `references(file, line, col)` | Who uses this declaration? | Find All References |

These are the **call-tree questions**: where is X defined, who calls X, who
implements interface X. LSP resolves them with type-system precision that Grep
on identifiers can't match — Grep on `Call(` matches every `.Call(` across the
codebase regardless of receiver type; `definition` resolves exactly one target.

### Read — **semantic**

Questions about what a symbol *does*, not where it lives:

- "Is amount capped at 1,000,000?"
- "What currencies does this enum allow?"
- "What JSON keys does this response produce?"
- "What does this `before_action` filter actually check?"

LSP returns the symbol's location — you still open the file to see the body.
This is why the skill's 01-extraction has to Read every root-set file even
after LSP identifies them: the call tree is the scaffolding, the field-level
contract is the content.

### Grep — **string-keyed**

Things LSP doesn't index because they're not symbols:

- HTTP route literals (`"POST /api/v1/transactions"`)
- Metric names, feature-flag keys, Datadog/Sentry tags
- Dynamic-dispatch map keys (`handlers["refund"]`)
- Raw SQL strings, template paths
- Environment variable names

Grep is correct for these — no other tool can do it.

---

## The seed problem

LSP needs a **starting symbol**. When the unit is specified as a route string
(`POST /api/v1/transactions`), there's a one-hop bootstrap from URL → handler
where LSP can't help:

```
Entry style                     Seed resolution
-----------                     ---------------
Rails routes.rb (symbol DSL)    Grep once in config/routes.rb
net/http ServeMux (string key)  Grep for the URL pattern
Framework with annotations      Read the annotation literally
Already have `Controller#Action` Go straight to LSP document_symbols
```

After that one bootstrap hop, every subsequent edge is pure LSP
(`definition` → next file, `document_symbols` → next symbol's range,
`references` → implementers of interfaces).

---

## Dynamic dispatch — tag `[unresolved]`, don't guess

LSP is a static tool. When dispatch happens at runtime, LSP sees the *shape*
but not the wiring. Don't try to resolve these with Grep and pretend the answer
is authoritative — mark them `[unresolved]` in the call tree so the reader
knows the branch was deliberately left incomplete:

- `map[string]Handler{...}[kind](...)` — runtime key
- `reflect.ValueOf(x).Method("Charge").Call(...)`
- Codegen artifacts whose inputs aren't on disk (sqlc, protoc-gen-go) — the
  generated code *is* on disk and LSP sees it, but the link back to the `.sql`
  or `.proto` is not type-system-visible
- Rails `send(:method_name)` / `public_send` / `before_action :name`
- Spring `@Autowired`, `@RequestMapping`, DI container lookups
- Go `//go:generate` outputs if the generator isn't committed

---

## Worked example — `POST /api/v1/transactions` on sample-app-go

```
seed: TransactionsHandler.Create                        (bootstrap: Grep route OR given)
  ↓ document_symbols(handler/transactions.go)           → method ranges
  ↓ definition on h.repo.FindWalletForUser(...)         → store/memory.go
  ↓ definition on h.service.Call(...)                   → service/transaction_service.go
      ↓ document_symbols(service/transaction_service.go)
      ↓ definition on w.Withdraw(...)                   → model/wallet.go
      ↓ definition on s.gateway.Charge(...)             → payment/gateway.go (interface)
          ↓ references on Gateway.Charge                → payment/gateway.go StubGateway
```

Every arrow = one `lsp_query.py` call. Zero Grep in the tree itself. The set of
files the tree touches (`handler/`, `store/`, `service/`, `model/`, `payment/`)
IS the root set — LSP produced it as a side effect.

To extract **per-field contracts** from those files (e.g. "amount must be
positive, ≤ 1,000,000, non-zero"), you still Read each one. The tree tells you
which files to open; Read tells you what's inside them.

---

## Summary rule

> **LSP first, Read second, Grep last.** If the question is "where / who",
> it's LSP. If it's "what does this do", it's Read. If the key is a string
> literal and not a symbol, it's Grep. Runtime dispatch beyond interfaces gets
> `[unresolved]`, not a guess.

## Source

Derived interactively 2026-04-22 while building
`benchmark/sample-app-go/scripts/lsp-bench.py`. See
`skills/tdd-contract-review/contract-extraction.md` §"LSP-assisted call-tree
construction (mandatory algorithm)" for the skill-side enforcement.
