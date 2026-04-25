---
name: tdd-contract-review
description: Contract-based test quality review. Reviews ONE unit per run (one HTTP endpoint, one background job, or one queue consumer). Extracts contracts, audits tests, identifies gaps, produces a scored report with CRITICAL-only test stubs, and emits machine-readable findings.json for CI grading.
argument-hint: "<unit: 'POST /path' | 'JobClass' | file.rb> [quick] [critical|no-critical]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent]
version: 0.50.1
---

# TDD Contract Review

Contract-based test quality review. **Reviews ONE unit per run.** A unit is one HTTP endpoint, one background job, or one queue consumer. The orchestrator dispatches a Staff Engineer agent at each step with focused context and writes intermediate reports to disk. The user reviews each intermediate and confirms before the next step runs.

## Output Layout

Every run writes to a flat, unit-scoped directory:

```
tdd-contract-review/{YYYYMMDD-HHMM}-{unit-slug}/
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
├── findings.json         ← merged + deduped gap list (machine-readable; CI/grader read this)
├── report.json           ← scorecard + narrative (source of truth)
└── report.md             ← rendered MD view of report.json
```

**JSON is the source of truth; MD is a rendered view.** Every numbered artifact is emitted as JSON by the agent (schema-validated against `[plugin root]/tdd-contract-review/schemas/<kind>.schema.json`), then re-rendered to Markdown by `[plugin root]/tdd-contract-review/scripts/render.py`. Humans read the MD; tooling reads the JSON. Hand-editing a generated `.md` is a correctness bug — edit the JSON and re-render.

Per-type sub-files are the source of truth for gaps — Step 7-8 reads the `.json` variants directly. `03-index.md` is a tiny shell-generated file that gives Checkpoint 3 a single reviewable artifact with clickable paths into each sub-file; it carries no content the sub-files don't already hold. Sub-reports for contract types marked `Not applicable` or `Not detected` are skipped entirely.

The `unit-slug` is lowercase kebab-case of the unit identifier:
- `POST /api/v1/transactions` → `post-api-v1-transactions`
- `ProcessPaymentJob` → `process-payment-job`
- `WithdrawalConsumer` → `withdrawal-consumer`

## Checkpoint Interaction Pattern

At each of the 3 review checkpoints, the orchestrator runs a three-step interaction: echo the agent's Summary so the user has something to review, ask the checkpoint question with `AskUserQuestion`, then branch on the selection.

### Step A — Echo Summary first

Read `$RUN_DIR/<file>` and print its `## Summary` section to the terminal. Grep the file for the literal heading `## Summary` and print every line after it up to (but not including) the next `## ` heading. Format:

```
=== Checkpoint <N> summary ($RUN_DIR/<file>) ===
<verbatim Summary section body>
==============================================
```

If no `## Summary` section is found (agent deviation), print `(Summary section missing in $RUN_DIR/<file> — open the file to review)` and proceed anyway. The step's GATE check already validates file shape; the Summary echo is a UX affordance, not a gate.

After the Summary block, print the checkpoint-specific **Review Hint** defined in that checkpoint's PAUSE section below. Format:

```
--- What to look for at Checkpoint <N> ---
<verbatim hint bullets>
-------------------------------------------
```

The hint names the two or three things most likely to matter at this checkpoint. Its job is to turn a rubber-stamp Continue into a one-minute review — especially for reviewers who don't yet have the vocabulary to spot a weak extraction or a miscalibrated gap. Print verbatim; do not paraphrase.

Then print the full report path on its own line as a **clickable markdown link** so the user can open the file before deciding:

```
Open to review: [<ABS_PATH>](<ABS_PATH>)
```

Resolve `$RUN_DIR/<file>` to an absolute filesystem path first, then substitute that same absolute path into BOTH the link label and the link target — Claude Code renders `[label](target)` as a clickable link in the terminal, and plain text (or an unresolved `$RUN_DIR`) is not clickable. Keep the line on its own with nothing trailing.

### Step B — Ask the checkpoint question

Use the `AskUserQuestion` tool — do NOT ask for free-text confirmation.

