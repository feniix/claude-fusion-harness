---
title: Subscription Fusion Harness - Plan
type: feat
date: 2026-08-02
topic: subscription-fusion-harness
artifact_contract: ce-unified-plan/v1
artifact_readiness: requirements-only
product_contract_source: ce-brainstorm
execution: code
---

# Subscription Fusion Harness - Plan

## Goal Capsule

- **Objective:** Build v1 of a two-model agentic harness hosted in Claude Code, with `/auto-validate` as the sole command: the architect designs acceptance gates before work starts and a selectable builder iterates in isolation until the gates pass.
- **Product authority:** Personal experiment rig for a single user; success is measured by what the experiment teaches, not by production polish. The Q&A commands (`/opinion`, `/fusion`) and the deterministic runner are known follow-ons, not active scope.
- **Open blockers:** None.

---

## Product Contract

### Summary

A prompt-driven port of disler's fusion-harness with Claude Code as host and architect, running entirely on existing subscriptions: Claude Code on the Claude plan, and pi's `openai-codex` provider on the Codex plan. v1 delivers `/auto-validate` — gates designed up front, a builder (gpt-5.6-sol via pi, or a clean-room Claude subprocess) iterating in a git worktree inside a visible Herdr pane until the gates pass.

### Problem Frame

The upstream fusion-harness runs on pi as host and requires pay-as-you-go API keys for both Anthropic and OpenAI. The user already pays for a Claude subscription (Claude Code) and a Codex subscription (pi's `openai-codex` provider), so PAYG keys duplicate cost for capacity already owned. Headless pi with Codex subscription auth was verified working in this session.

The failure mode motivating `/auto-validate` first: an agent claims a task is done when it isn't — tests fail or the feature doesn't actually work — forcing the user to babysit runs instead of walking away.

### Key Decisions

- KD1. **Subscription-only auth** (session-settled: user-directed — chosen over PAYG API keys: the point of the port; capacity is already paid for). Governs R1.
- KD2. **Claude is always the architect; the builder is selectable per run** (session-settled: user-directed — chosen over fixed GPT-builder or per-run role swapping: keeps orchestration in the host while making the builder model an experiment axis). Governs R3.
- KD3. **Builder works in a git worktree** (session-settled: user-approved — chosen over editing the working tree in place: walk-away safety; an off-the-rails run never touches the user's checkout). Governs R7.
- KD4. **Herdr pane observability from v1, with headless fallback** (session-settled: user-directed — chosen over headless-with-summaries as the default: live watching and takeover are wanted from day one). Governs R8, R9, R10.
- KD5. **Prompt-driven playbook first, deterministic runner second** (session-settled: user-approved — A→B staged over building the runner now: learn what the loop needs before encoding it; artifact formats are designed so the runner can absorb the inner loop without redesign). Governs R2, R12.
- KD6. **v1 ships `/auto-validate` only** (session-settled: user-approved — the primary success criterion is less babysitting, which only the validate loop tests).
- KD7. **v1 runs only against the harness repo itself** (session-settled: user-directed — chosen over a target-repo argument: prove the loop on sample tasks before spending on real-work ergonomics).
- KD8. **Gates are executable only** (session-settled: user-approved — chosen over adding an architect-judgment gate: pass/fail is never a matter of opinion, which is what keeps the loop honest). Governs R4.
- KD9. **Every run appends to a structured run log** (session-settled: user-approved — chosen over post-mortems-only or chat-only: cross-builder comparison must be greppable, and the log doubles as the v2 runner's format). Governs R14.

### Requirements

**Auth and models**

- R1. Every model call runs on subscription auth: the architect is the hosting Claude Code session (or a spawned `claude` subprocess), and the GPT builder uses pi's `openai-codex` provider. The harness never requires or reads `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.

**Validate loop**

- R2. The harness is a prompt-driven playbook: skill instructions, prompt templates, and gate/log conventions — no orchestration daemon in v1.
- R3. The builder is selectable per invocation — gpt-5.6-sol via pi (default) or a clean-room Claude subprocess — with everything else about the run identical, so results are comparable across builders.
- R4. The architect designs executable acceptance gates — scripts or commands with exit-code pass/fail semantics — before the builder does any work; gates are the definition of done for the run.
- R5. The builder iterates against the gates until they pass or a configurable maximum number of attempts is reached; each iteration receives the failing gate output.
- R6. When the same gate fails on the builder's third consecutive attempt, the architect re-diagnoses; if the gate itself is judged faulty, the architect rewrites it — at most once per run — without consuming a builder attempt.

**Isolation and results**

- R7. The builder works on a branch in a dedicated git worktree; the user's working tree is never modified. A passing run leaves the diff on its branch awaiting the user's review and merge — a deliberate manual step.

**Observability and control**

- R8. The builder runs inside a Herdr pane the user can watch live.
- R9. Taking over the builder's pane pauses the loop; on release, the architect re-runs the gates and resumes iteration from the code as the user left it.
- R10. When Herdr is not running at invocation, the run falls back to headless execution with per-iteration outcome summaries in chat rather than refusing to start.
- R11. Interrupting the run kills all spawned builder subprocesses and leaves the worktree intact for inspection.

**Forward compatibility**

- R12. Gate format, prompt templates, and run logs are defined as stable artifacts so a v2 deterministic runner can take over the inner loop without redesigning them.

**Run outcomes and records**

- R13. A run that exhausts its attempts without passing ends with an architect-written post-mortem — which gates failed, why the builder appears stuck, suggested next step — and leaves the worktree and branch with the best attempt for inspection.
- R14. Every run, pass or fail, appends a structured record to a run log in the repo: task, builder, attempt count, per-gate outcomes, duration, and token/cost stats.

### Key Flows

- F1. Validated build
  - **Trigger:** User invokes `/auto-validate` with a task description (and optionally a builder choice).
  - **Steps:** Architect writes gates → creates worktree and branch → launches builder in a Herdr pane → after each builder turn, runs gates → on failure, feeds results back for the next attempt → on pass, reports and points at the branch.
  - **Outcome:** Verified-passing diff on a branch; user reviews and merges.
  - **Covers:** R3, R4, R5, R7, R8.
- F2. Live takeover
  - **Trigger:** User grabs the builder's pane mid-run.
  - **Steps:** Architect detects takeover and stops dispatching → user edits freely → user releases the pane → architect re-runs gates and resumes iteration from the current state.
  - **Outcome:** Human edits become part of the iteration; the loop continues.
  - **Covers:** R9.
- F3. Gate repair
  - **Trigger:** Same gate fails the builder's third consecutive attempt.
  - **Steps:** Architect re-diagnoses → gate judged faulty → gate rewritten (once per run) → loop continues without charging a builder attempt.
  - **Outcome:** A bad gate cannot burn the run's attempt budget.
  - **Covers:** R6.

### Acceptance Examples

- AE1. **Covers R5.** Given gates exist and the builder's change fails gate 2, when the iteration completes, then the builder's next attempt receives gate 2's failing output and the attempt counter increments.
- AE2. **Covers R6.** Given the same gate has failed three consecutive attempts, when the architect judges the gate faulty, then the gate is rewritten once, the attempt counter does not increment, and a second faulty-gate verdict in the same run halts the loop for the user instead of rewriting again.
- AE3. **Covers R9.** Given a loop is mid-iteration, when the user takes over the pane, then no new builder turn is dispatched until release, and the first action after release is a gate run against the user's edits.
- AE4. **Covers R10.** Given Herdr is not running, when `/auto-validate` is invoked, then the run proceeds headless and each iteration's gate results are summarized in chat.
- AE5. **Covers R11.** Given a loop is running, when the user interrupts, then no builder process survives and the worktree remains on disk with its branch intact.
- AE6. **Covers R13, R14.** Given the final allowed attempt fails a gate, when the run ends, then a post-mortem exists, the branch holds the best attempt, and the run log has a record marked failed with per-gate outcomes.

### Success Criteria

- Primary: tasks handed to `/auto-validate` come back verified-working more often than solo-Claude runs — the "claims done, isn't" failure mode is absorbed by the gates.
- Zero marginal cost: sustained use stays within both subscriptions with no PAYG charges and no rate-limit pain that makes runs unusable.
- Ergonomics: the harness is low-friction enough that it gets reached for in real work, not just demos.
- Secondary: cross-builder comparisons (same task, different builder) surface blind-spot differences worth keeping the two-model pattern for.

### Scope Boundaries

Deferred for later:

- `/opinion` and `/fusion` — follow once the validate loop proves out.
- Running against arbitrary target repos (a target-repo argument or global skill install) — v1 operates only on the harness repo's own sample tasks.
- Architect-judgment gates (e.g., a final code-quality verdict after executable gates pass).
- Deterministic runner owning the inner loop (v2 of the staged approach).
- Plugin packaging or any distribution beyond this repo.
- Role flip (GPT as architect) or fusion-style dual builders competing on one task.

Rejected:

- Driving an interactive pi TUI via screen-scraping as the control channel — the pane is for human eyes; the control channel stays `--mode json`.

### Dependencies / Assumptions

- pi installed with working `openai-codex` subscription auth — verified this session (headless `--mode json -p` call succeeded with zero API-key involvement).
- Herdr installed with its socket API available for pane creation, takeover detection, and kill; absence degrades to headless per R10.
- Assumption: sustained builder iterations stay within Codex subscription limits — testing this is itself part of the zero-marginal-cost criterion.
- Assumption: long builder turns can run as background processes under the host without timing out the loop.

### Outstanding Questions

Deferred to Planning:

- Default maximum attempts, and how the cap is overridden per run.
- Takeover detection mechanism (Herdr socket events vs polling) and what "release" looks like concretely.
- Gate execution environment: repo-native test commands vs a harness-provided runner (upstream used `uv`).
- Builder session persistence: keying and continuing pi sessions across iterations (`--session-id` vs fresh sessions per attempt).
- Invocation surface: skill name, argument shape, and where builder choice and attempt cap are expressed.
