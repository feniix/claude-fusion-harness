#!/usr/bin/env bash
# Run setup: create the run directory skeleton, state file, and an isolated
# git worktree on branch fusion/<run-id>. The user's working tree is never
# modified (R7).
#
# Usage: run-init.sh <run-id> <builder:gpt|claude> <max-attempts> [task-file]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -ge 3 ] || fh_die "usage: run-init.sh <run-id> <builder> <max-attempts> [task-file]"
RUN_ID=$1 BUILDER=$2 MAX=$3 TASK_FILE=${4:-}

case "$BUILDER" in gpt | claude) ;; *) fh_die "builder must be gpt or claude, got: $BUILDER" ;; esac
case "$MAX" in '' | *[!0-9]*) fh_die "max-attempts must be a positive integer, got: $MAX" ;; esac
[ "$MAX" -gt 0 ] || fh_die "max-attempts must be greater than 0"
[ -z "$TASK_FILE" ] || [ -f "$TASK_FILE" ] || fh_die "task file missing: $TASK_FILE"

RUN_DIR="$FH_ROOT/runs/$RUN_ID"
WT="$FH_ROOT/worktrees/$RUN_ID"
[ -e "$RUN_DIR" ] && fh_die "run-id already exists: $RUN_ID (refusing to reuse)"
[ -e "$WT" ] && fh_die "worktree already exists: $WT (refusing to reuse)"

# A failed init must not leave a half-created run that blocks retrying the
# same run-id: clean up everything unless we reached the end.
INIT_OK=0
cleanup_partial() {
  [ "$INIT_OK" = 1 ] && return 0
  git -C "$FH_ROOT" worktree remove --force "$WT" 2> /dev/null || true
  git -C "$FH_ROOT" branch -D "fusion/$RUN_ID" 2> /dev/null || true
  rm -rf "$RUN_DIR"
  echo "fh: init failed — removed partial run $RUN_ID" >&2
}
trap cleanup_partial EXIT

mkdir -p "$RUN_DIR/gates" "$RUN_DIR/iterations" "$RUN_DIR/control"
[ -n "$TASK_FILE" ] && cp "$TASK_FILE" "$RUN_DIR/task.md"

git -C "$FH_ROOT" worktree add --quiet "$WT" -b "fusion/$RUN_ID"

jq -n --arg run_id "$RUN_ID" --arg builder "$BUILDER" --argjson max "$MAX" \
  --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson epoch "$(date +%s)" \
  '{run_id: $run_id, builder: $builder, max_attempts: $max, attempts: 0,
    gate_streaks: {}, gate_rewrite_used: false, status: "running",
    started_at: $started, started_epoch: $epoch}' > "$RUN_DIR/state.json"

INIT_OK=1
echo "fh: run $RUN_ID ready — worktree $WT (branch fusion/$RUN_ID), builder $BUILDER, max $MAX attempts" >&2
echo "$RUN_DIR"
