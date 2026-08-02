#!/usr/bin/env bash
# Append one structured record for a finished run to runs/log.jsonl (R14) —
# the greppable cross-builder comparison surface and the v2 runner's format.
#
# Usage: log-run.sh <run-id>
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -eq 1 ] || fh_die "usage: log-run.sh <run-id>"
RUN_ID=$1
RUN_DIR="$FH_ROOT/runs/$RUN_ID"
STATE="$RUN_DIR/state.json"
[ -f "$STATE" ] || fh_die "no state file for run: $RUN_ID"

# Latest gate results, when any gate run happened.
gates='[]'
if [ -f "$RUN_DIR/gates-result.json" ]; then
  gates=$(jq -c 'map({gate, pass, exit, timed_out, duration_secs})' "$RUN_DIR/gates-result.json")
fi

# Sum usage, count attempts, and capture model in one pass over the attempts.
agg="{\"attempts\":0,\"model\":null,\"usage\":$FH_ZERO_USAGE}"
if compgen -G "$RUN_DIR/iterations/[0-9][0-9].json" > /dev/null; then
  agg=$(jq -cs '{attempts: length, model: (last.model // null),
    usage: {input: (map(.usage.input) | add), output: (map(.usage.output) | add), total: (map(.usage.total) | add), cost: (map(.usage.cost) | add)}}' \
    "$RUN_DIR"/iterations/[0-9][0-9].json)
fi

task=""
[ -f "$RUN_DIR/task.md" ] && task=$(head -1 "$RUN_DIR/task.md" | sed 's/^#* *//')

record=$(jq -c -n --arg run_id "$RUN_ID" --arg task "$task" --argjson state "$(cat "$STATE")" \
  --argjson gates "$gates" --argjson agg "$agg" \
  '{run_id: $run_id, ts: $state.started_at, task: $task, builder: $state.builder, model: $agg.model,
    outcome: $state.status, attempts: $agg.attempts, max_attempts: $state.max_attempts,
    gate_rewrite_used: $state.gate_rewrite_used,
    duration_secs: (if $state.ended_epoch and $state.started_epoch then ($state.ended_epoch - $state.started_epoch) else null end),
    gates: $gates, usage: $agg.usage}')

mkdir -p "$FH_ROOT/runs"
echo "$record" >> "$FH_ROOT/runs/log.jsonl"
echo "fh: logged run $RUN_ID to runs/log.jsonl" >&2
