#!/usr/bin/env bash
# Claude builder adapter: one headless clean-room turn of the claude CLI on
# subscription auth. Uses --safe-mode (customizations disabled, OAuth intact).
# NEVER use --bare here: it restricts auth to ANTHROPIC_API_KEY and would
# violate the harness's subscription-only requirement (R1).
#
# Usage: builder-claude.sh <worktree> <prompt-file> <run-id>
# Result: writes runs/<run-id>/iterations/<NN>.json (authoritative channel).
#         Exit 0 on success, 124 on turn timeout, non-zero otherwise.
# Env:    FH_CLAUDE_MODEL (default: CLI default), FH_TURN_TIMEOUT secs (default 1800)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

fh_builder_setup "builder-claude.sh" "$@"
RAW="$RUN_DIR/iterations/$NN.claude.json"
STATE="$RUN_DIR/state.json"

# Claude session ids must be UUIDs (KTD8): mint one on the first turn, store
# it in state.json, resume it afterwards.
SESSION_UUID=""
[ -f "$STATE" ] && SESSION_UUID=$(jq -r '.claude_session_id // empty' "$STATE" 2> /dev/null || true)
SESSION_ARGS=()
if [ -n "$SESSION_UUID" ]; then
  SESSION_ARGS=(--resume "$SESSION_UUID")
else
  SESSION_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  SESSION_ARGS=(--session-id "$SESSION_UUID")
  if [ -f "$STATE" ]; then
    fh_jq_inplace "$STATE" '.claude_session_id = $id' --arg id "$SESSION_UUID"
  else
    jq -n --arg id "$SESSION_UUID" '{claude_session_id: $id}' > "$STATE"
  fi
fi

MODEL_ARGS=()
[ -n "${FH_CLAUDE_MODEL:-}" ] && MODEL_ARGS=(--model "$FH_CLAUDE_MODEL")

run_claude() {
  cd "$WT" && exec claude -p --output-format json --safe-mode \
    --dangerously-skip-permissions ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
    "${SESSION_ARGS[@]}" "$PROMPT_TEXT"
}

echo "fh[claude${FH_CLAUDE_MODEL:+/$FH_CLAUDE_MODEL}] attempt $NN starting" >&2
rc=0
fh_timeout "$TURN_TIMEOUT" "$MARKER" run_claude > "$RAW" 2> "$RUN_DIR/iterations/$NN.stderr" || rc=$?

text=$(jq -r '.result // ""' "$RAW" 2> /dev/null || echo "")
usage=$(jq -c '{input: (.usage.input_tokens // 0), output: (.usage.output_tokens // 0), total: ((.usage.input_tokens // 0) + (.usage.output_tokens // 0)), cost: (.total_cost_usd // 0)}' "$RAW" 2> /dev/null || echo "$FH_ZERO_USAGE")
# jq on an empty $RAW exits 0 with empty output, so the || fallback alone
# cannot be trusted (review finding: 0-byte result on timed-out/empty turns).
[ -n "$usage" ] || usage=$FH_ZERO_USAGE

rc=$(fh_effective_rc "$rc" "$text")
fh_emit_result "$RUN_DIR" "$NN" claude "${FH_CLAUDE_MODEL:-default}" "$text" "$usage" "$rc"
echo "fh[claude] attempt $NN done (exit $rc)" >&2
exit "$rc"
