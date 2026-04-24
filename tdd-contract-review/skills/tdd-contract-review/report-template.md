<!-- version: 0.49.0 -->
# Report Reference

Detailed guidance for Step 7-8 of the TDD Contract Review workflow.

The report is **JSON-first**. The Step 7-8 agent writes structured JSON; the orchestrator renders Markdown views via `scripts/render.py`. Humans review the `.md`; CI / graders read the `.json`. Hand-editing a generated `.md` is a correctness bug — update the JSON source and re-render.

## What Step 7-8 emits

The agent writes two JSON artifacts:

1. **`$RUN_DIR/findings.json`** — merged + deduped gap list. Schema: `[plugin root]/tdd-contract-review/schemas/findings.schema.json`. This is the machine-readable artifact CI graders read. No MD rendering.
2. **`$RUN_DIR/report.draft.json`** — draft report with LLM-authored fields only: `categories[{name, score, rationale_md}]`, `top_priority_actions`, header metadata, optional `exec_summary_md` / `scoring_rationale_md`. The scoring helper (`scripts/score.py`) fills in derived numbers (`weight`, `weighted`, `overall_score`, `verdict`), producing the final `report.json`. The renderer then emits `report.md`. The draft is an ephemeral artifact — once `report.json` lands, the draft can be deleted.

Why split? The number and the narrative must not drift. If the LLM authors `overall_score` directly, a reviewer can change a category from 6 to 3 and forget to update the overall — the grader sees a passing score for a failing unit. With `score.py`, `overall_score` is always `sum(score_i * weight_i)`.

## findings.json

Schema: `[plugin root]/tdd-contract-review/schemas/findings.schema.json`.

- Include **every** gap from every sub-file that exists in `$RUN_DIR` (03a..03e) — all four priorities: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`. Do NOT drop MEDIUM or LOW.
- Include per-type gaps (03a/03b/03c) AND cross-cutting gaps (03d money, 03e security) when those sub-files exist.
- Do NOT include hygiene / anti-pattern entries — those are audit output, not gaps.
- `findings.json` is still written in quick mode; quick mode only affects MD rendering.

### Dedupe rule

F1 money and F2 security overlap with per-type A/B/C by design — the same field can be flagged by multiple sub-files. Dedupe by `(field + failure-mode key phrase)`:

- Keep the **highest priority** across duplicates.
- **Combine descriptions** (preserve the unique angle from each sub-file).
- Use the **richer stub** (more assertions, more setup, or critical-mode coverage beats a thinner one).
- When two gaps merge, list the merged-away ids under `merged_from: [...]` on the survivor so provenance is preserved.
- Do NOT edit the per-type sub-file JSON on disk — dedupe lives in the final `findings.json` only.

### Gap fields

- `id`: matches `^G(API|DB|OUT|MON|SEC|FIN)-\d{3}$`. Prefix follows the scope of the per-type agent that originated the finding (GAPI for API inbound, GDB for DB, GOUT for Outbound, GMON for money, GSEC for security, GFIN reserved for merged fintech-level synthesis).
- `priority`: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW`.
- `field`: typed prefix + field name (e.g., `db field: wallets.status`, `outbound response field: Stripe.Charge.status`, `unit-level` for systemic Money/Security dimensions).
- `type`: enum from `_defs.schema.json#/$defs/gapTypeCategory`: `API inbound` | `DB` | `Outbound API` | `Jobs` | `UI Props` | `Fintech:Money` | `Fintech:Idempotency` | `Fintech:StateMachine` | `Fintech:BalanceLedger` | `Fintech:ExternalIntegration` | `Fintech:Compliance` | `Fintech:Concurrency` | `Fintech:Security`.
- `description`: what's missing, plain English.
- `stub`: test stub code. **REQUIRED for CRITICAL gaps. OMIT for HIGH/MEDIUM/LOW** — field + description + priority is enough for a developer to write the real test. Use actual newline escapes in JSON (`"...\n..."`). Emit the `stub` field only when it has a value; do not include empty-string stubs for non-CRITICAL gaps.

Step 9 validates this file; invalid JSON, bad `id` pattern, or a CRITICAL gap without a stub = FAIL.

### Example — findings.json

```json
{
  "unit": "POST /api/v1/transactions",
  "fintech": true,
  "critical": true,
  "gaps": [
    {
      "id": "GMON-001",
      "priority": "CRITICAL",
      "field": "request field: amount",
      "type": "Fintech:Money",
      "description": "No test that a fractional amount below the smallest unit is rejected; silent rounding would cost money.",
      "stub": "it 'rejects sub-cent amounts' do\n  post '/api/v1/transactions', params: { amount: 0.001 }\n  expect(response.status).to eq(422)\n  expect(Transaction.count).to eq(0)\nend",
      "merged_from": ["GAPI-003", "GMON-001"]
    },
    {
      "id": "GAPI-007",
      "priority": "HIGH",
      "field": "request field: amount",
      "type": "API inbound",
      "description": "No test for negative amount (should return 422)."
    }
  ]
}
```

## report.json

Schema: `[plugin root]/tdd-contract-review/schemas/report.schema.json`. The file is intentionally lean — it holds the 6-category scorecard and top priority actions only. Contract data lives in `01-extraction.json`; gaps live in `findings.json`. The rendered `report.md` is assembled by walking report.json together with the other artifacts.

### Fields

