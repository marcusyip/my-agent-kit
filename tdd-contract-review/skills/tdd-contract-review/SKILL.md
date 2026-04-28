---
name: tdd-contract-review
description: Contract-based test quality review. Reviews ONE unit per run (one HTTP endpoint, one background job, or one queue consumer). Extracts contracts, audits tests, identifies gaps, produces a scored report with CRITICAL-only test stubs, and emits machine-readable findings.json for CI grading.
argument-hint: "<unit: 'POST /path' | 'JobClass' | file.rb> [quick] [critical|no-critical]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.52.0
---

# TDD Contract Review

Contract-based test quality review. **Reviews ONE unit per run.** A unit is one HTTP endpoint, one background job, or one queue consumer. The orchestrator dispatches a Staff Engineer agent at each step with focused context and writes intermediate reports to disk. The user reviews each intermediate and confirms before the next step runs.

## Output Layout

Every run writes to TWO unit-scoped directories sharing the same `RUN_ID = {YYYYMMDD-HHMM}-{unit-slug}`. Intermediates live outside the project (so they don't pollute PRs); only the two committable deliverables land in the working tree.

```
$OUT_DIR  = tdd-contract-review/{RUN_ID}/                       ← in-repo, committed
├── report.md                ← rendered MD view of report.json (the deliverable)
└── findings.json            ← merged + deduped gap list (machine-readable; CI/grader read this)

$WORK_DIR = ~/.claude/tdd-contract-review/runs/{RUN_ID}/        ← user home, ephemeral
├── 01-extraction.json    ← contract extracted from source (source of truth)
├── 01-extraction.md      ← rendered MD view of 01-extraction.json
├── 02-audit.json         ← test structure + quality findings (source of truth)
├── 02-audit.md           ← rendered MD view of 02-audit.json
├── 03a-gaps-api.json     ← per-type gap JSON (API inbound, source of truth)
├── 03a-gaps-api.md       ← rendered MD view
├── 03b-gaps-db.json      ← per-type gap JSON (DB)
├── 03b-gaps-db.md        ← rendered MD view
├── 03c-gaps-outbound.json ← per-type gap JSON (Outbound API)
├── 03c-gaps-outbound.md  ← rendered MD view
├── 03d-gaps-money.json   ← cross-cutting money-correctness JSON (critical mode only)
├── 03d-gaps-money.md     ← rendered MD view
├── 03e-gaps-security.json ← cross-cutting API-security JSON (critical mode only)
├── 03e-gaps-security.md  ← rendered MD view
├── 03-index.md           ← CP3 index (shell-generated, clickable links + gap counts)
├── report.draft.json     ← LLM-authored draft (pre-scoring; ephemeral)
├── report.json           ← scorecard + narrative after deterministic scoring
├── lsp/                  ← persisted LSP query JSON for auditability
└── tree__*.json          ← lsp_tree.py call-tree dumps
```

**JSON is the source of truth; MD is a rendered view.** Every numbered artifact is emitted as JSON by the agent (schema-validated against `[plugin root]/tdd-contract-review/schemas/<kind>.schema.json`), then re-rendered to Markdown by `[plugin root]/tdd-contract-review/scripts/render.py`. Humans read the MD; tooling reads the JSON. Hand-editing a generated `.md` is a correctness bug — edit the JSON and re-render.

Per-type sub-files are the source of truth for gaps — Step 7-8 reads the `.json` variants directly. `03-index.md` is a tiny shell-generated file that gives Checkpoint 3 a single reviewable artifact with clickable paths into each sub-file; it carries no content the sub-files don't already hold. Sub-reports for contract types marked `Not applicable` or `Not detected` are skipped entirely.

The `unit-slug` is lowercase kebab-case of the unit identifier:
- `POST /api/v1/transactions` → `post-api-v1-transactions`
- `ProcessPaymentJob` → `process-payment-job`
- `WithdrawalConsumer` → `withdrawal-consumer`

## Checkpoint Interaction Pattern

The 3-step Echo Summary → Ask → Branch interaction (used at all 3 review checkpoints) lives in `[skill dir]/checkpoint-pattern.md`. Each PAUSE block below substitutes `<N>`, `<file>`, `<next step>`, and the specific-feedback revision target into that pattern. Read the sibling file once before the first checkpoint fires.

## Review Workflow

### Step 1: Parse Arguments

Split `$ARGUMENTS` on whitespace. The **first token is the unit identifier** and is REQUIRED. Remaining tokens are flags in any order.

- **Unit identifier** (required): one of
  - HTTP verb + path: `POST /api/v1/transactions`
  - Class name: `ProcessPaymentJob`, `WithdrawalConsumer`
  - File path: `app/controllers/api/v1/transactions_controller.rb`
- **`quick`** (optional): abbreviated report output
- **`critical`** (optional): force critical mode ON — enables BOTH money-correctness and API-security checklists
- **`no-critical`** (optional): force critical mode OFF (skip both checklists)

If no unit identifier is provided, print the following and stop:

```
ERROR: unit identifier required.

Usage: /tdd-contract-review <unit> [quick] [critical|no-critical]

Unit examples:
  "POST /api/v1/transactions"     HTTP verb + path
  ProcessPaymentJob               class name
  app/controllers/foo.rb          file path

Flags:
  quick          abbreviated final report
  critical       force critical mode (money + API-security checklists)
  no-critical    disable critical mode even if auto-detected
```

### Step 2: Preliminary Survey + Unit Guard

This step is a fast preliminary survey from test files and known-location files. It is **NOT authoritative** — Step 3's LSP call-tree walk is the ground truth for DB model tracing, outbound API discovery, and everything downstream. Step 2's job is to (a) resolve the unit so the GATE can fire before any agent dispatches and (b) seed the extraction agent with the cheapest useful signals. Do not walk the source tree here.

1. **Find test files.** Glob for `**/*.test.{ts,tsx,js,jsx}`, `**/*.spec.{ts,tsx,js,jsx}`, `**/*_test.go`, `**/*_spec.rb`, `**/*.test.py`, `**/test_*.py`
2. **Detect test framework** from the test files.
3. **Resolve the unit to a single source file** (required for the GATE below).
   - If unit is `VERB /path`: grep for route definitions, find the handler.
   - If unit is a class name: glob + grep for `class ClassName`.
   - If unit is a file path: use it directly.
4. **DB schema snapshot** — glob known locations only: `db/schema.rb`, `structure.sql`, `db/structure.sql`, `prisma/schema.prisma`, `schema.sql`. Pick the first hit, or report `not found`. Do NOT walk model/entity files — Step 3's LSP walk traces those authoritatively.
5. **Check project conventions.** Read CLAUDE.md, config files.
6. **Detect critical mode** unless overridden by `critical`/`no-critical` arg. Narrow-scope detection:
   - Scan test files (already globbed in step 1) for money vocabulary: `amount`, `balance`, `currency`, `decimal`, `cents`, `price`, `fee`.
   - Scan the schema snapshot (if found) for `decimal` / `numeric` columns on money-like names.
   - Any hit → critical mode ON.
   - This is intentionally narrower than a full-repo sweep. If it misses, the user can force with the `critical` flag.

**GATE (one-unit):** Exactly one source file must resolve from the unit identifier.
- **0 matches**: print the following and stop:
  ```
  ERROR: unit '<arg>' not found.

  Searched:
    <one line per glob / grep pattern actually tried>

  Closest matches:
    <top 3 fuzzy candidates — route definitions, class names, or file paths
     whose name shares a substring with <arg>, ranked by overlap length>
  ```
  If no fuzzy candidates exist, omit the "Closest matches" block entirely rather than printing an empty list.
- **>1 matches**: print `ERROR: unit '<arg>' ambiguous. Candidates:` followed by a numbered list, then stop.
- **1 match**: proceed.

**Compute unit-slug** from the identifier. Compute the shared run id and both directories:

```bash
RUN_ID="$(date +%Y%m%d-%H%M)-{unit-slug}"
WORK_DIR="$HOME/.claude/tdd-contract-review/runs/$RUN_ID"
OUT_DIR="tdd-contract-review/$RUN_ID"
mkdir -p "$WORK_DIR"
# OUT_DIR is created lazily in Step 7-8, just before the first deliverable
# writes — this avoids leaving an empty in-repo folder behind when the user
# Stops at Checkpoint 1, 2, or 3.
```

`$WORK_DIR` holds every intermediate (01-extraction.*, 02-audit.*, 03*-gaps-*, 03-index.md, lsp/, tree__*.json, report.draft.json, report.json). `$OUT_DIR` holds only the two committable deliverables (`report.md`, `findings.json`) and is what lands in the PR.

**Look for a previous extraction for this unit.** Glob `$HOME/.claude/tdd-contract-review/runs/*-{unit-slug}/01-extraction.json` (the JSON is the source of truth — older `.md`-only runs without a sibling `.json` are not auto-discovered, one fresh extraction migrates the unit forward), exclude `$WORK_DIR` itself, sort results by the `YYYYMMDD-HHMM` timestamp prefix in the directory name (lexicographic order works), pick the most recent. Store its path as `$PREV_EXTRACTION_JSON` (empty string if no match); the sibling `$PREV_EXTRACTION_MD` is `${PREV_EXTRACTION_JSON%.json}.md` and is shown to the user in the path preview at Step 2.6.

**Run preview.** Before proceeding to Step 3, print this 1-screen summary so the user can interrupt before the first agent dispatch:

```
=== TDD Contract Review — Run Preview ===
Unit:                <unit identifier>
Source:              <resolved source file:line of handler or class def>
DB schema snapshot:  <path, or "not found">
Critical mode:       ON (reason: <one-line signal that triggered it, e.g., "test file mentions 'amount'" or "decimal column 'balance' in db/schema.rb">)
                     OR OFF
Previous extraction: found at <$PREV_EXTRACTION_JSON> (<YYYY-MM-DD HH:MM from dir prefix>)
                     OR "none found (skip reuse ask)"
Pipeline:            <N> agent dispatches, 3 checkpoints
Work dir:            $WORK_DIR        (intermediates — ~/.claude, not committed)
Out dir:             $OUT_DIR         (deliverables — in repo, committed)
Note: DB model files and outbound API clients are discovered by Step 3's LSP walk, not here.
```

The first checkpoint fires within ~30s of this preview (after extraction, or sooner if the user picks Reuse at Step 2.6). This preview is informational — it makes auto-detected critical mode visible and flags when a prior extraction is available for reuse. It is NOT a hard gate; do not wait for input here.

### Step 2.5: LSP Plugin Check

Step 3 uses `lsp_tree.py` / `lsp_query.py` as its scripted LSP path — always available regardless of this check. Claude Code ALSO ships a native `LSP` tool via the [code-intelligence plugin](https://code.claude.com/docs/en/discover-plugins#code-intelligence), which adds interface→impl hops, call hierarchies, and type information when installed. The scripted path is the correctness floor; the native tool is an accuracy upgrade for languages `lsp_tree.py` does not natively cover.

This step auto-detects installation and language, then prompts only when the prompt is actionable. Users with the plugin already installed, and users on Go/Ruby/TypeScript, see no prompt at all.

**Detect plugin installation.** Inspect `~/.claude/plugins/installed_plugins.json` — it lists every installed plugin as `<name>@<marketplace>` keys. Match the plugin name (case-insensitive) against `code-intelligence`:

```bash
PLUGIN_INSTALLED=0
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$INSTALLED_FILE" ]]; then
  if jq -r '.plugins | keys[]' "$INSTALLED_FILE" 2>/dev/null \
     | awk -F@ '{print tolower($1)}' \
     | grep -qx 'code-intelligence'; then
    PLUGIN_INSTALLED=1
  fi
fi
```

Missing file, missing jq, or malformed JSON all mean "not detected" — the user still reaches the prompt below for non-native-covered languages, so a spurious prompt once is acceptable.

**Detect language** from the unit's source file extension: `.go` → `go`, `.rb` → `ruby`, `.ts`/`.tsx` → `typescript`, `.py` → `python`, `.rs` → `rust`, `.java` → `java`, `.cs` → `csharp`, `.kt` → `kotlin`, `.dart` → `dart`, anything else → `other`. Store as `$DETECTED_LANG`. Also compute `$NATIVE_LSP_AVAILABLE = yes` iff `PLUGIN_INSTALLED=1`, else `no` — this string is passed into the Step 3 agent prompt so the agent deterministically knows which LSP path to use.

**Decide whether to prompt (no question fires in cases 1 or 2):**

1. `PLUGIN_INSTALLED=1` → print `(code-intelligence plugin detected — native LSP tool available for <detected-lang>)` and go to Step 2.6.
2. `PLUGIN_INSTALLED=0` AND `$DETECTED_LANG` ∈ { `go`, `ruby`, `typescript` } → print `(scripted LSP covers <detected-lang> fully; native LSP tool not needed)` and go to Step 2.6.
3. `PLUGIN_INSTALLED=0` AND `$DETECTED_LANG` ∈ { `python`, `rust`, `java`, `csharp`, `kotlin`, `dart`, `other` } → run the **AskUserQuestion** below.

**AskUserQuestion** (only reached when the prompt is actionable):

- question: `The code-intelligence plugin (adds a native LSP tool for tracing function calls across files) is not installed. It would improve accuracy on <detected-lang>. The skill continues either way.`
- header: `Code-intelligence plugin`
- options (exactly these two, in this order):
  - label `Continue without it` — description: `Use scripted LSP only. Accuracy is slightly lower on <detected-lang>.`
  - label `Show install steps and continue` — description: `Print how to install, then proceed. Benefit applies on the next run.`

**Branch on selection:**

1. **Continue without it** → go to Step 2.6.
2. **Show install steps and continue** → print the block below, then go to Step 2.6 (does NOT stop the current run).

   ```
   Code-intelligence plugin — install for next run:
     1. In Claude Code, run `/plugins` and install the `code-intelligence` plugin
     2. Ensure the language server binary for <detected-lang> (pyright / rust-analyzer / jdtls / …) is on $PATH
   Docs: https://code.claude.com/docs/en/discover-plugins#code-intelligence
   ```

Free-text fallback: text matching "install" / "show" / "yes" / "steps" → treat as (2); anything else → treat as (1).

### Step 2.6: Previous Extraction Check (optional reuse)

If `$PREV_EXTRACTION_JSON` is empty, skip this step entirely — do not print anything, do not ask — and proceed to Step 3.

If `$PREV_EXTRACTION_JSON` is set, offer the user the choice to reuse it or run a fresh extraction. This saves the cost of re-extracting when iterating on the same unit with unchanged source.

**Critical-mode mismatch check (do this BEFORE the ask):** Infer the prior run's critical mode from `$PREV_EXTRACTION_JSON` — `jq -r 'if (.fintech_dimensions_md // "") == "" then "OFF" else "ON" end' "$PREV_EXTRACTION_JSON"` (the optional `fintech_dimensions_md` field is only emitted when critical mode is on). If it differs from the current run's critical mode, print a one-line warning above the path preview below: `Previous extraction was Critical mode: <X>, current run is Critical mode: <Y>. Fresh extraction recommended.`

**Path preview (print BEFORE calling AskUserQuestion):** Resolve `$PREV_EXTRACTION_MD` (the rendered MD view of `$PREV_EXTRACTION_JSON`) to an absolute filesystem path, then print the clickable markdown link on its own line so the user can open the prior file before choosing:

```
Previous extraction: [<ABS_PATH>](<ABS_PATH>) (<timestamp from dir prefix>)
```

Same rules as the Checkpoint Interaction Pattern: substitute the same absolute path into BOTH the link label and the target — `AskUserQuestion` does not render markdown, so the clickable link must live in the preview line, not in the question text.

**AskUserQuestion** with two options (no Revise/Stop — nothing has been written in this run yet to revise):

```
Question:
  "A previous extraction for this unit exists (see path above).
   Reuse it as this run's 01-extraction.md, or run a fresh extraction?
   <critical-mode mismatch warning line if applicable>"
Options:
  A) Reuse       — copy into $WORK_DIR and go straight to Checkpoint 1
  B) Extract fresh — run the Step 3 extraction agent as normal
Multi-select: false
```

Free-text fallback (user typed something instead of picking): treat affirmative-sounding text ("reuse", "yes", "copy", "skip") as Reuse; anything else as Extract fresh.

**Branch — Reuse:**

1. Copy the JSON (source of truth) and re-render the MD against the *currently installed* renderer (so a renderer upgrade between runs is picked up):
   ```bash
   cp "$PREV_EXTRACTION_JSON" "$WORK_DIR/01-extraction.json"
   [plugin root]/tdd-contract-review/scripts/render.py \
     --kind extraction \
     --input  "$WORK_DIR/01-extraction.json" \
     --output "$WORK_DIR/01-extraction.md"
   ```
   `render.py` schema-validates before rendering — a non-zero exit means the prior JSON does not match the current schema.
2. **GATE on reused extraction.** If `render.py` exited non-zero, treat as GATE failure (skip to step 4 below). Otherwise the schema check has already enforced the 5 coverage_table rows; the legacy grep gate (described under "GATE (Checkpoint 1 shape)" in Step 3) is a redundant backstop.
3. If GATE passes: jump directly to the **Checkpoint 1 PAUSE** in Step 3 — apply the Checkpoint Interaction Pattern with `<N>` = `1`, `<file>` = `01-extraction.md`, `<next step>` = `the test audit step`. Specific-feedback revision re-dispatches the Step 3 Contract extraction agent, which overwrites both the reused JSON and its rendered MD.
4. If GATE fails: print `GATE FAILED on reused $PREV_EXTRACTION_JSON (schema mismatch — likely produced by an older skill version) — falling through to fresh extraction`, remove the partial copies (`rm -f "$WORK_DIR/01-extraction.json" "$WORK_DIR/01-extraction.md"`), then proceed to Step 3 normally.

**Branch — Extract fresh:** proceed to Step 3 directly with no file copy.

### Step 3: Contract Extraction

Determine the skill directory and plugin root. Dispatch the Staff Engineer agent. **The source of truth is `01-extraction.json`**, validated against `[plugin root]/tdd-contract-review/schemas/extraction.schema.json`. After the agent returns, the orchestrator re-renders the JSON to `01-extraction.md` via `scripts/render.py --kind extraction` — humans read the MD, tooling reads the JSON. Hand-editing the MD is a correctness bug; fix in JSON and re-render.

The field vocabulary, tree grammar, and row labels still come from `contract-extraction.md` under "Output File Shape" — those rules describe the JSON structure (since the MD is just a rendering of it).

**Critical-mode pack compilation (skip entirely when critical mode is OFF).** Reuse the same `extract_section` helper defined under Step 6a.1. The Step 3 agent only needs the dimension headings + checklist bullets from each critical-mode reference file — the `## Gap Analysis Scenario Checklists` half is for Step 6 and is delivered there via separate packs:

| Pack | Source file | Section to extract | Used by |
|---|---|---|---|
| `PACK_EXTRACTION_MONEY` (critical only) | `money-correctness-checklists.md` | `Contract Extraction Details` | Step 3 agent |
| `PACK_EXTRACTION_SECURITY` (critical only) | `api-security-checklists.md` | `Contract Extraction Details` | Step 3 agent |

Same fallback rule: if `extract_section` returns empty, inline the full file and print `(splice fallback: 'Contract Extraction Details' not found in <file>, inlining full file)`. Same revision rule: re-compile on any specific-feedback revision re-dispatch.

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Contract extraction
Prompt:
  "TASK: Extract contracts for ONE unit and write to disk.
   Skill directory: [path]
   Run directory: $WORK_DIR
   Unit: [unit identifier]
   Source file: [resolved path]
   DB schema snapshot: [path, or "not found — discover via LSP walk + known-location glob"]
   Critical mode: [yes/no]
   Native LSP tool available: [$NATIVE_LSP_AVAILABLE — yes if the code-intelligence plugin is installed (Step 2.5 detection), no otherwise]

   Step 2 ran a deliberately narrow preliminary survey (test files + source file + schema snapshot only). It did NOT enumerate DB model files or outbound API clients — YOU discover those via the mandatory LSP call-tree walk below.

   Read [skill dir]/contract-extraction.md in full. It contains:
   - 'Output File Shape (01-extraction.md)' — follow the ordered sections, row labels, tree grammar, and root-set tag vocabulary verbatim; the orchestrator grep-gates on them. See benchmark/fixtures/v2-example/01-extraction.md for a worked example.
   - 'LSP-assisted call-tree construction (mandatory algorithm)' — execute the algorithm step by step. Three tool paths are available:
     - `[plugin root]/tdd-contract-review/scripts/lsp_tree.py` — preferred for Go, Ruby, and TypeScript/TSX (including React / React Native). Walks the full call tree in one invocation and persists every underlying LSP query under `$WORK_DIR/lsp/`.
     - Native `LSP` tool — for other languages (Python, Rust, Java, C#, Kotlin, Dart) when `Native LSP tool available: yes` above. Use its `definition` / `implementations` / `references` operations directly; no scripted wrapper needed.
     - `[plugin root]/tdd-contract-review/scripts/lsp_query.py` — two roles: (a) resolve a single ambiguous dispatch mid-walk when `lsp_tree.py` under-resolves a call site, or (b) last-resort fallback for non-lsp_tree languages when `Native LSP tool available: no`.
     For scripted tools, pass `--run-dir $WORK_DIR` to every invocation so each query's JSON is persisted under `$WORK_DIR/lsp/` for auditability. See `contract-extraction.md` for the exact CLIs and routing rules.
   - Per-framework extraction guidance for API / DB / Jobs / Outbound / UI Props.
   - 'Contract Extraction Summary Example' — the typed-prefix format for fields following the mandatory sections.

   [IF critical mode: do NOT read money-correctness-checklists.md or api-security-checklists.md — their extraction-relevant content is embedded below. Append the Money-correctness + API-security dimension tables after the Contract Extraction Summary, using the dimension headings from the packs as the table sections.]

   <<<CONTEXT_PACK:EXTRACTION_MONEY:start>>>
   [orchestrator inlines PACK_EXTRACTION_MONEY verbatim — Contract Extraction Details section of money-correctness-checklists.md]
   <<<CONTEXT_PACK:EXTRACTION_MONEY:end>>>

   <<<CONTEXT_PACK:EXTRACTION_SECURITY:start>>>
   [orchestrator inlines PACK_EXTRACTION_SECURITY verbatim — Contract Extraction Details section of api-security-checklists.md]
   <<<CONTEXT_PACK:EXTRACTION_SECURITY:end>>>

   LSP IS MANDATORY, NOT OPTIONAL. For Go/Ruby/TS, run `lsp_tree.py --lang <go|ruby|ts> --project <project-root> --file <rel-path> --symbol <name> --scope local --run-dir $WORK_DIR` once per root-set entry — it walks the full call tree and writes every underlying `definition` query to `$WORK_DIR/lsp/`. **Always pass `--scope local`** so the rendered tree drops stdlib / gem / `node_modules` edges (only the rendered tree is trimmed — every LSP query still runs). For other languages: if `Native LSP tool available: yes`, use the native `LSP` tool's `definition` / `implementations` / `references` on EVERY call site in EVERY own-node; if `Native LSP tool available: no`, fall back to `lsp_query.py definition --run-dir $WORK_DIR <file> <line> <col>` on every call site instead. Read+Grep is NOT a substitute. If `definition` returns empty, mark the node `[unresolved]` in the tree — do NOT silently use Grep to fill the gap. Report LSP call counts in the `## Summary` section using the line shape mandated in contract-extraction.md (`LSP calls: <D> document_symbols, <F> definitions, <R> references`).

   WRITE `$WORK_DIR/01-extraction.json` matching `[plugin root]/tdd-contract-review/schemas/extraction.schema.json`. Do NOT return the content in your response body; return only 'WROTE: $WORK_DIR/01-extraction.json' when done."
```

**Orchestrator renders MD view.** After the agent returns, run:
```bash
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind extraction \
  --input $WORK_DIR/01-extraction.json \
  --output $WORK_DIR/01-extraction.md
```
The renderer schema-validates the JSON before rendering and exits non-zero with a diagnostic if validation fails. Treat render failure as a GATE failure — do not proceed.

**GATE (Checkpoint 1 shape):** The renderer enforces schema shape (5 coverage_table rows with `Extracted` | `Not detected` | `Not applicable` statuses).

**PAUSE for user confirmation:** Apply the **Checkpoint Interaction Pattern** with:
- `<N>` = `1`
- `<file>` = `01-extraction.md`
- `<next step>` = `the test audit step`
- Specific-feedback revision target = the Step 3 **Contract extraction** agent above. Reuse its original prompt verbatim and append the REVISION REQUEST block from the Checkpoint Interaction Pattern.

**Review Hint (Checkpoint 1):**

```
- Call trees drive everything. Scan the ### Call trees fenced block: if the handler delegates to a service class that isn't an own-node (Symbol @ path:range), the extraction missed a branch — CP2 and CP3 will inherit that gap. Fixing it here is cheaper than three revisions later.
- `Not applicable` is a claim, not a gap. It asserts this contract type cannot apply to this unit. If `Outbound API: Not applicable` on a handler you think calls an external service, check for `[external -> slug]` in the tree; if none, type feedback naming the suspected call site — the agent may have missed it.
- Contract fields are the vocabulary for CP2 and CP3. A field that isn't extracted here can never be audited or gap-checked downstream. When in doubt, type feedback now.
```

### Step 4-5: Test Audit

Dispatch the Staff Engineer agent. The source of truth is `02-audit.json` (schema: `[plugin root]/tdd-contract-review/schemas/audit.schema.json`). The orchestrator re-renders to `02-audit.md` via `scripts/render.py --kind audit`. The read protocol and field vocabulary still live in `test-patterns.md`.

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Test structure audit
Prompt:
  "TASK: Audit test files against the contract extraction.
   Skill directory: [path]
   Run directory: $WORK_DIR
   Test files for this unit: [list]

   Read $WORK_DIR/01-extraction.json for the contract (produced by Step 3). The
   rendered MD view at $WORK_DIR/01-extraction.md is also available for human-
   readable browsing but the JSON is authoritative.
   Read [skill dir]/test-patterns.md in full. It contains:
   - 'Read Protocol (Test Audit)' — non-negotiable 3-step protocol: (1) framework-pattern grep count, (2) chunked read-to-EOF, (3) reconcile grep count against Test Inventory before writing. Skip any step and the audit is rejected.
   - Input/Assertion Model, sessions pattern, anti-patterns to flag, quality checklists.

   WRITE $WORK_DIR/02-audit.json matching [plugin root]/tdd-contract-review/schemas/audit.schema.json. Required top-level fields: unit, files_reviewed, test_inventory {grep_count, agent_count}, anti_patterns, per_field_coverage. test_inventory.grep_count MUST equal test_inventory.agent_count.

   Return only 'WROTE: $WORK_DIR/02-audit.json' when done."
```

**Orchestrator renders MD view:**
```bash
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind audit \
  --input $WORK_DIR/02-audit.json \
  --output $WORK_DIR/02-audit.md
```
Render failure (schema mismatch or grep/agent count mismatch) is a GATE failure.

**PAUSE for user confirmation:** Apply the **Checkpoint Interaction Pattern** with:
- `<N>` = `2`
- `<file>` = `02-audit.md`
- `<next step>` = `the gap analysis step`
- Specific-feedback revision target = the Step 4-5 **Test structure audit** agent above. Reuse its original prompt verbatim and append the REVISION REQUEST block from the Checkpoint Interaction Pattern.

**Review Hint (Checkpoint 2):**

```
- Reconciliation first. `Test files (grep count)` MUST equal `Test Inventory (agent count)` in the Summary. Mismatch means the agent skipped reads; type feedback to trigger a re-inventory before judging anything else — the coverage matrix is only trustworthy once counts reconcile.
- A test that runs is not a test that verifies. WEAK assertions (presence-only checks like `expect(x).not_to be_nil`, smoke checks with no value comparison) don't catch silent corruption. Scan Assertion Depth for WEAK entries on fields that matter — money amounts, auth headers, state transitions.
- UNCOVERED fields preview CP3 gaps. Any UNCOVERED field you're surprised by (a required request param, an enum value, a computed column) is a gap you already care about. Note it before advancing; if several look wrong, type feedback naming them.
```

### Step 6: Gap Analysis (parallel per-type + merge)

Gap analysis runs as **parallel per-type sub-dispatches** followed by a single **merge agent**. Each per-type agent has narrow context (one contract type), so it enumerates scenarios per field exhaustively instead of collapsing assertion fields into a grouped block.

#### Step 6a — Determine which types to dispatch

Read `$WORK_DIR/01-extraction.json` (the source of truth) — for each entry in `coverage_table`, branch on `status`:
- `Extracted` → dispatch a per-type agent for this type
- `Not detected` or `Not applicable` → skip this type (no sub-file produced)

```bash
jq -r '.coverage_table[] | "\(.contract_type)\t\(.status)"' "$WORK_DIR/01-extraction.json"
```

If critical mode is yes, ALSO dispatch BOTH cross-cutting agents (regardless of which contract types are Extracted):
- **F1 (money-correctness)** — uses money-correctness checklists (delivered via `PACK_MONEY_FULL`)
- **F2 (api-security)** — uses API-security checklists (delivered via `PACK_SECURITY_FULL`)

#### Step 6a.1 — Compile skill-file context packs

Before dispatching Step 6b agents, the orchestrator reads skill files ONCE and extracts the sections each agent needs. Those slices are embedded inline in each agent's dispatch prompt under `<<<CONTEXT_PACK:*>>>` markers. Sub-agents no longer run `Read [skill dir]/*.md` — the relevant content is already in their prompt. This cuts sub-agent token spend ~50% in non-critical mode, ~70% in critical mode.

**Helper (inline Bash).** Extract one `## Heading` section from a file:

```bash
extract_section() {
  # args: $1 = file path, $2 = heading text (without "## " prefix)
  awk -v h="## $2" '
    $0 == h { cap=1; print; next }
    cap && /^## / { exit }
    cap
  ' "$1"
}
```

Call multiple times and join with a blank line to concatenate sections into one pack.

**Compile these packs** (read each skill file once, extract named sections):

| Pack | Source file | Section(s) to extract | Used by |
|---|---|---|---|
| `PACK_SCENARIOS` | `scenario-checklist.md` | full file | A, B, C |
| `PACK_OUTSHAPE_PERTYPE` | `gap-analysis.md` | `Scenario Enumeration Rules (per-type agents A/B/C)` + `Output File Shape — Per-type Sub-report (A/B/C)` | A, B, C |
| `PACK_OUTSHAPE_F1` | `gap-analysis.md` | `Output File Shape — F1 Money-Correctness (\`03d-gaps-money.md\`)` | F1 |
| `PACK_OUTSHAPE_F2` | `gap-analysis.md` | `Output File Shape — F2 API-Security (\`03e-gaps-security.md\`)` | F2 |
| `PACK_MODEL` | `test-patterns.md` | `Input/Assertion Model` + `Contract Boundary Rules` | A, B, C |
| `PACK_MONEY_CHECKS` (critical only) | `money-correctness-checklists.md` | `Gap Analysis Scenario Checklists` | A, B, C |
| `PACK_MONEY_FULL` (critical only) | `money-correctness-checklists.md` | full file | F1 |
| `PACK_SECURITY_CHECKS` (critical only) | `api-security-checklists.md` | `Gap Analysis Scenario Checklists` | A, B, C |
| `PACK_SECURITY_FULL` (critical only) | `api-security-checklists.md` | full file | F2 |

**Fallback.** If `extract_section` returns empty (heading drifted or renamed), inline the full source file instead and print one line to the terminal: `(splice fallback: '<heading>' not found in <file>, inlining full file)`. Never fail the run — the agent still gets complete content, just with more tokens.

**Envelope format.** Every pack is embedded in the dispatch prompt between these markers:

```
<<<CONTEXT_PACK:<PACK_NAME>:start>>>
<extracted content, verbatim>
<<<CONTEXT_PACK:<PACK_NAME>:end>>>
```

Pack content is passed through verbatim — do not paraphrase, summarize, or reformat. The agent treats the pack as equivalent to having read that section of the source file directly.

**Revision re-dispatch.** On any specific-feedback revision re-dispatch of a per-type agent, the orchestrator MUST recompile context packs before re-dispatching. Skill files may have been updated between runs; stale packs defeat the point. (Step 6c is shell-only and has no packs.)

#### Step 6b — Parallel per-type dispatch

Dispatch all per-type agents in a single orchestrator message (parallel tool calls). Each agent writes its own sub-file and returns only `WROTE: <path>`.

**Scenario checklist.** Every field in the Test Structure Tree MUST enumerate every applicable scenario from the scenario checklist (delivered to each agent via `PACK_SCENARIOS` — see Step 6a.1), applied per the field's type + constraints. Do NOT collapse assertion fields into a "HAPPY PATH assertions" group — each assertion field gets its own branch.

**Progress output.** Before dispatching, print the plan (list only agents that will actually run — skip types marked `Not detected` / `Not applicable` in Checkpoint 1):

```
=== Step 6b: Gap analysis (<N> parallel agents) ===
→ API inbound
→ DB
→ Outbound API
→ money-correctness (critical mode)     [if critical mode]
→ API-security (critical mode)          [if critical mode]
```

After all agents return, print one `✓ <sub-file> (<N> gaps)` line per produced sub-file before proceeding to Step 6c.

**Source of truth:** `$WORK_DIR/<OUTPUT_FILE>.json` matching `[plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json`. After each agent returns, the orchestrator re-renders the JSON to `<OUTPUT_FILE>.md` via `scripts/render.py --kind gaps-per-type`. Same pattern applies to F1 (Money), F2 (API-security), and the 6c merge agent (emits `findings.json` matching `findings.schema.json`).

**Prompt template — per-type agent (used for A/B/C):**

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Gap analysis — <CONTRACT_TYPE>
Prompt:
  "TASK: Exhaustive per-field gap analysis for CONTRACT TYPE: <CONTRACT_TYPE>
   Run directory: $WORK_DIR
   Critical mode: [yes/no]

   Read $WORK_DIR/01-extraction.json — focus ONLY on the <CONTRACT_TYPE> slice under contracts.
   Read $WORK_DIR/02-audit.json — identify existing test coverage for <CONTRACT_TYPE> fields.

   DO NOT read any [skill dir]/*.md files. The skill-file content you need is embedded below under <<<CONTEXT_PACK:*>>> markers. Treat each pack as equivalent to having read that section of the source file.

   Use <TYPE_PREFIX> in gap ids (GAPI-NNN for API, GDB-NNN for DB, GOUT-NNN for Outbound — per the substitution table below this prompt).

   The output shape, scenario matrix, and input/assertion model in the packs are mandatory. Follow section headings, order, and the (<CONTRACT_TYPE>) qualifier on Test Structure Tree / Contract Map verbatim.

   <<<CONTEXT_PACK:SCENARIOS:start>>>
   [orchestrator inlines PACK_SCENARIOS verbatim]
   <<<CONTEXT_PACK:SCENARIOS:end>>>

   <<<CONTEXT_PACK:OUTSHAPE:start>>>
   [orchestrator inlines PACK_OUTSHAPE_PERTYPE verbatim]
   <<<CONTEXT_PACK:OUTSHAPE:end>>>

   <<<CONTEXT_PACK:MODEL:start>>>
   [orchestrator inlines PACK_MODEL verbatim]
   <<<CONTEXT_PACK:MODEL:end>>>

   [IF critical mode, ALSO append both blocks below:]
   <<<CONTEXT_PACK:MONEY_CHECKS:start>>>
   [orchestrator inlines PACK_MONEY_CHECKS verbatim]
   <<<CONTEXT_PACK:MONEY_CHECKS:end>>>

   <<<CONTEXT_PACK:SECURITY_CHECKS:start>>>
   [orchestrator inlines PACK_SECURITY_CHECKS verbatim]
   <<<CONTEXT_PACK:SECURITY_CHECKS:end>>>

   WRITE the full output to $WORK_DIR/<OUTPUT_FILE>.json matching [plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json. Use scope=<SCOPE_ENUM> and gap_prefix=<GAP_PREFIX_ENUM> (see substitution table). Return only 'WROTE: $WORK_DIR/<OUTPUT_FILE>.json' when done."
```

**Substitute per agent (`<OUTPUT_FILE>` is the base name; orchestrator writes `.json` and renders `.md`):**

| Agent | `<CONTRACT_TYPE>` | `<OUTPUT_FILE>` | `<TYPE_PREFIX>` | `<SCOPE_ENUM>` | `<GAP_PREFIX_ENUM>` |
|---|---|---|---|---|---|
| A | API inbound | 03a-gaps-api | API | `API inbound` | `GAPI` |
| B | DB | 03b-gaps-db | DB | `DB` | `GDB` |
| C | Outbound API | 03c-gaps-outbound | OUT | `Outbound API` | `GOUT` |

**Orchestrator renders MD view after each agent:**
```bash
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind gaps-per-type \
  --input $WORK_DIR/<OUTPUT_FILE>.json \
  --output $WORK_DIR/<OUTPUT_FILE>.md
```

**Prompt template — F1 money-correctness cross-cutting agent:**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — money-correctness cross-cutting
Prompt:
  "TASK: Cross-cutting money-correctness gap analysis for this unit.
   Run directory: $WORK_DIR

   Read $WORK_DIR/01-extraction.json (full file) and $WORK_DIR/02-audit.json (full file). MD views at .md counterparts are available for human browsing; the JSON is authoritative.

   DO NOT read any [skill dir]/*.md files. The skill-file content you need is embedded below under <<<CONTEXT_PACK:*>>> markers.

   <<<CONTEXT_PACK:MONEY_FULL:start>>>
   [orchestrator inlines PACK_MONEY_FULL verbatim — full money-correctness-checklists.md]
   <<<CONTEXT_PACK:MONEY_FULL:end>>>

   <<<CONTEXT_PACK:OUTSHAPE:start>>>
   [orchestrator inlines PACK_OUTSHAPE_F1 verbatim — systemic focus areas and Money:<dimension> type format]
   <<<CONTEXT_PACK:OUTSHAPE:end>>>

   Do NOT duplicate per-field gaps that the per-type agents will find — systemic, unit-level integrity only.

   WRITE $WORK_DIR/03d-gaps-money.json matching [plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json (scope=Money, gap_prefix=GMON). Return only 'WROTE: $WORK_DIR/03d-gaps-money.json' when done."
```

**Prompt template — F2 API-security cross-cutting agent:**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — API-security cross-cutting
Prompt:
  "TASK: Cross-cutting API-security gap analysis for this unit.
   Run directory: $WORK_DIR

   Read $WORK_DIR/01-extraction.json (full file) and $WORK_DIR/02-audit.json (full file). MD views at .md counterparts are available for human browsing; the JSON is authoritative.

   DO NOT read any [skill dir]/*.md files. The skill-file content you need is embedded below under <<<CONTEXT_PACK:*>>> markers.

   <<<CONTEXT_PACK:SECURITY_FULL:start>>>
   [orchestrator inlines PACK_SECURITY_FULL verbatim — full api-security-checklists.md]
   <<<CONTEXT_PACK:SECURITY_FULL:end>>>

   <<<CONTEXT_PACK:OUTSHAPE:start>>>
   [orchestrator inlines PACK_OUTSHAPE_F2 verbatim — systemic focus areas and Security:<dimension> type format]
   <<<CONTEXT_PACK:OUTSHAPE:end>>>

   Do NOT duplicate per-field gaps that the per-type agents will find — systemic, unit-level security integrity only.

   WRITE $WORK_DIR/03e-gaps-security.json matching [plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json (scope=Security, gap_prefix=GSEC). Return only 'WROTE: $WORK_DIR/03e-gaps-security.json' when done."
```

**GATE (sub-files shape):** After all per-type agents return, verify each expected sub-file exists and contains both `## Test Structure Tree` and `## Contract Map` (or `## Cross-cutting Money-Correctness Gaps` for F1, `## Cross-cutting API-Security Gaps` for F2). If any required sub-file is missing or malformed, print which one and stop.

#### Step 6c — Write `03-index.md` (shell, no LLM dispatch)

Shell-only: computes per-priority and per-type gap counts and writes a small index file with clickable links to each sub-file. Dedupe of overlapping gaps (F1 money ↔ A API; F2 security ↔ A API) happens inside Step 7 while the final report is written.

**Run this bash block.** `CP1_STATUS__<type>` variables are expected to be set by Step 3 based on the Checkpoint 1 Coverage table (`Extracted` | `Not detected` | `Not applicable`). If you did not capture them earlier, recover them from `$WORK_DIR/01-extraction.json` (the source of truth):

```bash
get_cp1_status() {  # arg: contract_type label
  jq -r --arg t "$1" '.coverage_table[] | select(.contract_type==$t) | .status' \
    "$WORK_DIR/01-extraction.json"
}
CP1_STATUS__API=$(get_cp1_status "API inbound")
CP1_STATUS__DB=$(get_cp1_status "DB")
CP1_STATUS__OUTBOUND=$(get_cp1_status "Outbound API")
CP1_STATUS__JOBS=$(get_cp1_status "Jobs")
CP1_STATUS__UIPROPS=$(get_cp1_status "UI Props")
```

```bash
INDEX="$WORK_DIR/03-index.md"

count_priority() {   # args: file priority
  [[ -f "$1" ]] || { echo 0; return; }
  grep -cE "^- \*\*priority\*\*: $2" "$1" || echo 0
}
count_gaps() {       # args: file
  [[ -f "$1" ]] || { echo 0; return; }
  grep -cE '^- \*\*id\*\*: G' "$1" || echo 0
}

SUB_FILES=(
  "$WORK_DIR/03a-gaps-api.md"
  "$WORK_DIR/03b-gaps-db.md"
  "$WORK_DIR/03c-gaps-outbound.md"
  "$WORK_DIR/03d-gaps-money.md"
  "$WORK_DIR/03e-gaps-security.md"
)

TOTAL_CRIT=0; TOTAL_HIGH=0; TOTAL_MED=0; TOTAL_LOW=0
for f in "${SUB_FILES[@]}"; do
  [[ -f "$f" ]] || continue
  TOTAL_CRIT=$((TOTAL_CRIT + $(count_priority "$f" CRITICAL)))
  TOTAL_HIGH=$((TOTAL_HIGH + $(count_priority "$f" HIGH)))
  TOTAL_MED=$((TOTAL_MED  + $(count_priority "$f" MEDIUM)))
  TOTAL_LOW=$((TOTAL_LOW  + $(count_priority "$f" LOW)))
done

API_CT=$(count_gaps   "$WORK_DIR/03a-gaps-api.md")
DB_CT=$(count_gaps    "$WORK_DIR/03b-gaps-db.md")
OUT_CT=$(count_gaps   "$WORK_DIR/03c-gaps-outbound.md")
MONEY_CT=$(count_gaps "$WORK_DIR/03d-gaps-money.md")
SEC_CT=$(count_gaps   "$WORK_DIR/03e-gaps-security.md")

# Helper: one CP3 Coverage row. `$1`=type label, `$2`=count, `$3`=CP1 status, `$4`=sub-file basename
cov_row() {
  local label="$1" ct="$2" cp1="$3" sub="$4"
  case "$cp1" in
    Extracted)         echo "| $label | Yes | $ct | see $sub |" ;;
    "Not detected")    echo "| $label | N/A | 0 | Not detected at CP1 |" ;;
    "Not applicable")  echo "| $label | N/A | 0 | Not applicable at CP1 |" ;;
    *)                 echo "| $label | N/A | 0 | unknown CP1 status |" ;;
  esac
}

# Write the index
{
  echo "# Gap Analysis — $UNIT"
  echo
  echo "## Summary"
  echo
  echo "Gaps by priority (across all sub-reports):"
  echo "- CRITICAL: $TOTAL_CRIT"
  echo "- HIGH: $TOTAL_HIGH"
  echo "- MEDIUM: $TOTAL_MED"
  echo "- LOW: $TOTAL_LOW"
  echo
  echo "Gaps by contract type:"
  [[ -f "$WORK_DIR/03a-gaps-api.md"      ]] && echo "- API inbound: $API_CT — [03a-gaps-api.md]($WORK_DIR/03a-gaps-api.md)"
  [[ -f "$WORK_DIR/03b-gaps-db.md"       ]] && echo "- DB: $DB_CT — [03b-gaps-db.md]($WORK_DIR/03b-gaps-db.md)"
  [[ -f "$WORK_DIR/03c-gaps-outbound.md" ]] && echo "- Outbound API: $OUT_CT — [03c-gaps-outbound.md]($WORK_DIR/03c-gaps-outbound.md)"
  [[ -f "$WORK_DIR/03d-gaps-money.md"    ]] && echo "- Money (cross-cutting): $MONEY_CT — [03d-gaps-money.md]($WORK_DIR/03d-gaps-money.md)"
  [[ -f "$WORK_DIR/03e-gaps-security.md" ]] && echo "- Security (cross-cutting): $SEC_CT — [03e-gaps-security.md]($WORK_DIR/03e-gaps-security.md)"
  echo
  echo "Critical mode: $CRITICAL_MODE"
  echo
  echo "## Checkpoint 3: Gap Coverage"
  echo
  echo "| Contract Type | Gaps Checked | Count | Notes |"
  echo "|---|---|---|---|"
  cov_row "API inbound"  "$API_CT" "$CP1_STATUS__API"      "03a-gaps-api.md"
  cov_row "DB"           "$DB_CT"  "$CP1_STATUS__DB"       "03b-gaps-db.md"
  cov_row "Outbound API" "$OUT_CT" "$CP1_STATUS__OUTBOUND" "03c-gaps-outbound.md"
  cov_row "Jobs"         0         "$CP1_STATUS__JOBS"     "(no sub-file — Jobs does not run at CP3)"
  cov_row "UI Props"     0         "$CP1_STATUS__UIPROPS"  "(no sub-file — UI Props does not run at CP3)"
} > "$INDEX"

echo "WROTE: $INDEX"
```

The index file is intentionally tiny (<50 lines). It exists for two reasons only: to give Checkpoint 3 a single file to review with clickable paths into the sub-files, and to give the gate below a grep target for the Coverage table. It is NOT consumed by Step 7-8 — the report agent reads the sub-files directly.

**GATE (Checkpoint 3 shape):** Two checks must pass.

1. **Sub-file presence.** For every type marked `Extracted` in Checkpoint 1, the corresponding sub-file must exist: `03a-gaps-api.md` for `API inbound`, `03b-gaps-db.md` for `DB`, `03c-gaps-outbound.md` for `Outbound API`. Print which is missing and stop if any is absent.
2. **Index shape.** Grep `$WORK_DIR/03-index.md` for the 5 Checkpoint 3 Coverage rows (`API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`). Every type that was `Extracted` in Checkpoint 1 must show `Yes` in Gaps Checked. If any `Extracted` type shows `N/A` or is missing, print which one and stop — the shell block in Step 6c produced a malformed index.

**PAUSE for user confirmation:** Apply the **Checkpoint Interaction Pattern** with:
- `<N>` = `3`
- `<file>` = `03-index.md`
- `<next step>` = `the final report step (Step 7-8)`
- Specific-feedback revision target — the typed text MUST name a single contract type (API inbound / DB / Outbound API / Money / Security). Re-dispatch **only** the matching per-type agent from Step 6b with the REVISION REQUEST block from the Checkpoint Interaction Pattern appended. After the per-type agent returns and its sub-file GATE passes, re-run the Step 6c shell block to regenerate `03-index.md`. There is no longer a merge agent to re-dispatch. If the typed text does not clearly name a type, ask a one-line clarification before re-dispatching.

**Review Hint (Checkpoint 3):**

```
- Priority calibration is the main risk. CRITICAL = data loss, security breach, or money off by a cent. If a CRITICAL gap reads "academic" or a MEDIUM describes a real outage path, type specific re-calibration feedback naming the sub-file (e.g., "03a-gaps-api.md HIGH #2 is really MEDIUM") — the per-type agent will honor typed requests verbatim.
- Test stubs are executable specs. Open ONE sub-file (the linked path in Summary) and read ONE CRITICAL stub end-to-end — if you can't tell what it asserts, the gap description isn't concrete enough to act on. That's a revision signal, not a Continue signal.
- Overlap is expected, not a gap. Cross-cutting F1/F2 agents deliberately overlap with the per-type agents (F1 money ↔ A API on amount fields; F2 security ↔ A API on auth). Dedupe happens in Step 7 while the report is written, not here. Two gaps describing the same failure mode across 03a and 03d is normal — do NOT treat it as a defect at CP3.
```

### Step 7-8: Report + findings.json

**Split:** `findings.json` (all gaps, merged + deduped) and `report.json` (scorecard + narrative) are the canonical structured artifacts. The orchestrator re-renders `report.md` from `report.json` via `scripts/render.py --kind report` (MD view). `findings.json` remains the machine-readable contract grading depends on — no MD render; downstream readers use jq/python. `report.json` holds only the 6-category score table, verdict, top priority actions, and a short `rationale_md` per category (LLM-authored). The numbers (score, verdict, weighted subtotals) are computed by a deterministic scoring helper the agent must run before emitting — this keeps the grader and the narrative from drifting.

**Output split.** Of these artifacts, only two get committed to the repo: `findings.json` (CI/grader machine-readable contract) and `report.md` (the human deliverable). They land in `$OUT_DIR`. Every other artifact in this step (`report.draft.json`, `report.json`) stays in `$WORK_DIR`.

**Create `$OUT_DIR` now** (deferred from Step 2 so a CP-stop doesn't leave an empty folder):

```bash
mkdir -p "$OUT_DIR"
```

Dispatch the Staff Engineer agent. The report template, findings.json schema, scoring rubric, and output rules all live in `report-template.md`.

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Report writing
Prompt:
  "TASK: Write findings.json (merged gap list — to OUT_DIR) and report.draft.json (scorecard + rationale — to WORK_DIR).
   Skill directory: [path]
   Work directory (intermediates): $WORK_DIR
   Output directory (deliverables): $OUT_DIR
   Unit: [unit identifier]
   Quick mode: [yes/no]

   Read $WORK_DIR/01-extraction.json and $WORK_DIR/02-audit.json in full.
   Read every gap sub-file JSON that exists — skip any that are absent:
     - $WORK_DIR/03a-gaps-api.json        (API inbound per-type gaps)
     - $WORK_DIR/03b-gaps-db.json         (DB per-type gaps)
     - $WORK_DIR/03c-gaps-outbound.json   (Outbound API per-type gaps)
     - $WORK_DIR/03d-gaps-money.json      (cross-cutting money, critical mode only)
     - $WORK_DIR/03e-gaps-security.json   (cross-cutting security, critical mode only)
   Do NOT read $WORK_DIR/03-index.md — it is a shell-generated index for CP3 review only and carries no content not already in the sub-files.

   DEDUPE while composing findings.json. The F1 money and F2 security cross-cutting agents deliberately overlap with the per-type A/B/C agents — e.g., F1 flags amount-precision on the same field A-API flags as missing validation; F2 flags missing auth on the same endpoint A-API flags. When two gaps describe the same (field + failure mode), keep the highest priority, combine the descriptions, and use the richer stub. This dedupe produces the final findings.json.

   Read [skill dir]/report-template.md in full. It contains:
   - 'Output Instructions' — what to write to findings.json vs report.json, and the rule that findings.json must include all four priorities (CRITICAL, HIGH, MEDIUM, LOW).
   - 'findings.json Schema' — exact JSON schema and field rules. Only CRITICAL gaps MUST have a stub; omit stub for HIGH/MEDIUM/LOW.
   - 'Scoring' — 6-category rubric, weights, verdict bands, and calibration anchors.
   - 'report.json Fields' — overall_score, verdict, categories[6], top_priority_actions, per-category rationale_md, optional exec_summary_md.

   WRITE $OUT_DIR/findings.json matching [plugin root]/tdd-contract-review/schemas/findings.schema.json.
   (findings.json is a committable deliverable — note the OUT_DIR prefix, NOT WORK_DIR.)

   WRITE $WORK_DIR/report.draft.json — a DRAFT containing unit, source_files,
   test_files, framework, fintech_mode, categories[{name, score, rationale_md}]
   (all 6 categories in the fixed order), top_priority_actions, and optional
   exec_summary_md / scoring_rationale_md. Omit overall_score, verdict,
   per-category weight, per-category weighted — the scoring helper computes
   those deterministically so the number and narrative cannot drift.

   Return only 'WROTE: $OUT_DIR/findings.json, $WORK_DIR/report.draft.json' when done."
```

**Orchestrator scores + renders MD view.** The scoring helper fills in overall_score, verdict, weight, and weighted (output stays in `$WORK_DIR`); the renderer then schema-validates and emits the MD view to `$OUT_DIR`:
```bash
[plugin root]/tdd-contract-review/scripts/score.py \
  --input $WORK_DIR/report.draft.json \
  --output $WORK_DIR/report.json
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind report \
  --input $WORK_DIR/report.json \
  --output $OUT_DIR/report.md
```
`score.py` failure (missing category, score out of range) or `render.py` schema-validation failure is a GATE failure — stop and surface the diagnostic. The intermediate `report.draft.json` is an ephemeral artifact and may be deleted after `report.json` lands.

### Step 9: Deterministic Check

No agent dispatch. Run shell checks on `$OUT_DIR/findings.json` (the committable copy):

1. **Valid JSON:** `jq empty $OUT_DIR/findings.json` (or fallback python3 json parse)
2. **CRITICAL gaps have stubs:** `jq -e '.gaps | map(select(.priority == "CRITICAL" and (.stub == null or .stub == ""))) | length == 0' $OUT_DIR/findings.json` — HIGH/MEDIUM/LOW gaps do NOT require a stub.
3. **All Extracted types represented:** for each Checkpoint 1 type with status `Extracted` in `$WORK_DIR/01-extraction.json` (`jq -r '.coverage_table[] | select(.status=="Extracted") | .contract_type'`), `jq` must find at least one gap in `$OUT_DIR/findings.json` OR the report must explicitly note coverage is complete. (Skip this check if the type is `Not detected` or `Not applicable`.)

Print:
- **PASS:** `✓ Step 9 checks passed. Report: [<ABS_PATH>](<ABS_PATH>)` — resolve `$OUT_DIR/report.md` to an absolute filesystem path and substitute it into BOTH the link label and target so Claude Code renders a clickable link.
- **FAIL:** `✗ Step 9 check failed: <which check, what's wrong>`. Do not re-dispatch. Surface the failure so a human can inspect.

## Review Principles

1. **Read the source, not just tests.**
2. **Be specific.** Every finding references `file:line`.
3. **Prioritize by breakage risk.**
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7.
6. **Do not run tests.** Static analysis only.
7. **One unit per run.** If you need to review multiple units, run the skill multiple times.
