# sample-app-go

Go fixture for benchmarking the `tdd-contract-review` plugin against `gopls`.

**LSP is not optional here.** The skill's Step 3 call-tree algorithm requires
`document_symbols` + `definition` + (where needed) `references` per root-set file.
This fixture exists to exercise that mandatory path on a non-Ruby codebase.

Mirrors the domain of `../sample-app/` (fintech: users / wallets / transactions) so
call-tree and contract extraction can be compared across languages on the same
business logic.

## Layout

```
cmd/server/main.go                  # net/http router, wires handlers
internal/handler/transactions.go    # GET/POST/GET:id for /api/v1/transactions
internal/handler/wallets.go         # GET/POST/PATCH for /api/v1/wallets
internal/handler/auth.go            # X-User-Id header "auth"
internal/service/transaction_service.go  # validation + charge gateway
internal/model/{user,wallet,transaction}.go
internal/payment/gateway.go         # Gateway interface + StubGateway
internal/store/memory.go            # repository (validates, paginates, IDOR-scoped reads)
internal/db/migrations/*.sql        # contract source for DB extraction
scripts/lsp-bench.py                # LSP benchmark driver (see below)
targets.json                        # LSP target manifest
golden/                             # recorded LSP responses, diffed on verify
```

Stdlib only — no module deps — so `go build ./...` works offline and gopls indexes
without `go mod download`.

## Seeded gaps

- `handler/wallets.go#Update`: 422 response leaks `balance`, `user_id`, raw error
  (matches the Ruby PATCH /wallets/:id bug).
- No tests anywhere (intentional — the skill should report coverage gaps).

## LSP benchmark

`targets.json` is the manifest. Each entry names an LSP call to make, identified
by its **enclosing Go symbol** and the **call-text** to point at — never by
line/col, which drift on any edit. The driver (`scripts/lsp-bench.py`) resolves
positions at runtime (bounded regex inside the symbol body), invokes
`../../scripts/lsp_query.py`, and compares the response to `golden/<id>.json`.

```bash
./scripts/lsp-bench.py            # verify — exit 0 if all match, 1 on drift
./scripts/lsp-bench.py --record   # capture new goldens
./scripts/lsp-bench.py --target def-service-charge-gateway   # one target
```

Current targets: 5 `document_symbols` (one per root-set file), 4 `definition`
(handler → service → model → interface), 1 `references` (interface → impl).
Together they exercise every LSP operation the skill's Step 3 call-tree
algorithm relies on.

Paths in recorded goldens are normalised to project-relative
(`file://./internal/...`) so checkouts on different machines diff cleanly.
`gopls` on PATH is required (`go install golang.org/x/tools/gopls@latest`).

## Running

```bash
go build ./...
go run ./cmd/server
```

Then `X-User-Id: 1` header on requests. The in-memory store starts empty — wire up
seed data from a test or shell as needed.
