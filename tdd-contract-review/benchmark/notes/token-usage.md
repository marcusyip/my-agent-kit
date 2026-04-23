# Token Usage — tdd-contract-review (study note)

Empirical per-step token cost for the skill, measured from benchmark run
`sample-app/tdd-contract-review/20260418-0826-post-api-v1-transactions/` (plugin
v0.35.0, critical mode ON, `POST /api/v1/transactions` unit).

**Conversion:** ~3.5 chars/token for markdown-heavy technical content.
**Source of truth for sizes:** `wc -c` on the run directory output files and the
skill reference files under `skills/tdd-contract-review/`.

---

## Reference-file sizes (inputs reused across dispatches)

| File | Bytes | ~Tokens |
|---|---:|---:|
| `SKILL.md` (loaded once into orchestrator) | 35,325 | ~10,000 |
| `contract-extraction.md` | 14,061 | ~4,000 |
| `test-patterns.md` | 13,592 | ~3,900 |
| `gap-analysis.md` | 9,095 | ~2,600 |
| `report-template.md` | 9,810 | ~2,800 |
| `api-security-checklists.md` | 9,814 | ~2,800 |
| `money-correctness-checklists.md` | 25,172 | ~7,200 |
| `scenario-checklist.md` | 2,434 | ~700 |
| `agents/staff-engineer.md` | ~2,500 | ~700 |

## Output sizes (from the benchmark run)

| File | Bytes | ~Tokens |
|---|---:|---:|
| `01-extraction.md` | 11,362 | ~3,200 |
| `02-audit.md` | 13,291 | ~3,800 |
| `03a-gaps-api.md` | 41,214 | ~11,800 |
| `03b-gaps-db.md` | 32,434 | ~9,300 |
| `03c-gaps-outbound.md` | 20,919 | ~6,000 |
| `03d-gaps-money.md` | 25,308 | ~7,200 |
| `03e-gaps-security.md` | 22,199 | ~6,300 |
| `03-gaps.md` | 98,844 | ~28,000 |
| `report.md` | 44,378 | ~12,700 |
| `findings.json` | 64,598 | ~18,500 |

---

## Per-step cost (critical mode ON)

| Step | Agent / Action | Model | Input | Output | Total |
|---|---|---|---:|---:|---:|
| 1–2 | Orchestrator: parse args, discovery, preview | — | ~2k | <0.5k | **~2.5k** |
| 2.5 | Orchestrator: optional prev-extraction summary | — | ~1k | — | **~1k** |
| 3 | Contract extraction | sonnet | ~10k non-crit / ~20k crit | ~3k | **~13k / ~23k** |
| 4–5 | Test structure audit | sonnet | ~10k | ~4k | **~14k** |
| 6b-A | Gaps — API inbound | sonnet | ~12k | ~12k | **~24k** |
| 6b-B | Gaps — DB | sonnet | ~12k | ~9k | **~21k** |
| 6b-C | Gaps — Outbound | sonnet | ~12k | ~6k | **~18k** |
| 6b-F1 | Money-correctness (critical) | **opus** | ~14k | ~7k | **~21k** |
| 6b-F2 | API-security (critical) | **opus** | ~14k | ~6k | **~20k** |
| 6c | Merge | **opus** | ~60k | ~28k | **~88k** |
| 7–8 | Report + findings.json | sonnet | ~37k | ~31k | **~68k** |
| 9 | Deterministic `jq` checks | — | <0.5k | — | **~0.5k** |

## Run totals

- **Non-critical mode (A/B/C only):** ~160k tokens
- **Critical mode (A/B/C + F1 + F2):** ~290k tokens
- **Orchestrator overhead:** `SKILL.md` ~10k loaded once + 3× checkpoint Summary
  echo ~1.5k + AskUserQuestion turns → add **~15k** to the main context.
  Sub-agent contexts are independent of main.

---

## Hotspots / cost drivers

1. **Step 6c merge (~88k, opus)** — single biggest dispatch. Ingests all
   sub-files (~40k) and emits ~28k. Opus pricing makes this the dominant $/run
   line item. Reducing sub-file verbosity compounds here 2×.
2. **Step 7–8 (~68k)** — `findings.json` alone is ~18.5k of output because every
   CRITICAL/HIGH gap carries a stub. Quick mode chops narrative but not
   findings.json.
3. **Per-type gap agents (~20k each × 3–5)** — sonnet, but the Revise-from-CP3
   path re-dispatches ALL of them in parallel, so a single Revise at CP3
   ≈ another **~100–190k**.
4. **Critical-mode surcharge:** +~130k (~80% more than non-critical), split
   across 3 opus dispatches (F1, F2, merge).
5. **Reuse at Step 2.6** saves ~13–23k (Step 3 entirely) but does nothing for
   the other ~280k.

## Revise-loop multipliers

- CP1 Revise: +~13k (one re-extraction)
- CP2 Revise: +~14k (one re-audit)
- **CP3 Revise: +~185k** — all per-type agents + merge re-dispatched. Most
  expensive button in the skill. 3-revise cap × CP3 worst-case ≈ +555k on top
  of base run.

---

## Assumptions & caveats

- Benchmark sizes are from a non-trivial `POST /api/v1/transactions` unit in
  critical mode. Small CRUD handlers are ~40–50% of these numbers.
- Inputs assume agents follow the read protocol verbatim (full-file reads of
  referenced skill files). Bash grep counts in `test-patterns.md` read-protocol
  add negligible tokens.
- Cached system-prompt / agent-definition reuse across sibling dispatches is
  not modeled. With prompt caching, the Step 6b parallel fan-out benefits most
  (shared `01`/`02`/`test-patterns`/`scenario-checklist` prefix).
- Conversion factor (~3.5 chars/token) is a heuristic. Real tokenization of
  JSON-heavy output (`findings.json`) can drift ±20%.

## Source

Derived interactively on 2026-04-18 from SKILL.md v0.35.0 and the benchmark
run listed above. Re-measure if the skill's reference files change materially.