- question: `Review checkpoint <N> of 3 — proceed to <next step>? To revise, pick 'Type something else' and describe the gap.` (the clickable path is already printed in Step A; do NOT repeat `$RUN_DIR/<file>` here — `AskUserQuestion` does not render markdown, so an inline path would show as unclickable duplicate noise)
- header: `Checkpoint <N>/3`
- options (exactly these two, in this order):
  - label `Continue` — description: `Proceed to <next step>. Artifacts up to this checkpoint are final.`
  - label `Stop` — description: `Exit without proceeding. All files in $RUN_DIR are preserved.`

There is intentionally no `Revise` button. A blind "look harder" re-dispatch costs tokens without telling the agent *what* is wrong; specific typed feedback produces sharper revisions. The free-text path (below) is the only revision channel.

### Step C — Branch on selection

1. **Continue** → proceed to the next step.
2. **Stop** → preserve every file in `$RUN_DIR` and exit without proceeding. Print one line: `Stopped at checkpoint <N>. Files preserved in $RUN_DIR`.
3. **Type something else** (user picked the auto-provided free-text option — rendered as `Type something else` in the CLI) → interpret the typed text:
   - Affirmative words (`go`, `yes`, `ok`, `continue`, `proceed`) → treat as Continue.
   - Stop intent (`stop`, `quit`, `abort`, `cancel`, `no`) → treat as Stop.
   - Anything else → treat as **specific-feedback revision**: re-dispatch the same agent that produced the current file (the target is specified per checkpoint in that step's PAUSE reference) with this block appended verbatim to the agent's original prompt:

     ```
     REVISION REQUEST — INVESTIGATE → PLAN → EXECUTE (single pass, no user gate).

     The user reviewed $RUN_DIR/<file> and typed this feedback verbatim:
     <paste the user's typed text here verbatim>

     IMPORTANT: this revision SUPERSEDES any "LSP IS MANDATORY", "walk every call site", or "Read [skill dir]/*.md" language from your original prompt. You already produced $RUN_DIR/<file> in this run — treat it as your baseline and patch it, do not regenerate from scratch. Skill docs and project conventions are already reflected in the file; do not re-read them.

     Phase 1 — INVESTIGATE (narrow, targeted tools only):
     - Read $RUN_DIR/<file> to understand what's already there.
     - Then use ONLY: Read on specific source/schema/test files the feedback points at, `[plugin root]/tdd-contract-review/scripts/lsp_query.py definition <symbol>` for single call sites, narrow Grep for string-keyed lookups. The native `LSP` tool is allowed for single-symbol queries if available.
     - BANNED in this phase: full `[plugin root]/tdd-contract-review/scripts/lsp_tree.py` walks, re-reading skill reference docs, broad repo sweeps. Your job is to locate the specific gap the user named, not re-do the extraction.

     Phase 2 — PLAN:
     - Produce a 3–10 item diff plan: which sections of $RUN_DIR/<file> change, and what concretely goes in/out. Keep it terse — this is for your own discipline, not a deliverable.

     Phase 3 — EXECUTE:
     - Apply the plan with Edit (preferred — targeted in-place patch) or Write (full rewrite) on $RUN_DIR/<file>.
     - Preserve every untouched section byte-for-byte. Do not reorder, reformat, or rewrite content unrelated to the user's feedback.

     Return exactly three lines to the terminal, in this order:
     INVESTIGATED: <one sentence — what you found the gap to be>
     PATCHED: <one sentence — what sections you changed>
     WROTE: $RUN_DIR/<file>
     ```

     After re-dispatch, re-run the GATE check for this step. If the GATE fails, surface the failure and stop — do NOT loop on a failing gate. If the GATE passes, loop back to Step A (re-echo the updated Summary) and Step B (re-ask the checkpoint question). The typed text is passed through verbatim — the agent sees the user's own words, not a paraphrase.

**Revision cap: 3 per checkpoint** (counts only specific-feedback revisions). Track the count for this checkpoint in your working state for the run. On the 4th visit to the same checkpoint, prepend `Revised 3 times already — please Continue or Stop.` to the question text; if the user still types free text at that point, treat it as Continue (do not re-dispatch).

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

**Compute unit-slug** from the identifier. Compute run directory: `tdd-contract-review/$(date +%Y%m%d-%H%M)-{unit-slug}/`. Create the directory. Store path as `$RUN_DIR`.

**Look for a previous extraction for this unit.** Glob `tdd-contract-review/*-{unit-slug}/01-extraction.md`, exclude `$RUN_DIR` itself, sort results by the `YYYYMMDD-HHMM` timestamp prefix in the directory name (lexicographic order works), pick the most recent. Store its path as `$PREV_EXTRACTION` (empty string if no match). This drives the optional reuse ask in Step 2.6.

**Run preview.** Before proceeding to Step 3, print this 1-screen summary so the user can interrupt before the first agent dispatch:

```
=== TDD Contract Review — Run Preview ===
Unit:                <unit identifier>
Source:              <resolved source file:line of handler or class def>
DB schema snapshot:  <path, or "not found">
Critical mode:       ON (reason: <one-line signal that triggered it, e.g., "test file mentions 'amount'" or "decimal column 'balance' in db/schema.rb">)
                     OR OFF
Previous extraction: found at <$PREV_EXTRACTION> (<YYYY-MM-DD HH:MM from dir prefix>)
                     OR "none found (skip reuse ask)"
Pipeline:            <N> agent dispatches, 3 checkpoints
Run dir:             $RUN_DIR
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

If `$PREV_EXTRACTION` is empty, skip this step entirely — do not print anything, do not ask — and proceed to Step 3.

If `$PREV_EXTRACTION` is set, offer the user the choice to reuse it or run a fresh extraction. This saves the cost of re-extracting when iterating on the same unit with unchanged source.

**Critical-mode mismatch check (do this BEFORE the ask):** Read the `Critical mode:` line from `$PREV_EXTRACTION` (it appears in the file's `## Summary` section) and compare to the current run's critical-mode. If they differ, print a one-line warning with the path preview below: `Previous extraction was Critical mode: <X>, current run is Critical mode: <Y>. Fresh extraction recommended.`

**Path preview (print BEFORE calling AskUserQuestion):** Resolve `$PREV_EXTRACTION` to an absolute filesystem path, then print the clickable markdown link on its own line so the user can open the prior file before choosing:

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
  A) Reuse       — copy into $RUN_DIR and go straight to Checkpoint 1
  B) Extract fresh — run the Step 3 extraction agent as normal
