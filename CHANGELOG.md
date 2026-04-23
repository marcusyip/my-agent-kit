# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.44.0] - 2026-04-23

### tdd-contract-review

#### Changed
- **Step 2 renamed "Discovery" → "Preliminary Survey" and narrowed in scope.** The step's output is now explicitly marked "NOT authoritative" — it produces a rough DB-snapshot + model-class list to seed Step 3, and the authoritative call tree / DB touch set / outbound surface is built in Step 3 via `lsp_tree.py`. Dropped the standalone outbound-client discovery pass (outbound edges fall out of the LSP walk in Step 3) and restricted the DB pass to `schema.rb` / migrations + model class names (no more column-by-column guesswork). Step 3 prompt params updated to match.
- **Step 6 sub-agent prompts now splice skill sections inline via `<<<CONTEXT_PACK>>>` markers instead of instructing each agent to `Read` full skill files.** New Step 6a.1 pre-compiles 10 named packs (`PACK_SCENARIOS`, `PACK_OUTSHAPE_*`, `PACK_MODEL`, `PACK_MONEY_*`, `PACK_SECURITY_*`) by extracting just the relevant headings from `scenario-checklist.md`, `test-patterns.md`, `gap-analysis.md`, `money-correctness-checklists.md`, and `api-security-checklists.md`. Each per-type / F1 / F2 / merge agent receives only the packs it needs. Cuts sub-agent token spend ~50% in non-critical mode and ~70% in critical mode; DEEPEN REQUEST block on revise also points at `PACK_SCENARIOS` instead of the full file path.



### tdd-contract-review

#### Added
- **Go interface-hop in `scripts/lsp_tree.py`.** When the walker hits a method whose `definition` lands on a Go `interface { ... }` signature, it now issues a `textDocument/implementation` request at the original call site and descends into every concrete implementation returned by `gopls`. Previously the tree dead-ended at `Method @ path [symbol-not-found]` and the model/data layer was invisible. The interface node is rendered with an `[interface]` tag, each impl becomes a normal own-node child. A new `implementation__*.json` artifact is persisted under `$RUN_DIR/lsp/` for auditability.
- **`benchmark/check-lsp-tool.sh` — Go interface-hop regression guard.** Seeds `(*TransactionService).chargePaymentGateway`, asserts `[interface]` tag + `(*StubGateway).Charge` concrete impl + absence of `[symbol-not-found]` + presence of the implementation artifact. Fails loudly if a future refactor re-introduces the dead-end.
- **Native `LSP` tool added to `agents/staff-engineer.md` frontmatter.** Subagent can now call `definition` / `implementations` / `references` directly for languages `lsp_tree.py` doesn't cover (Python, Rust, Java, C#, Kotlin, Dart). Requires the user's Claude Code to have a code-intelligence plugin installed.
- **Step 2.5 LSP Plugin Preflight in `SKILL.md`.** One `AskUserQuestion` per run nudges the user to install a code-intelligence plugin when they haven't. Three options: `Yes — proceed` / `Not installed — proceed anyway` / `Not installed — stop to install` (clean abort, removes empty `$RUN_DIR`). The scripted LSP path runs either way; the preflight only affects whether the native `LSP` tool is available for non-lsp_tree languages.

#### Changed
- **Three-path LSP routing.** SKILL.md and contract-extraction.md now route by language + plugin availability: `lsp_tree.py` for Go/Ruby/TS (preferred), native `LSP` tool for other languages when the plugin is installed, `lsp_query.py` in two roles — (a) resolve a single ambiguous dispatch mid-walk, (b) last-resort fallback for non-lsp_tree languages when no plugin is installed. Previously `lsp_query.py` was the generic fallback for all non-lsp_tree work.
- **Previous-extraction check renumbered Step 2.5 → Step 2.6.** To make room for the new LSP preflight. Cross-references in `benchmark/test-plan.md` and `benchmark/notes/token-usage.md` updated.

#### Removed
- **LSP-utilization GATE (Step 3).** The gate counted `$RUN_DIR/lsp/*.json` artifacts and required `LSP_COUNT >= ROOT_SET_COUNT` AND `>= 1 definition`. Native LSP tool invocations leave no on-disk artifacts, so the gate would now always fail for non-lsp_tree languages using the native path. Removed rather than made language-aware — the shape gates (Checkpoint 1 / 2 / sub-files) still catch the user-visible failure modes; under-utilization is now surveilled by the `## Summary` self-report line only. The Revise checkpoint path still exists for user-initiated deepen requests.

## [0.42.1] - 2026-04-23

### tdd-contract-review

