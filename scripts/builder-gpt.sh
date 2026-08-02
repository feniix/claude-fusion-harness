#!/usr/bin/env bash
# GPT builder adapter: one headless turn of pi on the openai-codex
# (subscription) provider, clean-room, run-scoped session.
#
# Usage: builder-gpt.sh <worktree> <prompt-file> <run-id>
# Result: writes runs/<run-id>/iterations/<NN>.json (authoritative channel);
#         stdout/pane output is human-facing only. Exit 0 on success, 124 on
#         turn timeout, non-zero otherwise.
# Env:    FH_GPT_MODEL (default gpt-5.6-sol), FH_TURN_TIMEOUT secs (default 1800)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -eq 3 ] || fh_die "usage: builder-gpt.sh <worktree> <prompt-file> <run-id>"
WT=$1 PROMPT=$2 RUN_ID=$3
RUN_DIR="$FH_ROOT/runs/$RUN_ID"
[ -d "$RUN_DIR/iterations" ] || fh_die "run dir missing: $RUN_DIR/iterations"
[ -f "$PROMPT" ] || fh_die "prompt file missing: $PROMPT"

MODEL="${FH_GPT_MODEL:-gpt-5.6-sol}"
TURN_TIMEOUT="${FH_TURN_TIMEOUT:-1800}"
NN=$(fh_next_attempt "$RUN_DIR")
RAW="$RUN_DIR/iterations/$NN.events.jsonl"
MARKER="$RUN_DIR/iterations/$NN.timeout"
SESSION_DIR="$RUN_DIR/pi-session"
mkdir -p "$SESSION_DIR"

# Continue the run's session when one exists (context of prior attempts).
CONT=()
if compgen -G "$SESSION_DIR/*.jsonl" > /dev/null; then CONT=(--continue); fi

echo "fh[gpt/$MODEL] attempt $NN starting" >&2
rc=0
fh_timeout "$TURN_TIMEOUT" "$MARKER" bash -c '
  cd "$1" && exec pi --provider openai-codex --model "$2" --mode json -p \
    --session-dir "$3" "${@:5}" \
    --no-extensions --no-skills --no-context-files "$(cat "$4")"
' _ "$WT" "$MODEL" "$SESSION_DIR" "$PROMPT" "${CONT[@]:-}" > "$RAW" 2> "$RUN_DIR/iterations/$NN.stderr" || rc=$?

timed_out=false
[ "$rc" -eq 124 ] && timed_out=true

text=$(jq -rs '[.[] | select(.type == "agent_end")] | last | (.messages // []) | last | (.content // []) | map(select(.type == "text") | .text) | join("\n")' "$RAW" 2> /dev/null || echo "")
usage=$(jq -cs '[.[] | select(.type == "message_end")] | map(.message.usage // empty) | {input: (map(.input) | add // 0), output: (map(.output) | add // 0), total: (map(.totalTokens) | add // 0), cost: (map(.cost.total) | add // 0)}' "$RAW" 2> /dev/null || echo '{"input":0,"output":0,"total":0,"cost":0}')

# A silent turn (no final text, no explicit error) is an error, not a pass.
if [ "$rc" -eq 0 ] && [ -z "$text" ]; then rc=1; fi

jq -n --arg builder gpt --arg model "$MODEL" --arg attempt "$NN" --arg text "$text" \
  --argjson usage "$usage" --argjson exit "$rc" --argjson timed_out "$timed_out" \
  '{builder: $builder, model: $model, attempt: $attempt, exit: $exit, timed_out: $timed_out, text: $text, usage: $usage}' |
  fh_write_result "$RUN_DIR" "$NN"

echo "fh[gpt/$MODEL] attempt $NN done (exit $rc)" >&2
exit "$rc"