Multi-select: false
```

Free-text fallback (user typed something instead of picking): treat affirmative-sounding text ("reuse", "yes", "copy", "skip") as Reuse; anything else as Extract fresh.

**Branch — Reuse:**

1. Copy the file: `cp "$PREV_EXTRACTION" "$RUN_DIR/01-extraction.md"` via Bash.
2. Run the **Checkpoint 1 shape GATE** (same grep used in Step 3, described under "GATE (Checkpoint 1 shape)" below): verify all 5 required rows (`API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`) appear with a valid three-state status (`Extracted` | `Not detected` | `Not applicable`).
3. If GATE passes: jump directly to the **Checkpoint 1 PAUSE** in Step 3 — apply the Checkpoint Interaction Pattern with `<N>` = `1`, `<file>` = `01-extraction.md`, `<next step>` = `the test audit step`. Specific-feedback revision re-dispatches the Step 3 Contract extraction agent, overwriting the reused file.
4. If GATE fails: print `GATE FAILED on reused $PREV_EXTRACTION (file is malformed or from an older skill version) — falling through to fresh extraction`, then proceed to Step 3 normally. Do not leave the malformed copy in `$RUN_DIR` — either remove it first (`rm "$RUN_DIR/01-extraction.md"`) or let Step 3's agent overwrite it.

**Branch — Extract fresh:** proceed to Step 3 directly with no file copy.

### Step 3: Contract Extraction

Determine the skill directory and plugin root. Dispatch the Staff Engineer agent. **The source of truth is `01-extraction.json`**, validated against `[plugin root]/tdd-contract-review/schemas/extraction.schema.json`. After the agent returns, the orchestrator re-renders the JSON to `01-extraction.md` via `scripts/render.py --kind extraction` — humans read the MD, tooling reads the JSON. Hand-editing the MD is a correctness bug; fix in JSON and re-render.

The field vocabulary, tree grammar, and row labels still come from `contract-extraction.md` under "Output File Shape" — those rules describe the JSON structure (since the MD is just a rendering of it).

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Contract extraction
Prompt:
  "TASK: Extract contracts for ONE unit and write to disk.
   Skill directory: [path]
   Run directory: $RUN_DIR
   Unit: [unit identifier]
   Source file: [resolved path]
   DB schema snapshot: [path, or "not found — discover via LSP walk + known-location glob"]
   Critical mode: [yes/no]
   Native LSP tool available: [$NATIVE_LSP_AVAILABLE — yes if the code-intelligence plugin is installed (Step 2.5 detection), no otherwise]

   Step 2 ran a deliberately narrow preliminary survey (test files + source file + schema snapshot only). It did NOT enumerate DB model files or outbound API clients — YOU discover those via the mandatory LSP call-tree walk below.

   Read [skill dir]/contract-extraction.md in full. It contains:
   - 'Output File Shape (01-extraction.md)' — follow the ordered sections, row labels, tree grammar, and root-set tag vocabulary verbatim; the orchestrator grep-gates on them. See benchmark/fixtures/v2-example/01-extraction.md for a worked example.
   - 'LSP-assisted call-tree construction (mandatory algorithm)' — execute the algorithm step by step. Three tool paths are available:
     - `[plugin root]/tdd-contract-review/scripts/lsp_tree.py` — preferred for Go, Ruby, and TypeScript/TSX (including React / React Native). Walks the full call tree in one invocation and persists every underlying LSP query under `$RUN_DIR/lsp/`.
     - Native `LSP` tool — for other languages (Python, Rust, Java, C#, Kotlin, Dart) when `Native LSP tool available: yes` above. Use its `definition` / `implementations` / `references` operations directly; no scripted wrapper needed.
     - `[plugin root]/tdd-contract-review/scripts/lsp_query.py` — two roles: (a) resolve a single ambiguous dispatch mid-walk when `lsp_tree.py` under-resolves a call site, or (b) last-resort fallback for non-lsp_tree languages when `Native LSP tool available: no`.
     For scripted tools, pass `--run-dir $RUN_DIR` to every invocation so each query's JSON is persisted under `$RUN_DIR/lsp/` for auditability. See `contract-extraction.md` for the exact CLIs and routing rules.
   - Per-framework extraction guidance for API / DB / Jobs / Outbound / UI Props.
   - 'Contract Extraction Summary Example' — the typed-prefix format for fields following the mandatory sections.

   If critical mode: also read [skill dir]/money-correctness-checklists.md and [skill dir]/api-security-checklists.md, and append the Money-correctness + API-security dimension tables after the Contract Extraction Summary.

   LSP IS MANDATORY, NOT OPTIONAL. For Go/Ruby/TS, run `lsp_tree.py --lang <go|ruby|ts> --project <project-root> --file <rel-path> --symbol <name> --scope local --run-dir $RUN_DIR` once per root-set entry — it walks the full call tree and writes every underlying `definition` query to `$RUN_DIR/lsp/`. **Always pass `--scope local`** so the rendered tree drops stdlib / gem / `node_modules` edges (only the rendered tree is trimmed — every LSP query still runs). For other languages: if `Native LSP tool available: yes`, use the native `LSP` tool's `definition` / `implementations` / `references` on EVERY call site in EVERY own-node; if `Native LSP tool available: no`, fall back to `lsp_query.py definition --run-dir $RUN_DIR <file> <line> <col>` on every call site instead. Read+Grep is NOT a substitute. If `definition` returns empty, mark the node `[unresolved]` in the tree — do NOT silently use Grep to fill the gap. Report LSP call counts in the `## Summary` section using the line shape mandated in contract-extraction.md (`LSP calls: <D> document_symbols, <F> definitions, <R> references`).

   WRITE `$RUN_DIR/01-extraction.json` matching `[plugin root]/tdd-contract-review/schemas/extraction.schema.json`. Do NOT return the content in your response body; return only 'WROTE: $RUN_DIR/01-extraction.json' when done."
