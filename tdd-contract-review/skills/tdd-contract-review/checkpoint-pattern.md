# Checkpoint Interaction Pattern

Used at all 3 review checkpoints in `SKILL.md`. The orchestrator runs a three-step interaction: echo the agent's Summary so the user has something to review, ask the checkpoint question with `AskUserQuestion`, then branch on the selection.

The PAUSE block in `SKILL.md` provides the per-checkpoint substitutions: `<N>` (1, 2, or 3), `<file>` (the artifact to review), `<next step>` (human-readable name of what comes next), and the **specific-feedback revision target** (which agent to re-dispatch when the user types free-text feedback).

## Step A — Echo Summary first

Read `$WORK_DIR/<file>` and print its `## Summary` section to the terminal. Grep the file for the literal heading `## Summary` and print every line after it up to (but not including) the next `## ` heading. Format:

```
=== Checkpoint <N> summary ($WORK_DIR/<file>) ===
<verbatim Summary section body>
==============================================
```

If no `## Summary` section is found (agent deviation), print `(Summary section missing in $WORK_DIR/<file> — open the file to review)` and proceed anyway. The step's GATE check already validates file shape; the Summary echo is a UX affordance, not a gate.

After the Summary block, print the checkpoint-specific **Review Hint** defined in that checkpoint's PAUSE section in `SKILL.md`. Format:

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

Resolve `$WORK_DIR/<file>` to an absolute filesystem path first, then substitute that same absolute path into BOTH the link label and the link target — Claude Code renders `[label](target)` as a clickable link in the terminal, and plain text (or an unresolved `$WORK_DIR`) is not clickable. Keep the line on its own with nothing trailing.

## Step B — Ask the checkpoint question

Use the `AskUserQuestion` tool — do NOT ask for free-text confirmation.

- question: `Review checkpoint <N> of 3 — proceed to <next step>? To revise, pick 'Type something else' and describe the gap.` (the clickable path is already printed in Step A; do NOT repeat `$WORK_DIR/<file>` here — `AskUserQuestion` does not render markdown, so an inline path would show as unclickable duplicate noise)
- header: `Checkpoint <N>/3`
- options (exactly these two, in this order):
  - label `Continue` — description: `Proceed to <next step>. Artifacts up to this checkpoint are final.`
  - label `Stop` — description: `Exit without proceeding. All files in $WORK_DIR are preserved.`

There is intentionally no `Revise` button. A blind "look harder" re-dispatch costs tokens without telling the agent *what* is wrong; specific typed feedback produces sharper revisions. The free-text path (below) is the only revision channel.

## Step C — Branch on selection

1. **Continue** → proceed to the next step.
2. **Stop** → preserve every file in `$WORK_DIR` and exit without proceeding. Print one line: `Stopped at checkpoint <N>. Files preserved in $WORK_DIR`.
3. **Type something else** (user picked the auto-provided free-text option — rendered as `Type something else` in the CLI) → interpret the typed text:
   - Affirmative words (`go`, `yes`, `ok`, `continue`, `proceed`) → treat as Continue.
   - Stop intent (`stop`, `quit`, `abort`, `cancel`, `no`) → treat as Stop.
   - Anything else → treat as **specific-feedback revision**: re-dispatch the same agent that produced the current file (the target is specified per checkpoint in that step's PAUSE reference) with this block appended verbatim to the agent's original prompt:

     ```
     REVISION REQUEST — INVESTIGATE → PLAN → EXECUTE (single pass, no user gate).

     The user reviewed $WORK_DIR/<file> and typed this feedback verbatim:
     <paste the user's typed text here verbatim>

     IMPORTANT: this revision SUPERSEDES any "LSP IS MANDATORY", "walk every call site", or "Read [skill dir]/*.md" language from your original prompt. You already produced $WORK_DIR/<file> in this run — treat it as your baseline and patch it, do not regenerate from scratch. Skill docs and project conventions are already reflected in the file; do not re-read them.

     Phase 1 — INVESTIGATE (narrow, targeted tools only):
     - Read $WORK_DIR/<file> to understand what's already there.
     - Then use ONLY: Read on specific source/schema/test files the feedback points at, `[plugin root]/tdd-contract-review/scripts/lsp_query.py definition <symbol>` for single call sites, narrow Grep for string-keyed lookups. The native `LSP` tool is allowed for single-symbol queries if available.
     - BANNED in this phase: full `[plugin root]/tdd-contract-review/scripts/lsp_tree.py` walks, re-reading skill reference docs, broad repo sweeps. Your job is to locate the specific gap the user named, not re-do the extraction.

     Phase 2 — PLAN:
     - Produce a 3–10 item diff plan: which sections of $WORK_DIR/<file> change, and what concretely goes in/out. Keep it terse — this is for your own discipline, not a deliverable.

     Phase 3 — EXECUTE:
     - Apply the plan with Edit (preferred — targeted in-place patch) or Write (full rewrite) on $WORK_DIR/<file>.
     - Preserve every untouched section byte-for-byte. Do not reorder, reformat, or rewrite content unrelated to the user's feedback.

     Return exactly three lines to the terminal, in this order:
     INVESTIGATED: <one sentence — what you found the gap to be>
     PATCHED: <one sentence — what sections you changed>
     WROTE: $WORK_DIR/<file>
     ```

     After re-dispatch, re-run the GATE check for this step. If the GATE fails, surface the failure and stop — do NOT loop on a failing gate. If the GATE passes, loop back to Step A (re-echo the updated Summary) and Step B (re-ask the checkpoint question). The typed text is passed through verbatim — the agent sees the user's own words, not a paraphrase.

**Revision cap: 3 per checkpoint** (counts only specific-feedback revisions). Track the count for this checkpoint in your working state for the run. On the 4th visit to the same checkpoint, prepend `Revised 3 times already — please Continue or Stop.` to the question text; if the user still types free text at that point, treat it as Continue (do not re-dispatch).
