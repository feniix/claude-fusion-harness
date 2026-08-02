---
name: auto-validate
description: Gated two-model build loop — the architect (this session) designs executable acceptance gates, then a builder (gpt-5.6-sol via pi, or a clean-room claude subprocess) iterates in an isolated worktree until the gates pass. Use when the user invokes /auto-validate with a task, asks for a validated build, or wants a task built hands-off with acceptance gates.
---

# auto-validate: the gated build loop

You are the ARCHITECT. You design the gates, dispatch the builder, judge results, and never write the implementation yourself. All model calls run on subscriptions — never set or read `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`.

## Parse the invocation

From the user's arguments take: the task (free text, or a path under `tasks/`), optional `builder:gpt|claude` (default `gpt`), optional `max:N` attempt cap (default `5`). If the task is a path, use that file; otherwise write the task text to a temp file to pass to run-init.

Pick a run id: `<yyyymmdd>-<short-slug>` from the task (e.g. `20260802-slugify`). All helper scripts live in `scripts/` at the repo root and print usage when misused.

## Set up the run

1. `scripts/run-init.sh <run-id> <builder> <max> <task-file>` — creates `runs/<run-id>/` (state.json, gates/, iterations/, control/) and the worktree `worktrees/<run-id>` on branch `fusion/<run-id>`.
2. Design the gates now, before any builder work, following `prompts/gate-design.md`. Write them to `runs/<run-id>/gates/NN-<name>.sh` and `chmod +x`.
3. `scripts/pane.sh up <run-id> worktrees/<run-id>` — Herdr pane when the server is running, headless background fallback otherwise (tell the user which).

## The loop

Repeat until pass, exhaustion, or halt. Let `RUN=runs/<run-id>`.

1. **Pause check.** If `$RUN/control/PAUSE` exists, tell the user the loop is paused and wait (poll with a background sleep); when the sentinel disappears, run the gates first (step 4) before any new dispatch — the user's edits become part of the iteration.
2. **Attempt budget.** If `attempts >= max_attempts` in `$RUN/state.json`, go to Exhaustion.
3. **Dispatch one builder turn.** First attempt: fill `prompts/builder-task.md` with the task text (`scripts/fill-prompt.sh prompts/builder-task.md '{{TASK}}' <task-file>`). Later attempts: fill `prompts/iteration-feedback.md` with the failing gate results (the `output` fields verbatim, via `fill-prompt.sh`). Write the prompt to `$RUN/iterations/NN-prompt.md`, then
   `scripts/pane.sh dispatch <run-id> -- scripts/builder-<builder>.sh worktrees/<run-id> $RUN/iterations/NN-prompt.md <run-id>`
   and poll for `$RUN/iterations/NN.json` (the completion signal; use a background `sleep`-loop, checking the pause sentinel between polls). On `timed_out: true` or a non-zero `exit` with no useful text, count the attempt and treat it as a failure with the stderr tail as feedback. Increment `attempts` in state.json (jq in-place).
4. **Run the gates.** `scripts/run-gates.sh $RUN worktrees/<run-id> > $RUN/gates-result.json`; show the user the one-line pass/fail summary per gate.
   - **All pass →** Success.
   - **Some fail →** update per-gate consecutive-failure streaks in state.json (`gate_streaks`: increment failed gates, reset passed ones), then:
5. **Gate repair check (R6).** If a gate's streak just reached 3: re-diagnose it against the task text. If the gate is faulty (tests something the task doesn't ask, or asserts wrongly):
   - If `gate_rewrite_used` is false: rewrite the gate file, set `gate_rewrite_used: true`, reset that gate's streak, and continue **without** counting a builder attempt.
   - If `gate_rewrite_used` is true: **halt** — tell the user a second gate has been judged faulty this run and stop the loop (leave everything in place).
   If the gate is sound, continue to the next iteration (feedback loop).

## Endings

Always: `scripts/pane.sh down <run-id>`, then `scripts/run-finish.sh <run-id> <outcome>`, then `scripts/log-run.sh <run-id>`.

- **Success (`passed`):** report the passing gates, token/cost totals from the iteration files, and point the user at branch `fusion/<run-id>` for review and merge — merging is deliberately theirs.
- **Exhaustion (`failed`):** write `$RUN/post-mortem.md` per `prompts/post-mortem.md`, then report it. The branch keeps the best attempt.
- **User interrupt (`aborted`):** `pane.sh down` kills the builder process tree; the worktree stays for inspection.

## Rules

- Gates are executable-only; your judgment never overrides a gate result (KD8).
- Never edit the worktree yourself during a run — pause/takeover is the user's channel, the feedback prompt is the builder's.
- The user's own working tree is untouched at all times; everything happens in `worktrees/<run-id>`.