```

**Orchestrator renders MD view.** After the agent returns, run:
```bash
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind extraction \
  --input $RUN_DIR/01-extraction.json \
  --output $RUN_DIR/01-extraction.md
```
The renderer schema-validates the JSON before rendering and exits non-zero with a diagnostic if validation fails. Treat render failure as a GATE failure — do not proceed.

**GATE (Checkpoint 1 shape):** The renderer enforces schema shape (5 coverage_table rows with `Extracted` | `Not detected` | `Not applicable` statuses). The legacy grep gate on `$RUN_DIR/01-extraction.md` remains as a backstop but should never fail when JSON validation passes.

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
   Run directory: $RUN_DIR
   Test files for this unit: [list]

   Read $RUN_DIR/01-extraction.json for the contract (produced by Step 3). The
   rendered MD view at $RUN_DIR/01-extraction.md is also available for human-
   readable browsing but the JSON is authoritative.
   Read [skill dir]/test-patterns.md in full. It contains:
   - 'Read Protocol (Test Audit)' — non-negotiable 3-step protocol: (1) framework-pattern grep count, (2) chunked read-to-EOF, (3) reconcile grep count against Test Inventory before writing. Skip any step and the audit is rejected.
   - Input/Assertion Model, sessions pattern, anti-patterns to flag, quality checklists.

   WRITE $RUN_DIR/02-audit.json matching [plugin root]/tdd-contract-review/schemas/audit.schema.json. Required top-level fields: unit, files_reviewed, test_inventory {grep_count, agent_count}, anti_patterns, per_field_coverage. test_inventory.grep_count MUST equal test_inventory.agent_count.

   Return only 'WROTE: $RUN_DIR/02-audit.json' when done."
```

