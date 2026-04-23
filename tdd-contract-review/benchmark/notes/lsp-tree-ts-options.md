# TypeScript support in `lsp_tree.py` — design notes

Captured from a design conversation on 2026-04-23 while scoping the deferred
"TypeScript support in `lsp_tree.py`" entry in [TODOS.md](../../../TODOS.md).
These tables document the three parser options and the current per-language
status of the call-tree helpers, so a future implementer (or reviewer) does
not have to re-derive the comparison.

---

## Three options for extracting TS call sites

multilspy is only an LSP client — it never parses files itself. So "what
parser do we use for call-site enumeration?" is a separate question from
"what LSP server does multilspy talk to?". These three options differ only
in the parser column.

| Dimension | Opt 1: tree-sitter-typescript | Opt 2: tsc compiler API (Node) | Opt 3: LSP `semanticTokens` |
|---|---|---|---|
| **Where it runs** | In-process Python (PyPI wheel) | Node subprocess | Inside multilspy (LSP request) |
| **Parser quality** | Fuzzy on generics, decorators, type-only imports | Canonical — full TS semantics | Whatever ts-server emits (semantic, full resolution) |
| **Handles JSX → `createElement`** | Treats JSX as its own node shape; needs explicit handling | Yes, via TS AST | Depends on ts-server classification |
| **Handles React hooks (`useFoo`)** | Yes (appears as `call_expression`) | Yes | Yes — classified as `function` token |
| **Handles arrow-method-in-object (`obj = { bar: () => … }`)** | Yes | Yes | Yes |
| **Tagged templates (`` sql`…` ``)** | `tagged_template_expression`, not `call` — opt-in needed | Handled as CallExpression-equivalent | Classified as function invocation |
| **Decorators (`@Injectable()`)** | Parses but may not flag as call | Yes | Yes |
| **New runtime dependency** | `tree-sitter`, `tree-sitter-typescript` Python wheels | Node 20+, `typescript` npm pkg, `package.json` in plugin | None — multilspy already bundles ts-server |
| **Cold start** | ~50ms (wheel load) | ~500ms–1s (Node + tsc boot) | 0 (server already warm from definition calls) |
| **Per-file parse cost** | Fast (ms) | Slow (full type-check path unless `transpileOnly`) | Free — reuses LSP session |
| **Maintenance burden** | One Python file, matches `callsites.rb` pattern | Node dep drift, `ts-node`/ESM config churn | Depends on multilspy exposing `semanticTokens` (may need multilspy patch or raw JSON-RPC) |
| **Matches existing ethos** | Yes — same shape as Ruby/Go helpers | No — first Node dep in plugin | Yes — already using multilspy for everything else |
| **Risk of multilspy not exposing it** | N/A | N/A | **High** — needs a spike to verify |
| **Lines of code (rough)** | ~150 (new file) | ~100 TS + `package.json` + lockfile | ~50 if multilspy supports it; much more if not |
| **Best for** | Getting a working TS path quickly with the current pattern | Teams that already have a Node build | Staying pure-Python + minimizing new surface |

**TL;DR column picks:**
- Fastest path to working: **Opt 1**
- Most correct on exotic TS: **Opt 2**
- Least new surface if it works: **Opt 3** (but unknown until spiked)

---

## Per-language status of the call-tree helpers

The "parser" column (helper file + parser library) always runs *before*
multilspy's `definition` call — LSP has no "enumerate call sites in this
function body" primitive, so we parse ourselves to produce the `(line, col)`
positions multilspy then resolves. For every new language you need **both**
columns 2–3: a parser *and* an LSP server.

| Language | Callsite helper (this repo) | Parser in the helper | LSP server (via multilspy) | Status in `lsp_tree.py` |
|---|---|---|---|---|
| **Go** | `scripts/callsites.go` → compiled to `.bin/callsites` | `go/parser` (stdlib) | `gopls` | **Shipped** (`--lang go`) |
| **Ruby** | `scripts/callsites.rb` | Prism (stdlib on modern Ruby) | Solargraph | **Shipped** (`--lang ruby`) — needs brewed Ruby for Prism |
| **TypeScript** | *Missing* — proposed `scripts/callsites_ts.py` or `.ts` | Opt 1: `tree-sitter-typescript` · Opt 2: `tsc` · Opt 3: none (LSP `semanticTokens`) | `typescript-language-server` (wraps `tsserver`) | *Not yet* — this ticket |
| **JavaScript** | Would share the TS helper (JS ⊂ TS) | Same as TS | `typescript-language-server` | Covered by TS work |
| **Python** | None | — (would be `ast` stdlib if ever added) | `jedi-language-server` | Not planned — `contract-extraction.md` falls back to a manual walk via `lsp_query.py` |
| **Rust** | None | — (would be `syn` or tree-sitter) | `rust-analyzer` | Not planned |
| **Java** | None | — (would be JavaParser or tree-sitter) | Eclipse JDT LS | Not planned |
| **C#** | None | — | OmniSharp | Not planned |
| **Kotlin** | None | — | Kotlin LS | Not planned |
| **Dart** | None | — | Dart LS | Not planned |

Installed multilspy language-server coverage (from `scripts/.venv`):
`dart_language_server`, `eclipse_jdtls`, `gopls`, `jedi_language_server`,
`kotlin_language_server`, `omnisharp`, `rust_analyzer`, `solargraph`,
`typescript_language_server`.

---

## Outcome: shipped 2026-04-23

Opt 1 landed as `scripts/callsites_ts.py` + a `--lang ts` branch in
`lsp_tree.py`. Grammar Option A (`Foo#bar`, `Foo.bar`, `Foo`, `bar` — mirrors
the Ruby helper). Fixture: `benchmark/sample-app-ts/` (React Native-style
screen → hook → service → model, no `node_modules`).

One TS-specific wrinkle surfaced during end-to-end testing and got baked
into `lsp_tree.py`: **typescript-language-server only resolves cross-file
`definition` after the target file has been opened by the LSP client.**
Without the pre-open, `definition` on a use-site of an imported function
returns the *import binding* (the identifier on line 2 of the current file),
not the declaration in the source file. Fix: `preopen_typescript_project()`
walks `project/src/**/*.{ts,tsx}` at startup and opens each file before the
first query. Go/Ruby servers index the whole project on startup and don't
need this.

## Decision: Opt 1

Opt 3 was spiked on 2026-04-23 against the installed multilspy and ruled out.
Findings in `scripts/.venv/lib/python3.14/site-packages/multilspy/`:

- `language_server.py` exposes only `request_definition`, `request_references`,
  `request_completions`, `request_document_symbols`, `request_hover`, and
  `request_workspace_symbol`. No `request_semantic_tokens`.
- No `semantic` / `SemanticTokens` references anywhere in the package,
  including the low-level `lsp_protocol_handler/`.

Using semantic tokens would require patching/forking multilspy or dropping to
raw JSON-RPC — both more work than writing a tree-sitter helper. Revisit only
if multilspy adds semantic-tokens support upstream.

**Implementation path:** `scripts/callsites_ts.py` using
`tree-sitter-typescript`, emitting the same `{start_line, end_line, calls=[
{line, col, name}, …]}` JSON contract as `callsites.rb`. Opt 2 stays in
reserve only if we later need full generics/decorator fidelity.
