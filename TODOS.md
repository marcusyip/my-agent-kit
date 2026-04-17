# TODOS

## Deferred from plan-eng-review (2026-04-17)

### Scalability — Incremental Mode
**Skipped in current PR.**
What: `incremental` argument to re-use `.tmp/extraction.md` if source files haven't changed (mtime check).
Why: At 50+ files, full runs cost $5-15. Incremental reduces CI cost by 80-90% for typical PRs.
Depends on: disk-based intermediate writes landing first.
Blocked by: cache invalidation is tricky (model version change, reference file update not caught by mtime).

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
