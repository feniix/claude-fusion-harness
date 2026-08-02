# Residual Review Findings

Source: ce-code-review run `20260802-133422-40f8f570` on branch `feat/auto-validate-harness` (verdict: Ready with fixes). Twelve of seventeen primary findings were applied and committed in `fix(review): apply simplification pass and review findings`; the five below were not applied (advisory class, or anchor-75 single-reviewer findings under the apply bar) and are filed as tracker tickets.

## Residual Review Findings

- P2 `scripts/builder-claude.sh:40` — Document `--dangerously-skip-permissions` rationale in KTD2 and README — [issue #1](https://github.com/feniix/claude-fusion-harness/issues/1)
- P2 `.claude/skills/auto-validate/SKILL.md:28` — SKILL.md: state how the architect derives NN for prompt filenames and polling — [issue #2](https://github.com/feniix/claude-fusion-harness/issues/2)
- P2 `.claude/skills/auto-validate/SKILL.md:30` — Bound the completion poll in the auto-validate loop — [issue #3](https://github.com/feniix/claude-fusion-harness/issues/3)
- P2 `scripts/lib/common.sh:60` — fh_timeout: KILL escalation can be cancelled during the TERM grace window — [issue #4](https://github.com/feniix/claude-fusion-harness/issues/4)
- P2 `scripts/pane.sh:71` — pane.sh dispatch: persist builder pid before/atomically with launch — [issue #5](https://github.com/feniix/claude-fusion-harness/issues/5)

No `settled_conflict`-stamped findings and no proceeded-and-flagged settled-decision conflicts occurred in this run.

Informational residual risks from the review (no tickets): Herdr pane-mode path has no automated coverage (server down during e2e; first live pane run should confirm findings fixed blind against the CLI help); Claude `--resume` fork semantics across 3+ attempts unverified; `gate_streaks` bookkeeping has no worked example in SKILL.md; concurrent runs race on `runs/log.jsonl` (accepted single-user design).
