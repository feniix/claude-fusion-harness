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

fh_builder_setup "builder-gpt.sh" "$@"
MODEL="${FH_GPT_MODEL:-gpt-5.6-sol}"
RAW="$RUN_DIR/iterations/$NN.events.jsonl"
SESSION_DIR="$RUN_DIR/pi-session"
mkdir -p "$SESSION_DIR"

# Continue the run's session when one exists (context of prior attempts).
CONT=()
if compgen -G "$SESSION_DIR/*.jsonl" > /dev/null; then CONT=(--continue); fi

run_pi() {
  cd "$WT" && exec pi --provider openai-codex --model "$MODEL" --mode json -p \
    --session-dir "$SESSION_DIR" ${CONT[@]+"${CONT[@]}"} \
    --no-extensions --no-skills --no-context-files "$PROMPT_TEXT"
}

echo "fh[gpt/$MODEL] attempt $NN starting" >&2
rc=0
fh_timeout "$TURN_TIMEOUT" "$MARKER" run_pi > "$RAW" 2> "$RUN_DIR/iterations/$NN.stderr" || rc=$?

text=$(jq -rs '[.[] | select(.type == "agent_end")] | last | (.messages // []) | last | (.content // []) | map(select(.type == "text") | .text) | join("\n")' "$RAW" 2> /dev/null || echo "")
usage=$(jq -cs '[.[] | select(.type == "message_end")] | map(.message.usage // empty) | {input: (map(.input) | add // 0), output: (map(.output) | add // 0), total: (map(.totalTokens) | add // 0), cost: (map(.cost.total) | add // 0)}' "$RAW" 2> /dev/null || echo "$FH_ZERO_USAGE")

rc=$(fh_effective_rc "$rc" "$text")
fh_emit_result "$RUN_DIR" "$NN" gpt "$MODEL" "$text" "$usage" "$rc"
echo "fh[gpt/$MODEL] attempt $NN done (exit $rc)" >&2
exit "$rc"
