# TODOS

## Deferred from plan-eng-review (2026-04-17)

### Scalability — Incremental Mode
**Skipped in current PR.**
What: `incremental` argument to re-use `.tmp/extraction.md` if source files haven't changed (mtime check).
Why: At 50+ files, full runs cost $5-15. Incremental reduces CI cost by 80-90% for typical PRs.
Depends on: disk-based intermediate writes landing first.
Blocked by: cache invalidation is tricky (model version change, reference file update not caught by mtime).

## Deferred from plan-eng-review (2026-04-20)

### Auto-detect `generated-from` via glob heuristic
**Surfaced during v0.37.0 eng review (parseable call-tree extraction).**
What: when the extraction agent lists a code-generated file as an own-node
leaf (e.g., `prisma/client/index.d.ts`, `api/grpc/transaction.pb.go`), the
parser auto-suggests the `generated-from <source>` root-set tag via a glob
match against a known pattern library (`*.pb.{go,py,rb}`, `prisma/client/*`,
`**/__generated__/**`, `*_pb.js`, `*.gen.ts`, `schema.gen.go`).

Why: B25 (file-existence + line-range sanity) will false-fail on regenerated
files whose line numbers drift every build. v0.37.0 relies on the agent
manually tagging them, which they'll forget in fintech audits using gRPC
stubs or Prisma-generated types. The heuristic prevents silent quality
regressions without expanding scope at v0.37.0 ship time.

Pros: catches the class of error without manual tagging; compounds across
benchmark units that use codegen; framework-adjacent (per-language globs,
not per-framework routing), so stays within the plugin's framework-agnostic
constraint if the glob library is kept minimal.

Cons: glob library becomes maintenance surface (Prisma renames `client/` to
`generated/` in future versions; gRPC's Python stubs differ from Ruby's).
Per-language patterns fight the framework-agnostic ethos. A false positive
(tagging a hand-written `pb.go` file) suppresses B25 for code that should
be checked.

Context: v0.37.0 ships with `generated-from` as a voluntary tag. Agents
must remember to apply it; B25 exempts tagged files. The eng review flagged
this as a quiet gameability surface: any agent that simply never uses the
tag silently over-trusts line ranges in regenerated code. Implementation
should wait until we have at least one real benchmark unit using gRPC or
Prisma so the glob patterns are calibrated against actual codegen output,
not guessed.

Depends on: v0.37.0 shipped; at least one benchmark unit exercising codegen.

Blocked by: deciding where the glob list lives (per-user extensible config
vs. a static file shipped with the plugin).

## Landed

### TypeScript support in `lsp_tree.py` — landed 2026-04-23
Shipped `--lang ts` (handles `.ts` and `.tsx`, including React / React
Native function components, hooks, and class components) via
`scripts/callsites_ts.py` (tree-sitter-typescript). Symbol grammar mirrors
the Ruby/Solargraph convention (`Foo#bar`, `Foo.bar`, `Foo`, `bar`).
Fixture: `benchmark/sample-app-ts/` (screen + hook + service + model, no
`node_modules` — external hooks deliberately tag as `[external]`).
Design notes: `benchmark/notes/lsp-tree-ts-options.md`. TS files are
pre-opened at startup so ts-server's project graph resolves cross-file
`definition` calls through imports; Ruby/Go servers index on startup and
don't need this.

Follow-ups deferred: JS-only (`.js`/`.jsx`) dispatch; destructured
assignment reconstruction (today `const [items, setItems] = useState(...)`
reports `setItems` as `symbol-not-found` because ts-server points at a
tuple-element position).

## Deferred from plan-ceo-review (2026-04-17)

### Stateful resumption and gate-failure retry (Approach B)
**Deferred in v0.31.0 UX pass.**
What: new entry points that reuse an existing run directory instead of starting over.
- `resume <rundir>` to pick up from the last completed checkpoint in `$RUN_DIR`.
- `remerge <rundir>` to re-run Step 6c (merge) using existing sub-files in `$RUN_DIR` without re-extracting or re-auditing.
- Gate failures (Checkpoint 1, Step 6b sub-file shape, Checkpoint 2) offer "retry this step" as a visible option in the checkpoint prompt instead of hard-stopping.

Why: today a gate failure after Step 6b burns 3 to 5 minutes of parallel gap analysis and forces a restart from Step 1. The revise loop handles content fixes but not step-level recovery. Stateful resume also unblocks future CI integration where re-running a single step is the right granularity.

Depends on: a small state file in `$RUN_DIR` recording which steps have passed their GATE, which agent last wrote each file, and the arguments used. Without this, `resume` and `remerge` cannot know what is safe to reuse.

Blocked by: state-model design. What invalidates a checkpoint? Source-file mtime change between runs, model version, reference-file edits? Same invalidation question as the Incremental Mode entry above and should share an answer.

Related: Incremental Mode (above) likely converges on the same state file.