| Field | Authored by | Notes |
|---|---|---|
| `unit`, `source_files`, `test_files`, `framework`, `fintech_mode` | LLM | Header metadata. |
| `exec_summary_md` | LLM (optional) | 2-3 sentence executive summary shown near the top of the rendered report. |
| `categories[6]` `.name` + `.score` + `.rationale_md` | LLM | `name` MUST be one of the 6 fixed values in the schema-enforced order below; `score` MUST be a number in [0, 10]; `rationale_md` is a one-sentence rationale. |
| `categories[6]` `.weight`, `.weighted` | `score.py` | Derived; LLM must NOT set these in the draft. |
| `overall_score`, `verdict` | `score.py` | Derived. |
| `top_priority_actions[1..5]` | LLM | Highest-leverage work first. `action` is prose; `related_gaps` optionally names ids from findings.json (pattern `^G(API|DB|OUT|MON|SEC|FIN)-\d{3}$`). |
| `scoring_rationale_md` | LLM (optional) | Overall narrative paragraph that wraps the category table. |

### The 6 categories (fixed names, fixed weights)

| Category | Weight | Focus |
|---|---|---|
| Contract Coverage | 25% | Are all contract fields tested? |
| Test Grouping | 15% | Grouped by feature > field for visible gaps? |
| Scenario Depth | 20% | Per field: edge cases, corner cases, error paths covered? |
| Test Case Quality | 15% | Assertion completeness, readability, meaningful data? |
| Isolation & Flakiness | 15% | Real DB, no state leakage, no flaky patterns, only external APIs mocked? |
| Anti-Patterns | 10% | Implementation testing, over-mocking, assert-free tests? |

Weights are hardcoded in `scripts/score.py`. The draft must include all 6 categories in this order with these exact `name` strings — `score.py` errors out otherwise.

### Verdict bands

| Band | Range | Meaning |
|---|---|---|
| `WEAK` | `overall_score < 4` | Major features have zero coverage; status-only assertions throughout. |
| `OK` | `4 <= overall_score < 7` | Core fields tested; significant gaps in error paths, response-body assertions, or external-API scenarios. |
| `STRONG` | `overall_score >= 7` | Every contract field has a test group; happy paths assert all response fields + DB state; enum values covered; external APIs mocked with success + failure. |

`score.py` computes `verdict` from `overall_score` deterministically; the LLM does not author `verdict`.

### Calibration anchors (for category scores, 0-10)

- **9-10** Every contract field has a test group. Happy paths assert all response fields + DB state. All enum values covered. External API mocked with success / failure / timeout. No anti-patterns. Rare — most mature codebases top out at 8.
- **7** Most contract fields tested. Happy paths exist but may miss some response fields. A few enum values or edge cases missing. Minor anti-patterns (e.g., some status-only assertions).
- **5** Core fields tested but significant gaps: missing error path coverage, incomplete happy path assertions, untested endpoints, no external API scenarios.
- **2-3** Minimal tests exist. Most contract fields untested. No test foundation pattern. Status-only assertions throughout. Major features have zero coverage.

### Example — report.draft.json (what the LLM writes)

```json
{
  "unit": "POST /api/v1/transactions",
  "source_files": ["app/controllers/api/v1/transactions_controller.rb"],
  "test_files": ["spec/requests/api/v1/transactions_spec.rb"],
  "framework": "Rails / RSpec",
  "fintech_mode": true,
  "categories": [
    {"name": "Contract Coverage",     "score": 1, "rationale_md": "33 of 36 fields have zero coverage."},
    {"name": "Test Grouping",         "score": 2, "rationale_md": "Shallow grouping; multiple endpoints per file."},
    {"name": "Scenario Depth",        "score": 1, "rationale_md": "Meaningful depth only on amount/currency."},
    {"name": "Test Case Quality",     "score": 1, "rationale_md": "Every test asserts only have_http_status."},
    {"name": "Isolation & Flakiness", "score": 4, "rationale_md": "Real DB but PaymentGateway never mocked."},
    {"name": "Anti-Patterns",         "score": 0, "rationale_md": "Seven anti-patterns surfaced at CP2."}
  ],
  "top_priority_actions": [
    {"rank": 1, "action": "Fix the double-charge via after_create callback.", "related_gaps": ["GFIN-001"]},
    {"rank": 2, "action": "Add balance-leak test for InsufficientBalanceError.", "related_gaps": ["GAPI-001", "GSEC-001"]}
  ]
}
```

After `score.py`, `overall_score` = `1*0.25 + 2*0.15 + 1*0.20 + 1*0.15 + 4*0.15 + 0*0.10` = `1.50` → `verdict = WEAK`.

## Quick mode

When the user passes `quick`, `report.draft.json` can omit `scoring_rationale_md` and collapse `top_priority_actions` to the top 3. `findings.json` is STILL written in full — it's the machine-readable output, not a rendering choice. The renderer's quick-mode MD view is an abbreviation of the full view; JSON content is unchanged.

## Hygiene section — where do anti-patterns go?

Anti-patterns live in `02-audit.json` (`.anti_patterns[]`). They are rendered into `02-audit.md`, not duplicated into `report.md`. The Step 7-8 agent does NOT re-extract or re-author anti-patterns. If a reviewer wants "the whole report as one checklist," the MD renderer can splice audit anti-patterns into the report view — that's a rendering concern, not a data concern.
