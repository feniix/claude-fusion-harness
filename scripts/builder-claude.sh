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

[ $# -eq 3 ] || fh_die "usage: builder-claude.sh <worktree> <prompt-file> <run-id>"
WT=$1 PROMPT=$2 RUN_ID=$3
RUN_DIR="$FH_ROOT/runs/$RUN_ID"
[ -d "$RUN_DIR/iterations" ] || fh_die "run dir missing: $RUN_DIR/iterations"
[ -f "$PROMPT" ] || fh_die "prompt file missing: $PROMPT"
[ -d "$WT" ] || fh_die "worktree missing: $WT"
# Resolve before any cd: callers may pass repo-relative paths.
WT="$(cd "$WT" && pwd)"
PROMPT_TEXT="$(cat "$PROMPT")"

TURN_TIMEOUT="${FH_TURN_TIMEOUT:-1800}"
NN=$(fh_next_attempt "$RUN_DIR")
RAW="$RUN_DIR/iterations/$NN.claude.json"
MARKER="$RUN_DIR/iterations/$NN.timeout"
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
    tmp=$(mktemp)
    jq --arg id "$SESSION_UUID" '.claude_session_id = $id' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
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

timed_out=false
[ "$rc" -eq 124 ] && timed_out=true

text=$(jq -r '.result // ""' "$RAW" 2> /dev/null || echo "")
usage=$(jq -c '{input: (.usage.input_tokens // 0), output: (.usage.output_tokens // 0), total: ((.usage.input_tokens // 0) + (.usage.output_tokens // 0)), cost: (.total_cost_usd // 0)}' "$RAW" 2> /dev/null || echo '{"input":0,"output":0,"total":0,"cost":0}')

if [ "$rc" -eq 0 ] && [ -z "$text" ]; then rc=1; fi

jq -n --arg builder claude --arg model "${FH_CLAUDE_MODEL:-default}" --arg attempt "$NN" --arg text "$text" \
  --argjson usage "$usage" --argjson exit "$rc" --argjson timed_out "$timed_out" \
  '{builder: $builder, model: $model, attempt: $attempt, exit: $exit, timed_out: $timed_out, text: $text, usage: $usage}' |
  fh_write_result "$RUN_DIR" "$NN"

echo "fh[claude] attempt $NN done (exit $rc)" >&2
exit "$rc"
