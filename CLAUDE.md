# my-agent-kit

Claude Code plugin marketplace. One plugin today: **tdd-contract-review**. Each plugin
lives at the repo root with its own `.claude-plugin/plugin.json`, `README.md`, and
`LICENSE`. Top-level `.claude-plugin/marketplace.json` is the marketplace manifest.

Deep docs live inside each plugin. Start at
[tdd-contract-review/README.md](./tdd-contract-review/README.md) before touching the
plugin internals; see [CONTRIBUTING.md](./CONTRIBUTING.md) for how plugins are laid out.

## Repo-specific gotchas

**Version lives in FOUR places.** Use `scripts/release.sh <version>` to keep them in
sync. It bumps:

1. `tdd-contract-review/.claude-plugin/plugin.json` → `version`
2. `.claude-plugin/marketplace.json` → matching plugin entry `version`
3. `tdd-contract-review/skills/tdd-contract-review/SKILL.md` → frontmatter `version:`

…and validates that `CHANGELOG.md` already has a `## [<version>]` section at the top
(the script does not write CHANGELOG entries). Write the CHANGELOG body by hand first,
then run the script. These had drifted pre-2026-04-18 (marketplace at 0.14.0, plugin at
0.34.0, CHANGELOG at 0.34.1).

**Ignore the parent `continuously-working-with-claude-code/CLAUDE.md`.** It describes an
unrelated Slack/Discord bot project and loads automatically into context. Disregard it
in this repo.

## tdd-contract-review plugin

- **Skill**: `tdd-contract-review/skills/tdd-contract-review/SKILL.md` plus its
  companion reference files (`contract-extraction.md`, `scenario-checklist.md`,
  `test-patterns.md`, `api-security-checklists.md`, `money-correctness-checklists.md`,
  `report-template.md`). Keep each under 800 lines; split into a sibling when it grows.
- **Agent**: `tdd-contract-review/agents/staff-engineer.md`. Canonical subagent id is
  **`tdd-contract-review:staff-engineer`**. The harness error list sometimes shows a
  triple-namespaced `tdd-contract-review:tdd-contract-review:staff-engineer` form — do
  not use it.
- **Benchmark**: `tdd-contract-review/benchmark/`. `run-eval.sh` grades every unit with
  both `expected_gaps.yaml` and a run dir; `structural_check.sh` validates artifact
  shape. See `benchmark/test-plan.md` for the matrix contract. Run artifacts land in
  `benchmark/sample-app/tdd-contract-review/YYYYMMDD-HHMM-<unit-slug>/` — the directory
  name is load-bearing (Step 2 previous-extraction discovery globs on it).
- **Deferred work**: see [TODOS.md](./TODOS.md) before proposing new scope.

## Routing

The harness already injects every user-invocable skill with its trigger. Don't duplicate
that list here. Most web-app-flavored skills (`ship`, `qa`, `canary`, `design-*`,
`setup-deploy`, `land-and-deploy`) do not apply to a plugin-marketplace repo. What
usually fits here:

- `skill-eval` — evaluate or A/B the tdd-contract-review skill
- `plan-eng-review` / `plan-ceo-review` — before a sizeable plugin change
- `checkpoint` — pause/resume a long skill iteration
- `review` — pre-PR diff review
- `tdd-contract-review:tdd-contract-review` — dogfood the plugin on another project

When a request doesn't clearly match a skill, answer directly rather than forcing one.
