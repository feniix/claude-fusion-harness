#!/usr/bin/env bash
# Run teardown: record the outcome in state.json. The worktree and branch are
# deliberately left in place for inspection and review (R7, R13).
#
# Usage: run-finish.sh <run-id> <passed|failed|aborted>
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -eq 2 ] || fh_die "usage: run-finish.sh <run-id> <passed|failed|aborted>"
RUN_ID=$1 OUTCOME=$2
case "$OUTCOME" in passed | failed | aborted) ;; *) fh_die "outcome must be passed|failed|aborted, got: $OUTCOME" ;; esac

STATE="$FH_ROOT/runs/$RUN_ID/state.json"
[ -f "$STATE" ] || fh_die "no state file for run: $RUN_ID"

fh_jq_inplace "$STATE" '.status = $outcome | .ended_at = $ended | .ended_epoch = $epoch' \
  --arg outcome "$OUTCOME" --arg ended "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson epoch "$(date +%s)"

echo "fh: run $RUN_ID finished: $OUTCOME" >&2