#### Changed
- **`SKILL.md` + `contract-extraction.md` now instruct agents to always pass `--scope local` to `lsp_tree.py`.** Without it, the rendered call tree includes every stdlib / gem / `node_modules` edge on the path (`fmt.Sprintf`, `Hash#[]`, React's `useState`, etc.) and drowns the unit's real blast radius in noise. The flag trims external edges from the rendered tree only; the underlying LSP `definition` query still runs and still writes its JSON artifact to `$RUN_DIR/lsp/`, so the Step 3 LSP-utilization GATE (artifact count) is unaffected.

#### Fixed
- **`SKILL.md` invocation: dropped the bogus `walk` subcommand.** v0.42.0 introduced `lsp_tree.py walk --lang ... <symbol>` — the script has no `walk` subcommand; the actual CLI is `--lang ... --project ... --file ... --symbol ...`. Agents copy-pasting the v0.42.0 line would have hit an arg-parse error on first invocation.

## [0.42.0] - 2026-04-23

### tdd-contract-review

#### Added
- **`scripts/lsp_tree.py --lang ts` — TypeScript / TSX support.** The standalone call-tree builder now handles `.ts` and `.tsx` files, including React and React Native function components, hooks, and class components. Closes the third stack in the benchmark roadmap (Go, Ruby, TypeScript) — the walker, cache, `--scope local` filter, and `--run-dir` artifact writer all reuse the existing language-agnostic machinery.
  - Call-site extraction lives in a new helper `scripts/callsites_ts.py` using `tree-sitter-typescript` (PyPI wheels; no Node dependency). Symbol grammar mirrors the Ruby/Solargraph convention: `Foo#bar` (instance method), `Foo.bar` (static · namespace member · object-literal arrow), `Foo` (class/function/const-arrow at module scope), `bar` (free function / hook at module scope).
  - **`preopen_typescript_project()`** walks `project/src/**/*.{ts,tsx}` at startup and opens each file in the LSP session before any query. Without this, `typescript-language-server`'s first cross-file `definition` call returns the local import binding instead of chasing through to the source file. Go / Ruby servers index the whole project on startup and don't need this.
- **`benchmark/sample-app-ts/`** — React Native-style fixture (screen + custom hook + service + model, no `node_modules`) that exercises the depth-5 TS walk end-to-end. External hooks deliberately tag as `[external]`.
- **`benchmark/notes/lsp-tree-ts-options.md`** — design notes capturing the parser-option comparison (tree-sitter vs. tsc API vs. multilspy `semanticTokens`), the per-language call-tree helper status matrix, and the outcome of the Opt 3 spike (multilspy exposes no `semanticTokens` path, so the tree-sitter helper wins on reduced surface area).

#### Changed
- **`SKILL.md` + `contract-extraction.md`** now surface `lsp_tree.py` as the preferred entry point for Go / Ruby / TS, so agents running the skill in other repos discover it. `lsp_query.py` stays as the per-call fallback for other languages (Python, Rust, Java, C#, Kotlin, Dart). Both the Step 3 LSP directive and the Checkpoint-1 deepen block now reference both scripts with language-based dispatch.

## [0.41.0] - 2026-04-23

### tdd-contract-review

#### Added
- **`scripts/lsp_tree.py` — standalone LSP-driven call-tree builder.** Given a seed symbol, walks outgoing calls via `definition` and emits a nested markdown or JSON tree. Replaces the agent-driven per-call `lsp_query.py` loop for Go and Ruby targets: one invocation pays the language-server cold-start once instead of once per call site.
  - **Go call-sites** extracted via `go/parser` AST (`scripts/callsites.go`, built once into `.bin/callsites` on first use). Symbol grammar: `(*Type).Method`, `(Type).Method`, `Name`.
  - **Ruby call-sites** extracted via Prism AST (`scripts/callsites.rb`, shells out to brewed Ruby). Solargraph symbol grammar: `A::B::Foo#bar`, `A::B::Foo.bar`, `A::B::Foo`. Ruby helper has both extract mode and an `@LINE` resolve mode so downstream targets can be named from their declaration line without a second AST walk.
  - **`--scope local`** drops calls whose definitions resolve outside `--project` (stdlib, gems). LSP queries still run, so the Step 3 LSP-utilization GATE artifact count is unaffected — only the rendered tree is trimmed.
  - **`--run-dir DIR`** persists every LSP response under `DIR/lsp/<op>__<slug>__L<line>C<col>.json` (same naming as `lsp_query.py`) and writes the final tree to `DIR/tree__<file-slug>__<symbol-slug>.<md|json>`. Printed as `WROTE: <path>` on stdout instead of the tree body.
- **`benchmark/sample-app-go/`** — new Go fixture (wallets / transactions endpoints, mirroring the Ruby sample-app) for exercising the Go path of `lsp_tree.py` end-to-end.
- **`benchmark/notes/lsp-taxonomy.md`** — reference note on when to use LSP vs. Read vs. Grep for call-tree construction, derived from the dogfooding session that produced `lsp_tree.py`.

#### Changed
- **`benchmark/sample-app` `WalletsController#create` and `#update` now delegate to `WalletCreateService` / `WalletUpdateService`.** Mirrors the existing `TransactionService` pattern. External HTTP behavior is preserved — including the intentional data-leak bug in the update error path that the benchmark expects to find — but internal structure now has an explicit service layer. `lsp_tree.py --lang ruby` walks across the controller → service boundary instead of bottoming out at ActiveRecord magic.

## [0.40.2] - 2026-04-22

### tdd-contract-review

#### Fixed
- **`lsp_query.py` now opens the target file via `lsp.open_file()` before issuing requests.** Some language servers require the file to be in the LSP session's open-buffer set before `definition` / `document_symbols` / `references` can resolve positions; without this, queries against untouched files silently returned empty.
- **Server-shutdown cleanup exceptions are caught and logged to stderr.** gopls can exit before `multilspy` signals its psutil-tracked children, producing a benign `psutil.NoSuchProcess` on context exit *after* the query has already completed. Previously this propagated and failed the invocation. The `with lsp.start_server()` block was unrolled into manual `__enter__`/`__exit__` so the cleanup path can catch its own exception without discarding the already-computed result.

## [0.40.1] - 2026-04-22

### tdd-contract-review

#### Changed
- **`contract-extraction.md` LSP algorithm section tidied.** No behavior change; clarity and doc-accuracy pass:
  - Step 1 (Seed) now scopes own-nodes to **only the symbol(s) the unit owns** (e.g., `create` on a controller, not `index`/`show`/etc.) — fixes prior "every method/class in that file" over-scoping.
  - **Coordinate convention** (LSP 0-indexed → own-node 1-indexed `+1`) moved into Step 1 where the agent first reads line ranges, instead of being buried after the CLI examples.
  - Step 4 (`references` closure) downgraded from mandatory to **optional** with a concrete use case — the gate doesn't enforce it, and "blast radius" was an imprecise frame for a single-unit review.
  - Gate description rewritten to match actual behavior: the gate counts JSON files in `$RUN_DIR/lsp/` directly (it does not parse the Summary line), requires `lsp_artifacts >= root_set_files` AND `>= 1 definition`. The Summary line is informational, not a gate input.
  - Duplicate "When LSP is NOT the right tool" block at the end **deleted** — its content was a near-subset of the earlier permitted-uses list (Solargraph-weak note folded into the runtime-dispatch bullet).

## [0.40.0] - 2026-04-22

### tdd-contract-review

#### Changed
- **LSP-first call-tree construction is now enforced, not just recommended.** A verification run found a sub-agent ran `document_symbols` once on the entry file and built the rest of the 9-file, 12-symbol tree via Grep — `$RUN_DIR/lsp/` had a single JSON artifact. The markdown-shape gate passed; the call tree was incomplete. Three changes harden the path:
  - `contract-extraction.md`: the "LSP-assisted call-tree construction" section is rewritten as a step-by-step algorithm (seed → walk every call site → recurse → closure). It states explicitly that **Read+Grep is NOT an acceptable substitute for `definition`** when `definition` returns a result; permitted Read+Grep uses are restricted to (a) contract field semantics, (b) marked `[unresolved]` nodes after `definition` returned empty, (c) runtime dispatch.
  - `SKILL.md` Step 3: a new **GATE (LSP utilization)** runs after the existing shape gate. It requires `lsp_artifacts >= root_set_files` AND at least one `definition__*.json`. On fail it auto-Revises with the deepen block — does not pass the checkpoint silently. Step 3 agent prompt and Checkpoint 1 DEEPEN REQUEST both gain explicit "LSP re-walk mandatory; Grep is not a substitute" language.
  - `## Summary` template now requires an `LSP calls: <D> document_symbols, <F> definitions, <R> references` line that must reconcile with file counts in `$RUN_DIR/lsp/`.

## [0.39.0] - 2026-04-22

### tdd-contract-review

#### Added
- **LSP query results persisted to `$RUN_DIR/lsp/`.** `lsp_query.py` now accepts `--run-dir DIR`. With the flag set, each query writes its JSON body to `DIR/lsp/<op>__<file-slug>__L<line>C<col>.json` and prints `WROTE: <path>` on stdout instead of dumping the response. Filenames are derived deterministically from the operation + target, so a repeat query overwrites the same file — giving an effective per-run cache, an inspectable audit trail of every LSP call the run made, and a way to diff runs over the same unit. The Step 3 agent prompt and `contract-extraction.md` now both instruct the agent to pass `--run-dir $RUN_DIR` on every invocation.

## [0.38.0] - 2026-04-22

### tdd-contract-review

#### Added
- **LSP-assisted call-tree construction via `multilspy`.** Step 3 (Contract Extraction) now treats LSP queries as the first-priority tool for building the `### Call trees` block. New helper at `tdd-contract-review/scripts/lsp_query.py` wraps `multilspy` and exposes `definition`, `document_symbols`, and `references` for 12 languages (ruby, typescript, javascript, go, python, java, rust, csharp, dart, kotlin, php, cpp). The script self-bootstraps a venv next to itself on first run — no separate setup step. On macOS it also auto-PATHs the brewed Ruby and its gem bin so `solargraph` installs into a writable location instead of failing on the system Ruby. The Step 3 agent prompt and `contract-extraction.md` both flag the workflow: `document_symbols` for own-node line ranges, `definition` to walk call sites outward, `references` for Checkpoint 2 file-closure verification. Read + Grep remain primary for contract field semantics (validations, enum values, response shapes) and for tagging `[unresolved]` runtime dispatch (`rescue_from`, `before_action`, `send`, DI lookup) that no LSP can resolve statically.

## [0.37.2] - 2026-04-21

### tdd-contract-review

#### Changed
- **Every actionable item in `report.md` is now a `- [ ]` checkbox in exactly one place.** Anti-Patterns Detected was a 4-column Markdown table; Top 5 Priority Actions was a numbered list. Neither was checkable, so a developer working through a review had to stitch together the checkboxes in Gap Analysis, the untickable table, and the untickable top-5. Both sections now render as flat checkbox lists (anti-pattern rows become `- [ ] **AP# — name** (Severity) — Location: … Fix: …`; the top-5 stays `1.`–`5.`-labelled but each item is a checkbox). No consolidated end-of-report checklist was added — Gap Analysis was already a checklist, and duplicating items into a second list was the original failure mode we were trying to fix. `report-template.md` requirements now explicitly state this rule so future template edits don't regress it.

## [0.37.1] - 2026-04-20

### tdd-contract-review

#### Changed
- **Benchmark graders renamed for clarity.** `eval.sh` → `grade-content.sh` (Category A: per-unit content grader against `expected_gaps.yaml`). `structural_check.sh` → `grade-shape.sh` (Category B: per-unit shape invariants). `run-eval.sh` → `run-matrix.sh` (wraps both across every declared unit, writes `last-eval.json`). The old names obscured that `run-eval` was a wrapper and that `eval` / `structural_check` were peers. Banners also renamed (`━━━ grade-content: …`, `━━━ shape: …`, `━━━ run-matrix: …`).
- **Shared YAML parser extracted to `parse_expected.py`** with `units` / `gaps` subcommands. Removes two drift-prone inline Python parsers that were duplicated between the per-unit grader and the matrix runner.
- **`results.md` trimmed 385 → 74 lines.** Kept the three historical matrices (Version Comparison, Gap Detection, Fintech Gap Detection); dropped v0.9–v0.18 per-version analysis prose that duplicated `CHANGELOG.md` and had stopped being updated at v0.18 while the plugin was on v0.37. Added a header pointing current eval state at `last-eval.json` + `CHANGELOG.md`.

#### Removed
- **Pre-v0.8 report snapshots** at `benchmark/sample-app-report-v0.3.0.md`, `-v0.5.0.md`, `-v0.6.0-test-file.md`, `-v0.7.0.md` (~2,800 lines). Preserved in git history; `results.md:5` already claimed they had been removed.

#### Fixed
- **`grade-shape.sh` B11 audit-template coupling documented.** B11 (grep-count vs. Test Inventory reconciliation) is grep-pinned to specific wording in `SKILL.md` + `test-patterns.md`. Added an inline comment flagging the coupling so future template edits don't silently break the gate.
- **`run-matrix.sh` intentional `set -e` omission documented.** Added a NOTE comment explaining that the matrix must not abort on per-unit failures (per-command exit codes are checked explicitly), so the divergence from `grade-content.sh` / `grade-shape.sh` isn't "fixed" by accident.

## [0.37.0] - 2026-04-20

### tdd-contract-review

#### Changed
- **`01-extraction.md` now uses a parseable call-tree shape (`schema_version: 2`).** The retired v1 shape (`## Files Examined` with flat `**Source:** / **DB schema:** / **Outbound clients:** / **Other:**` category headings) under-represented how the unit actually reaches its dependencies: a controller that dispatches to three services looked the same as one that called a single model, and downstream reviewers could not tell whether the extraction had missed a branch. The new shape replaces the flat list with an ordered file: YAML front-matter (`schema_version: 2`, `unit:`), `## Summary` (count-reconciled bullets), `## Entry points` (declared ROOT#n bullets), `## Files Examined` with three subsections (`### Call trees` fenced `tree` block + `### Root set` tagged bullets + optional `### Not examined`), `## Checkpoint 1: Contract Type Coverage`, and `## Checkpoint 2: File closure` closure paragraph. The call-tree block uses five line forms (ROOT, own-node with `Symbol @ path:start-end`, `[dup -> Symbol]`, `[external -> slug]`, `[unresolved]` with a reason) so a reviewer can walk the unit's actual control flow instead of inferring it. The root set carries a 12-tag vocabulary (`migration-authoritative`, `migration-snapshot-fallback`, `route-definition`, `annotation-config`, `factory`, `seed`, `middleware`, `di-config`, `dispatched-at-runtime`, `implicitly-invoked`, `generated-from <source>`, `test-fixture-shared`) so framework-convention files (before_action chains, rescue_from handlers, DI wiring) are accounted for instead of silently dropped. Hard cutover with no back-compat.
- **Checkpoint 1 table reshaped from 4 columns to 3.** Old header `| Contract Type | Status | Fields | Notes |` became `| Type | Status | Evidence |`. The `Fields` count was a loose proxy for coverage that encouraged padding; `Evidence` asks for the concrete class/table/SDK name that justifies the `Extracted` claim. `structural_check.sh` B8 already greps each row by exact label so the column rename was gate-safe.
- **SKILL.md Step 3 agent prompt, Checkpoint 1 Review Hint, and DEEPEN REQUEST block rewritten for v2.** The Step 3 prompt now points at the new `## Output File Shape (01-extraction.md)` section in `contract-extraction.md` and at `benchmark/fixtures/v2-example/01-extraction.md` as the worked example (80-word inline spec duplication removed). The Review Hint tells reviewers to scan the `### Call trees` block for missing own-nodes instead of the v1 `Files Examined` flat list. The DEEPEN REQUEST block tells the re-dispatched agent to re-walk every own-node + every root-set entry and to resolve or acknowledge every `[unresolved]` dispatch.
- **`structural_check.sh` B9 rewritten to grep v2 subheadings.** Was `^\*\*Source:\*\*` / `^\*\*DB schema:\*\*` / `^\*\*Outbound clients:\*\*` / `^\*\*Other:\*\*`; now `^### Call trees[[:space:]]*$` and `^### Root set[[:space:]]*$`. B7 anchor tightened too (`^## Summary[[:space:]]*$`) to prevent `## Summary (draft)`-style false-positives.

#### Added
- **`benchmark/fixtures/v2-example/01-extraction.md` — canonical v2 extraction.** POST /api/v1/transactions (Rails), critical mode OFF, 13 own-nodes, 8 files in root set, 1 unresolved `rescue_from` dispatch, 1 external `payment-gateway` call. Dual role: the Step 3 agent reads it as the authoritative worked example, and the benchmark harness uses it as a sanity fixture to verify B7/B8/B9 still pass against a known-good v2 file.

### Deferred

- **Auto-detect `generated-from` via glob heuristic.** v0.37.0 ships `generated-from` as a voluntary tag; agents have to remember to apply it on Prisma/gRPC/OpenAPI-generated files. The eng review flagged this as a quiet gameability surface (any agent that just never tags silently over-trusts line ranges on regenerated code). Implementation waits until at least one benchmark unit actually exercises codegen. See `TODOS.md` "Deferred from plan-eng-review (2026-04-20)".

## [0.36.1] - 2026-04-20

### tdd-contract-review

#### Fixed
- **Checkpoint file paths are now clickable markdown links, not plain text.** The v0.36.0 "Open to review:" line relied on the terminal auto-linking a raw absolute path — in practice Claude Code rendered it as unclickable text, and `AskUserQuestion` (which never renders markdown) inlined the same path a second time, doubling the noise. The Checkpoint Interaction Pattern, Step 2.5 previous-extraction reuse prompt, and the Step 9 PASS message all now emit the resolved absolute path as a `[abs-path](abs-path)` markdown link on its own line BEFORE any `AskUserQuestion` call, and the question text references "see path above" instead of re-inlining `$RUN_DIR/<file>` / `$PREV_EXTRACTION`. One clickable path per prompt, zero duplicates.

## [0.36.0] - 2026-04-19

### tdd-contract-review

#### Fixed
- **DB contract extraction was reading migrations as a first-class source.** The staff-engineer agent and `contract-extraction.md` told extraction to read migrations alongside models, which can produce a false contract (a column added then later removed across migrations still appears). Flipped the priority: snapshot files (`db/schema.rb`, `db/structure.sql`, `schema.prisma`, Drizzle schema, Django `models.py`) are the authoritative current state; migrations are fallback only when no snapshot exists. Rewrote the DB Extraction Rules in `agents/staff-engineer.md`, the DB Data Contract section + Files Examined template + HIGH confidence example in `contract-extraction.md`, Step 2 discovery DB-file line + critical-mode example in `SKILL.md`. Added canonical `benchmark/sample-app/db/schema.rb` so the sample-app benchmark exercises the snapshot path (previously only migrations were committed).

#### Changed
- **Checkpoints now surface the full report path on its own 'Open to review:' line** after the Review Hint block and before the AskUserQuestion ask. Terminal-selectable text lets reviewers copy the path and open the file to review before picking Continue/Revise/Stop. The Summary echo and embedded question text still mention the path too — the dedicated line exists purely as a copy target.
- **Revise option copy points users at the CLI's free-text option by its actual label.** `Re-run this step with a deeper pass. For specific feedback, pick 'Type something else' and type it.` The Step C #4 branch header is renamed from `Other` to `Type something else` to match. The AskUserQuestion tool auto-adds this option; prior copy referenced it as `Other`, which does not match what users see in the Claude Code CLI.

## [0.35.0] - 2026-04-18

### tdd-contract-review

#### Changed
- **SKILL.md slimmed from 832 → 562 lines (~42% smaller, 6,585 → 4,927 words).** Every step-6 through step-8 agent-dispatch prompt used to inline its full output-file-shape spec (section order, row labels, table headers, schema) even though the prompt already told the agent to read the companion ref file. Those specs now live once in the ref files. Dispatch prompts now point to the ref section by name and carry a single-line reminder that the orchestrator grep-gates on literal row labels / column headers so the gate still passes. Affected: Step 3, Step 4-5, Step 6b (×3 per-type agents), Step 6c merge, Step 7-8 report.

#### Added
- **`gap-analysis.md` ref file (new).** Houses the full output-file-shape spec for Step 6: per-type sub-reports (`03a-gaps-api.md` / `03b-gaps-db.md` / `03c-gaps-outbound.md`), F1 money-correctness (`03d-gaps-money.md`), F2 API-security (`03e-gaps-security.md`), and the merged `03-gaps.md` (7 sections including the grep-gated Checkpoint 2 table). Also carries the Scenario Enumeration Rules (input field → own branch, assertion field → own branch, enum value → own scenario) that previously were split between SKILL.md and `scenario-checklist.md`.
- **`## Output File Shape (01-extraction.md)` in `contract-extraction.md`.** The three mandatory opening sections (Summary, Files Examined, Checkpoint 1 Contract Type Coverage table) with row labels and column headers the orchestrator grep-gates on.
- **`## Read Protocol (Test Audit)` and `## Output File Shape (02-audit.md)` in `test-patterns.md`.** The three-step read protocol (grep-count, chunked read-to-EOF, reconcile) and the five-section audit file spec (Test Inventory, Scenario Inventory, Per-Field Coverage Matrix, Assertion Depth, Anti-Patterns).
- **`## Output Instructions` in `report-template.md`.** What goes into `report.md` (full-or-quick rendering + Hygiene section) vs. `findings.json` (all four priorities, hygiene excluded, still written in quick mode).
- **Checkpoint Review Hint blocks (×3).** Each checkpoint now prints a `--- What to look for at Checkpoint <N> ---` block after the Summary echo and before the AskUserQuestion Continue/Revise/Stop ask. Each block teaches the principle behind the checkpoint and names the concrete thing to verify before accepting. Aimed at junior engineers who would otherwise rubber-stamp the three stop points. Example (CP1): "Files Examined drives everything. If the handler delegates to a service class that isn't listed, the extraction missed a branch. CP2 and CP3 will inherit that gap. Fixing it here is cheaper than three Revises later."

#### Fixed
- **`report-template.md` priority schema drift.** The ref file still encoded the old three-priority model (`HIGH|MEDIUM|LOW`) and said stubs were REQUIRED for HIGH only. The orchestrator, Step 9 gate, and v0.34.1 findings.json rule had already moved to four priorities (`CRITICAL|HIGH|MEDIUM|LOW`) with stubs REQUIRED for CRITICAL and HIGH. The schema example, field-rules prose, and the `## Gap Analysis by Priority` block in the `report.md` template are now aligned with the four-priority authoritative model.

## [0.34.1] - 2026-04-18

### tdd-contract-review

#### Fixed
- **Step 7-8 report agent was silently dropping MEDIUM and LOW gaps from `findings.json`.** The schema example showed only `"HIGH|MEDIUM|LOW"` and the instruction text said "include ONLY contract gaps and critical-mode gaps" — the agent reasonably read this as "HIGH is the floor" and emitted 0 MEDIUM, 0 LOW. Schema now lists all four priorities (`CRITICAL|HIGH|MEDIUM|LOW`) and the instruction explicitly says "include EVERY gap ... all four priorities. Do NOT drop MEDIUM or LOW." Benchmark score on `post-api-v1-transactions` rose from 16/24 → 19/24 with no other changes.
- **Step 9 check 2 only validated HIGH gaps had stubs, missing CRITICAL.** The SKILL spec has always said "stub: REQUIRED for CRITICAL and HIGH" but the jq filter was `priority == "HIGH"`. Now `(.priority == "CRITICAL" or .priority == "HIGH")`. Label renamed to `CRITICAL+HIGH gaps have stubs`.

## [0.34.0] - 2026-04-17

### tdd-contract-review

#### Added
- **Step 2.5 Previous Extraction Check** — if a previous run's `01-extraction.md` exists for the same unit-slug, the orchestrator offers a two-option AskUserQuestion (`Reuse` / `Extract fresh`) before dispatching the Step 3 extraction agent. Reuse copies the prior file into the current `$RUN_DIR`, runs the Checkpoint 1 shape GATE against the copy, and jumps straight to the Checkpoint 1 PAUSE. Extract fresh runs Step 3 normally. Saves the full extraction-agent cost when iterating on the same unit with unchanged source.
- **Previous-extraction lookup in Step 2 discovery** — glob `tdd-contract-review/*-{unit-slug}/01-extraction.md`, exclude the current `$RUN_DIR`, pick the most recent by `YYYYMMDD-HHMM` directory prefix. Result stored as `$PREV_EXTRACTION` (empty if none).
- **`Previous extraction:` line in the Run Preview** — shows `<path> (<timestamp>)` if one was found, or `none found (skip reuse ask)` otherwise. User sees the reuse opportunity before the first agent dispatches.
- **Critical-mode mismatch warning** — if the prior extraction's `Critical mode:` value differs from the current run's, Step 2.5 prepends a one-line warning above the two options recommending Extract fresh.
- **GATE-fail fallback** — if the reused file fails the Checkpoint 1 shape GATE (malformed or from an older skill version), the orchestrator prints the failure and falls through to a fresh Step 3 dispatch. No hard stop.

#### Notes
- Revise at Checkpoint 1 works identically on a reused file — the Step 3 DEEPEN REQUEST block overwrites `$RUN_DIR/01-extraction.md` regardless of how it arrived.
- Out of scope for v0.34.0: audit (`02-audit.md`) reuse, gaps (`03-gaps.md`) reuse, a CLI `no-reuse` skip flag, and mtime-based staleness detection. Revisit audit reuse if real usage shows audit cost dominating after this lands.

## [0.33.0] - 2026-04-17

### tdd-contract-review

#### Added
- **READ PROTOCOL in the audit agent prompt.** Three non-negotiable steps before writing `02-audit.md`: (1) grep each test file with the framework's test-function pattern to get a ground-truth count and line numbers, (2) read every test file to EOF with chunked `Read(offset=0/500/1000/...)` calls until returned lines < 500, (3) pre-write verification that Test Inventory count equals grep count per file. Closes the silent-under-reading failure mode that burned ~353K tokens across 3 revision runs pre-v0.33.0.
- **Per-framework grep pattern table** inlined in the audit prompt: Go testing, RSpec, Jest/Vitest, pytest, Minitest.
- **5-section audit output spec** (explicit and ordered): `## Test Inventory`, `## Scenario Inventory`, `## Per-Field Coverage Matrix`, `## Assertion Depth`, `## Anti-Patterns`. Replaces the previous vague "produce test structure findings, quality issues, anti-patterns (with file:line), per-field coverage notes" one-liner.
- **Grep-reconciliation bullets in `## Summary`**: `Test files (grep count): <N> files, <M> functions` + `Test Inventory (agent count): <M> functions ← MUST match`. The Checkpoint 2 Summary echo now surfaces any count mismatch directly in the terminal — user can spot incompleteness without opening the file.

#### Changed
- **Checkpoint 2 DEEPEN REQUEST block** now leads with reconciliation: verify grep-count vs agent-count first, re-run chunked reads on any short file, then proceed to the exhaustive-examination steps. Misreads get caught first, not after another full pass.
- **Audit output explicitly excludes `## Gaps` and `## Scorecard`.** Gaps are Step 6's job; scoring is Step 7-8's job. The audit is an input to both, not a partial duplicate.

#### Notes
- Audit agent stays on `Model: sonnet`. The forcing functions (read protocol + 5-section spec + reconciliation) should land the audit on first run without a model upgrade. If sonnet with the hardened prompt still burns revision cycles, revisit upgrading to opus in a future version.

## [0.32.0] - 2026-04-17

### tdd-contract-review

#### Added
- **`## Summary` sections** in three agent outputs — extraction (`01-extraction.md`), audit (`02-audit.md`), merge (`03-gaps.md`). Each is a scannable 4-8 bullet one-screen overview placed as the first section of the file. Extraction summary: total fields, Checkpoint 1 matrix one-liner, critical-mode status + triggering signal, files-examined counts. Audit summary: test framework, file + case counts, anti-pattern count, per-contract-type coverage. Merge summary: gaps by priority, gaps per contract type, stubs generated, hygiene count.
- **Summary echo before each checkpoint** — the orchestrator prints the written file's Summary section to the terminal before asking Continue/Revise/Stop, so the user has something to review without opening the file.
- **Per-type DEEPEN REQUEST + Merge DEEPEN REQUEST blocks** at Checkpoint 3 — Revise re-dispatches all Extracted per-type agents (plus critical-mode agents if applicable) in parallel before re-running the merge agent. Matches the intent of "make the report more complete" instead of just re-merging existing sub-files.

#### Changed
- **Per-type gap agents (API / DB / Outbound) downgraded from opus → sonnet.** The F1 money-correctness, F2 API-security, and Step 6c merge agents stay on opus. Per-type analysis is narrow-context scenario enumeration against a matrix — sonnet handles this well and cuts ~60% of gap-analysis cost per run.
- **Revise is now an auto-iterate deepen pass** — no follow-up "what should be revised?" prompt. Selecting Revise re-dispatches the same agent with a step-specific DEEPEN REQUEST block appended (re-examine source exhaustively, re-verify cited tests, re-calibrate priorities). The description in the Checkpoint option list changed from `Re-run this step with your feedback.` to `Re-run this step with a deepen pass (no input needed).`
- **Specific-feedback path preserved** via the existing free-text fallback. Typing free text at the checkpoint (instead of picking Continue/Revise/Stop) still routes through the REVISION REQUEST block with the user's verbatim text — unchanged from v0.31.0.
- **Revision cap (3 per checkpoint)** now counts any mix of deepen Revise and specific-feedback free-text paths.
- **Checkpoint Interaction Pattern section rewritten** as a three-step shape (Step A — Echo Summary, Step B — Ask, Step C — Branch) so all three checkpoints share one spec.

## [0.31.0] - 2026-04-17

### tdd-contract-review

#### Added
- `scenario-checklist.md` reference file — the per-field input/assertion scenario matrix previously inlined into every per-type gap prompt is now a single reference loaded by the per-type agents. One place to edit; smaller prompts.
- **Run preview** printed at end of Step 2 (before Step 3 dispatches): unit, resolved source, schema/outbound counts, critical-mode status with the signal that triggered it, pipeline shape, and run dir. Makes auto-detected critical mode visible and gives users a cancellation window before any agent spends tokens.
- **Progress breadcrumbs** in Step 6b: print the list of parallel gap agents before dispatch and one `✓ <sub-file> (<N> gaps)` line per agent after all return. No more silent multi-minute gaps.
- Not-found error (Step 2 GATE) now shows the globs actually searched and up to 3 fuzzy candidate matches, symmetrical with the ambiguous-match path.
- Missing-unit error (Step 1) now prints the full argument hint with unit-form examples and flag descriptions.

#### Changed
- Renumbered cross-cutting gap sub-files: `03f-gaps-money.md` → `03d-gaps-money.md`, `03g-gaps-security.md` → `03e-gaps-security.md`. Output layout is now sequential `03a/03b/03c/03d/03e`.

## [0.30.0] - 2026-04-17

### tdd-contract-review

#### Changed
- Review checkpoints now use the `AskUserQuestion` harness instead of "Reply continue" text prompts. Each of the 3 checkpoints (after extraction, audit, and gap analysis) renders three explicit options: **Continue**, **Revise**, **Stop**.
- Added a shared **Checkpoint Interaction Pattern** section in SKILL.md so all three checkpoints share one spec.

#### Added
- **Revise** option: re-dispatches the same step's agent with user feedback appended as a REVISION REQUEST block, overwrites the intermediate file, re-runs the step's GATE check, and returns to the same checkpoint.
- Revision cap: 3 revisions per checkpoint before the option is dropped, to prevent unbounded loops.
- Natural-language fallback: if the user types free text instead of selecting (via the auto-added "Other" input), affirmative words proceed, stop-intent words exit, and any other text is treated as revise feedback directly.

## [0.14.0] - 2026-04-12

### tdd-contract-review

#### Added
- Balance and position validation scenarios for amount fields in gap analysis
- Position & Inventory extraction guidance and gap checklist in fintech-checklists.md
- Common Field Type Scenarios section (pagination, date/time, array, formatted string, file upload)
- Cross-dimension rule: amount fields show balance/position constraints in test tree
- Stronger error response data leak check in security gap analysis

#### Changed
- Cross-reference notes between amount-level and balance/ledger-level checks to avoid double-flagging
- Updated test structure tree example to include balance/position scenarios

## [0.13.0] - 2026-04-12

### tdd-contract-review

#### Added
- Full fintech dimension coverage across all 8 categories
- Benchmark reports for v0.13.0 validating complete gap detection

#### Changed
- Expanded SKILL.md fintech analysis instructions for broader scenario coverage

## [0.12.0] - 2026-04-12

### tdd-contract-review

#### Added
- Contract Map now requires every extracted field to have a row (DB fields, outbound API params, not just API request/response)
- Contract Extraction Summary in reports must include all contract types found

#### Changed
- Stub headings use full gap descriptions instead of shorthand labels like "Stub H4"
- Summary enforced as strict rollup — every finding must appear in a per-file report first
- Removed agent definition; skill is the sole entry point (fixes "Agent type not found" on fresh installs)

#### Fixed
- DB table fields and outbound API contracts now consistently appear in Contract Map
- Summary no longer contains findings absent from per-file reports

## [0.11.0] - 2026-04-12

### tdd-contract-review

#### Added
- Absence flagging: explicitly flags missing rate limiting, audit trail, and idempotency as infrastructure gaps
- Inline top 2-3 scenarios per fintech category (concurrency, security) to ensure gap generation
- Missing Infrastructure section in reports for absence-based findings

#### Changed
- Replaced `[FINTECH]` tags with natural prefixes (`security:`, `concurrency:`, `business:`)

#### Fixed
- Fintech gap detection now 18/18 (up from 14/18) — closed concurrency and infrastructure gaps

## [0.10.0] - 2026-04-12

### tdd-contract-review

#### Added
- Contract extraction completeness gate (minimum 10 fields before proceeding)
- Report file write gate (must write files before printing summary)
- Mass assignment risk detection (bonus finding: `wallet_params` permits `:status`)

#### Changed
- Extracted detailed fintech checklists to `fintech-checklists.md` reference file (SKILL.md: 933 -> 768 lines)

#### Fixed
- Recovered all 13/13 known gap detection (regressed to 7/13 in v0.9.0)
- Restored money/precision and state machine fintech findings
- Report file writing restored (regressed in v0.9.0)

## [0.9.0] - 2026-04-12

### tdd-contract-review

#### Added
- Fintech domain auto-detection (money/balance fields, payment gateways, state machines)
- 8-dimension fintech contract extraction: Money/Precision, Idempotency, State Machine, Balance/Ledger, External Integrations, Regulatory, Concurrency, Security
- Concurrency gap analysis (TOCTOU, locking, deadlock, double-submit)
- Security gap analysis (auth, IDOR, amount tampering, rate limiting, data exposure)
- Idempotency design gap detection

## [0.6.0] - 2026-04-11

### tdd-contract-review

#### Added
- Benchmark suite with sample Rails 7.1 API app (transactions, wallets, users)
- `$ARGUMENTS` parsing with quick mode (`/tdd-contract-review quick`)
- Test structure tree output (visual coverage map with checkmarks)
- Scoring calibration anchors (what a 2, 5, 7, 9 look like)
- Enum exhaustion checking in contract extraction
- Auto-generated test stubs for HIGH priority gaps
