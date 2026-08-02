# fusion-harness

A two-model agentic harness hosted in Claude Code, running entirely on existing subscriptions — no pay-as-you-go API keys. A port of the ideas in [disler/fusion-harness](https://github.com/disler/fusion-harness) with the roles inverted onto subscription auth:

- **ARCHITECT** — the hosting Claude Code session (Claude subscription). Designs executable acceptance gates before any work starts, judges results, writes post-mortems.
- **BUILDER** — selectable per run: `gpt-5.6-sol` via pi's `openai-codex` provider (Codex subscription, default), or a clean-room `claude -p --safe-mode` subprocess (Claude subscription).

v1 ships one command: **`/auto-validate`** — a gated build loop that absorbs the "claims done, isn't" failure mode. The harness never requires or reads `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.

## How a run works

1. You invoke `/auto-validate <task>` (optional tokens: `builder:gpt|claude`, `max:N`).
2. The architect writes executable gates (exit-code semantics) into the run directory — gates are the definition of done.
3. `scripts/run-init.sh` creates `runs/<run-id>/` and an isolated git worktree at `worktrees/<run-id>` on branch `fusion/<run-id>`. Your working tree is never touched.
4. The builder runs inside a Herdr pane when the Herdr server is up (watch it live, take it over); otherwise it falls back to a headless background process.
5. After each builder turn the architect runs the gates in the worktree; failing output feeds the next attempt. On the third consecutive failure of the same gate the architect re-diagnoses and may rewrite a faulty gate once per run.
6. Pass → the diff waits on `fusion/<run-id>` for your review and merge. Exhaustion → post-mortem in the run directory, branch kept with the best attempt. Every run appends a record to `runs/log.jsonl`.

## Pause / takeover

Create `runs/<run-id>/control/PAUSE` (or grab the pane with `herdr agent attach fusion-<run-id> --takeover` **and** touch the sentinel) to pause the loop. The sentinel is the authoritative signal — the architect checks it before dispatching each turn. Delete it to release; the first action after release is a gate run against your edits.

## Layout

```
.claude/skills/auto-validate/   the playbook (architect instructions)
prompts/                        gate-design / builder-task / iteration-feedback / post-mortem templates
scripts/                        leaf helpers: builder adapters, gate runner, run lifecycle, pane control
scripts/test/                   script tests (bash)
tasks/                          sample tasks for harness experiments (v1 targets this repo only)
runs/log.jsonl                  append-only run log (tracked); runs/<run-id>/ is per-run scratch (ignored)
worktrees/                      per-run git worktrees (ignored)
docs/plans/                     the plan this repo was built from
```

## Prerequisites

- [pi](https://pi.dev) with `openai-codex` subscription auth configured (`pi --provider openai-codex --list-models` should work without an API key)
- Claude Code (`claude`) logged in with a subscription
- [Herdr](https://herdr.dev) (optional — runs degrade to headless without it)
- `jq`, `git`, `shellcheck` (dev)

## Verify

```
shellcheck scripts/*.sh scripts/lib/*.sh scripts/test/*.sh scripts/test/lib/*.sh
scripts/test/run-gates.sh && scripts/test/run-lifecycle.sh && scripts/test/pane.sh
scripts/test/builder-adapters.sh   # spends a few subscription tokens
```