**Orchestrator renders MD view:**
```bash
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind audit \
  --input $RUN_DIR/02-audit.json \
  --output $RUN_DIR/02-audit.md
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

Read `$RUN_DIR/01-extraction.md`. For each Checkpoint 1 row, look at the Status column:
- `Extracted` → dispatch a per-type agent for this type
- `Not detected` or `Not applicable` → skip this type (no sub-file produced)

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

**Source of truth:** `$RUN_DIR/<OUTPUT_FILE>.json` matching `[plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json`. After each agent returns, the orchestrator re-renders the JSON to `<OUTPUT_FILE>.md` via `scripts/render.py --kind gaps-per-type`. Same pattern applies to F1 (Money), F2 (API-security), and the 6c merge agent (emits `findings.json` matching `findings.schema.json`).

**Prompt template — per-type agent (used for A/B/C):**

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Gap analysis — <CONTRACT_TYPE>
Prompt:
  "TASK: Exhaustive per-field gap analysis for CONTRACT TYPE: <CONTRACT_TYPE>
   Run directory: $RUN_DIR
   Critical mode: [yes/no]

   Read $RUN_DIR/01-extraction.json — focus ONLY on the <CONTRACT_TYPE> slice under contracts.
   Read $RUN_DIR/02-audit.json — identify existing test coverage for <CONTRACT_TYPE> fields.

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

   WRITE the full output to $RUN_DIR/<OUTPUT_FILE>.json matching [plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json. Use scope=<SCOPE_ENUM> and gap_prefix=<GAP_PREFIX_ENUM> (see substitution table). Return only 'WROTE: $RUN_DIR/<OUTPUT_FILE>.json' when done."
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
  --input $RUN_DIR/<OUTPUT_FILE>.json \
  --output $RUN_DIR/<OUTPUT_FILE>.md
```

**Prompt template — F1 money-correctness cross-cutting agent:**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — money-correctness cross-cutting
Prompt:
  "TASK: Cross-cutting money-correctness gap analysis for this unit.
   Run directory: $RUN_DIR

   Read $RUN_DIR/01-extraction.json (full file) and $RUN_DIR/02-audit.json (full file). MD views at .md counterparts are available for human browsing; the JSON is authoritative.

   DO NOT read any [skill dir]/*.md files. The skill-file content you need is embedded below under <<<CONTEXT_PACK:*>>> markers.

   <<<CONTEXT_PACK:MONEY_FULL:start>>>
   [orchestrator inlines PACK_MONEY_FULL verbatim — full money-correctness-checklists.md]
   <<<CONTEXT_PACK:MONEY_FULL:end>>>

   <<<CONTEXT_PACK:OUTSHAPE:start>>>
   [orchestrator inlines PACK_OUTSHAPE_F1 verbatim — systemic focus areas and Money:<dimension> type format]
   <<<CONTEXT_PACK:OUTSHAPE:end>>>

   Do NOT duplicate per-field gaps that the per-type agents will find — systemic, unit-level integrity only.

   WRITE $RUN_DIR/03d-gaps-money.json matching [plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json (scope=Money, gap_prefix=GMON). Return only 'WROTE: $RUN_DIR/03d-gaps-money.json' when done."
```

**Prompt template — F2 API-security cross-cutting agent:**

```
Agent:       tdd-contract-review:staff-engineer
Model:       opus
Description: Gap analysis — API-security cross-cutting
Prompt:
  "TASK: Cross-cutting API-security gap analysis for this unit.
   Run directory: $RUN_DIR

   Read $RUN_DIR/01-extraction.json (full file) and $RUN_DIR/02-audit.json (full file). MD views at .md counterparts are available for human browsing; the JSON is authoritative.

   DO NOT read any [skill dir]/*.md files. The skill-file content you need is embedded below under <<<CONTEXT_PACK:*>>> markers.

   <<<CONTEXT_PACK:SECURITY_FULL:start>>>
   [orchestrator inlines PACK_SECURITY_FULL verbatim — full api-security-checklists.md]
   <<<CONTEXT_PACK:SECURITY_FULL:end>>>

   <<<CONTEXT_PACK:OUTSHAPE:start>>>
   [orchestrator inlines PACK_OUTSHAPE_F2 verbatim — systemic focus areas and Security:<dimension> type format]
   <<<CONTEXT_PACK:OUTSHAPE:end>>>

   Do NOT duplicate per-field gaps that the per-type agents will find — systemic, unit-level security integrity only.

   WRITE $RUN_DIR/03e-gaps-security.json matching [plugin root]/tdd-contract-review/schemas/gaps-per-type.schema.json (scope=Security, gap_prefix=GSEC). Return only 'WROTE: $RUN_DIR/03e-gaps-security.json' when done."
```

**GATE (sub-files shape):** After all per-type agents return, verify each expected sub-file exists and contains both `## Test Structure Tree` and `## Contract Map` (or `## Cross-cutting Money-Correctness Gaps` for F1, `## Cross-cutting API-Security Gaps` for F2). If any required sub-file is missing or malformed, print which one and stop.

#### Step 6c — Write `03-index.md` (shell, no LLM dispatch)

Prior versions ran an opus "merge" agent that re-ingested every sub-file and rewrote them as a unified `03-gaps.md` — ~100k tokens/run to re-encode information Step 7-8 re-reads anyway. This step is now shell-only: it computes per-priority and per-type gap counts and writes a small index file with clickable links to each sub-file. Dedupe of overlapping gaps (F1 money ↔ A API; F2 security ↔ A API) now happens inside Step 7 while the final report is written.

**Run this bash block.** `CP1_STATUS__<type>` variables are expected to be set by Step 3 based on the Checkpoint 1 Coverage table (`Extracted` | `Not detected` | `Not applicable`). If you did not capture them earlier, re-parse from `$RUN_DIR/01-extraction.md` now.

```bash
INDEX="$RUN_DIR/03-index.md"

count_priority() {   # args: file priority
  [[ -f "$1" ]] || { echo 0; return; }
  grep -cE "^- \*\*priority\*\*: $2" "$1" || echo 0
}
count_gaps() {       # args: file
  [[ -f "$1" ]] || { echo 0; return; }
  grep -cE '^- \*\*id\*\*: G' "$1" || echo 0
}

SUB_FILES=(
  "$RUN_DIR/03a-gaps-api.md"
  "$RUN_DIR/03b-gaps-db.md"
  "$RUN_DIR/03c-gaps-outbound.md"
  "$RUN_DIR/03d-gaps-money.md"
  "$RUN_DIR/03e-gaps-security.md"
)

TOTAL_CRIT=0; TOTAL_HIGH=0; TOTAL_MED=0; TOTAL_LOW=0
for f in "${SUB_FILES[@]}"; do
  [[ -f "$f" ]] || continue
  TOTAL_CRIT=$((TOTAL_CRIT + $(count_priority "$f" CRITICAL)))
  TOTAL_HIGH=$((TOTAL_HIGH + $(count_priority "$f" HIGH)))
  TOTAL_MED=$((TOTAL_MED  + $(count_priority "$f" MEDIUM)))
  TOTAL_LOW=$((TOTAL_LOW  + $(count_priority "$f" LOW)))
done

API_CT=$(count_gaps   "$RUN_DIR/03a-gaps-api.md")
DB_CT=$(count_gaps    "$RUN_DIR/03b-gaps-db.md")
OUT_CT=$(count_gaps   "$RUN_DIR/03c-gaps-outbound.md")
MONEY_CT=$(count_gaps "$RUN_DIR/03d-gaps-money.md")
SEC_CT=$(count_gaps   "$RUN_DIR/03e-gaps-security.md")

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
  [[ -f "$RUN_DIR/03a-gaps-api.md"      ]] && echo "- API inbound: $API_CT — [03a-gaps-api.md]($RUN_DIR/03a-gaps-api.md)"
  [[ -f "$RUN_DIR/03b-gaps-db.md"       ]] && echo "- DB: $DB_CT — [03b-gaps-db.md]($RUN_DIR/03b-gaps-db.md)"
  [[ -f "$RUN_DIR/03c-gaps-outbound.md" ]] && echo "- Outbound API: $OUT_CT — [03c-gaps-outbound.md]($RUN_DIR/03c-gaps-outbound.md)"
  [[ -f "$RUN_DIR/03d-gaps-money.md"    ]] && echo "- Money (cross-cutting): $MONEY_CT — [03d-gaps-money.md]($RUN_DIR/03d-gaps-money.md)"
  [[ -f "$RUN_DIR/03e-gaps-security.md" ]] && echo "- Security (cross-cutting): $SEC_CT — [03e-gaps-security.md]($RUN_DIR/03e-gaps-security.md)"
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
2. **Index shape.** Grep `$RUN_DIR/03-index.md` for the 5 Checkpoint 3 Coverage rows (`API inbound`, `DB`, `Outbound API`, `Jobs`, `UI Props`). Every type that was `Extracted` in Checkpoint 1 must show `Yes` in Gaps Checked. If any `Extracted` type shows `N/A` or is missing, print which one and stop — the shell block in Step 6c produced a malformed index.

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

Dispatch the Staff Engineer agent. The report template, findings.json schema, scoring rubric, and output rules all live in `report-template.md`.

```
Agent:       tdd-contract-review:staff-engineer
Model:       sonnet
Description: Report writing
Prompt:
  "TASK: Write findings.json (merged gap list) and report.json (scorecard + rationale).
   Skill directory: [path]
   Run directory: $RUN_DIR
   Unit: [unit identifier]
   Quick mode: [yes/no]

   Read $RUN_DIR/01-extraction.json and $RUN_DIR/02-audit.json in full.
   Read every gap sub-file JSON that exists — skip any that are absent:
     - $RUN_DIR/03a-gaps-api.json        (API inbound per-type gaps)
     - $RUN_DIR/03b-gaps-db.json         (DB per-type gaps)
     - $RUN_DIR/03c-gaps-outbound.json   (Outbound API per-type gaps)
     - $RUN_DIR/03d-gaps-money.json      (cross-cutting money, critical mode only)
     - $RUN_DIR/03e-gaps-security.json   (cross-cutting security, critical mode only)
   Do NOT read $RUN_DIR/03-index.md — it is a shell-generated index for CP3 review only and carries no content not already in the sub-files.

   DEDUPE while composing findings.json. The F1 money and F2 security cross-cutting agents deliberately overlap with the per-type A/B/C agents — e.g., F1 flags amount-precision on the same field A-API flags as missing validation; F2 flags missing auth on the same endpoint A-API flags. When two gaps describe the same (field + failure mode), keep the highest priority, combine the descriptions, and use the richer stub. This dedupe produces the final findings.json.

   Read [skill dir]/report-template.md in full. It contains:
   - 'Output Instructions' — what to write to findings.json vs report.json, and the rule that findings.json must include all four priorities (CRITICAL, HIGH, MEDIUM, LOW).
   - 'findings.json Schema' — exact JSON schema and field rules. Only CRITICAL gaps MUST have a stub; omit stub for HIGH/MEDIUM/LOW.
   - 'Scoring' — 6-category rubric, weights, verdict bands, and calibration anchors.
   - 'report.json Fields' — overall_score, verdict, categories[6], top_priority_actions, per-category rationale_md, optional exec_summary_md.

   WRITE $RUN_DIR/findings.json matching [plugin root]/tdd-contract-review/schemas/findings.schema.json.

   WRITE $RUN_DIR/report.draft.json — a DRAFT containing unit, source_files,
   test_files, framework, fintech_mode, categories[{name, score, rationale_md}]
   (all 6 categories in the fixed order), top_priority_actions, and optional
   exec_summary_md / scoring_rationale_md. Omit overall_score, verdict,
   per-category weight, per-category weighted — the scoring helper computes
   those deterministically so the number and narrative cannot drift.

   Return only 'WROTE: findings.json, report.draft.json' when done."
```

**Orchestrator scores + renders MD view.** The scoring helper fills in overall_score, verdict, weight, and weighted; the renderer then schema-validates and emits the MD view:
```bash
[plugin root]/tdd-contract-review/scripts/score.py \
  --input $RUN_DIR/report.draft.json \
  --output $RUN_DIR/report.json
[plugin root]/tdd-contract-review/scripts/render.py \
  --kind report \
  --input $RUN_DIR/report.json \
  --output $RUN_DIR/report.md
```
`score.py` failure (missing category, score out of range) or `render.py` schema-validation failure is a GATE failure — stop and surface the diagnostic. The intermediate `report.draft.json` is an ephemeral artifact and may be deleted after `report.json` lands.

### Step 9: Deterministic Check

No agent dispatch. Run shell checks on `$RUN_DIR/findings.json`:

1. **Valid JSON:** `jq empty $RUN_DIR/findings.json` (or fallback python3 json parse)
2. **CRITICAL gaps have stubs:** `jq -e '.gaps | map(select(.priority == "CRITICAL" and (.stub == null or .stub == ""))) | length == 0' $RUN_DIR/findings.json` — HIGH/MEDIUM/LOW gaps do NOT require a stub.
3. **All Extracted types represented:** for each Checkpoint 1 type with status `Extracted` in `01-extraction.md`, `jq` must find at least one gap OR the report must explicitly note coverage is complete. (Skip this check if the type is `Not detected` or `Not applicable`.)

Print:
- **PASS:** `✓ Step 9 checks passed. Report: [<ABS_PATH>](<ABS_PATH>)` — resolve `$RUN_DIR/report.md` to an absolute filesystem path and substitute it into BOTH the link label and target so Claude Code renders a clickable link.
- **FAIL:** `✗ Step 9 check failed: <which check, what's wrong>`. Do not re-dispatch. Surface the failure so a human can inspect.

## Review Principles

1. **Read the source, not just tests.**
2. **Be specific.** Every finding references `file:line`.
3. **Prioritize by breakage risk.**
4. **Respect the mock boundary.** Only external API calls should be mocked.
5. **Be calibrated.** Most codebases score 4-7.
6. **Do not run tests.** Static analysis only.
7. **One unit per run.** If you need to review multiple units, run the skill multiple times.
