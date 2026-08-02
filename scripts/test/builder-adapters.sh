#!/usr/bin/env bash
# Smoke tests for the builder adapters. Spends a few subscription tokens:
# uses cheap models (gpt-5.6-terra / haiku) and trivial prompts per the
# Verification Contract.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/harness.sh"

RUN_ID="test-adapters-$$"
RUN_DIR="$ROOT/runs/$RUN_ID"
WT="$(mktemp -d)"
mkdir -p "$RUN_DIR/iterations"
trap 'rm -rf "$RUN_DIR" "$WT"' EXIT

prompt="$RUN_DIR/prompt1.md"
echo "Reply with exactly: ADAPTER-OK" > "$prompt"
prompt2="$RUN_DIR/prompt2.md"
echo "What exact phrase did I ask you to reply with in my previous message? Reply with just that phrase, nothing else." > "$prompt2"

# --- GPT adapter ---------------------------------------------------------
export FH_GPT_MODEL="${FH_GPT_MODEL:-gpt-5.6-terra}"

# Regression guard: call with repo-RELATIVE prompt/worktree paths — the adapter
# must resolve them before cd'ing into the worktree.
REL_WT="runs/$RUN_ID/wt-rel"
mkdir -p "$ROOT/$REL_WT"
cp "$prompt" "$ROOT/runs/$RUN_ID/prompt-rel.md"
(cd "$ROOT" && scripts/builder-gpt.sh "$REL_WT" "runs/$RUN_ID/prompt-rel.md" "$RUN_ID")
check "gpt: relative paths resolve (exit 0)" $?
jq -e '.text | contains("ADAPTER-OK")' "$RUN_DIR/iterations/01.json" > /dev/null
check "gpt: relative-path call produced real prompt text" $?

"$ROOT/scripts/builder-gpt.sh" "$WT" "$prompt" "$RUN_ID"
check "gpt: happy-path exit 0" $?
out="$RUN_DIR/iterations/02.json"
[ -f "$out" ] && jq -e '.text | contains("ADAPTER-OK")' "$out" > /dev/null
check "gpt: result file has ADAPTER-OK text" $?
jq -e '.usage.total > 0' "$out" > /dev/null
check "gpt: usage recorded" $?

"$ROOT/scripts/builder-gpt.sh" "$WT" "$prompt2" "$RUN_ID"
jq -e '.text | contains("ADAPTER-OK")' "$RUN_DIR/iterations/03.json" > /dev/null
check "gpt: session persists across attempts" $?

FH_GPT_MODEL="no-such-model-xyz" "$ROOT/scripts/builder-gpt.sh" "$WT" "$prompt" "$RUN_ID" 2> /dev/null
rc=$?
[ "$rc" -ne 0 ] && jq -e '.exit != 0' "$RUN_DIR/iterations/04.json" > /dev/null
check "gpt: bad model yields non-zero exit and JSON error result" $?

FH_TURN_TIMEOUT=1 "$ROOT/scripts/builder-gpt.sh" "$WT" "$prompt" "$RUN_ID" 2> /dev/null
rc=$?
[ "$rc" -eq 124 ] && jq -e '.timed_out == true' "$RUN_DIR/iterations/05.json" > /dev/null
check "gpt: turn timeout kills and marks timed_out" $?

# --- Claude adapter ------------------------------------------------------
export FH_CLAUDE_MODEL="${FH_CLAUDE_MODEL:-haiku}"

# Production always has state.json before the first turn (run-init creates
# it), so pre-seed it here to exercise the fh_jq_inplace merge branch.
echo '{"run_id":"'"$RUN_ID"'"}' > "$RUN_DIR/state.json"

"$ROOT/scripts/builder-claude.sh" "$WT" "$prompt" "$RUN_ID"
check "claude: happy-path exit 0" $?
out="$RUN_DIR/iterations/06.json"
[ -f "$out" ] && jq -e '.text | contains("ADAPTER-OK")' "$out" > /dev/null
check "claude: result file has ADAPTER-OK text" $?
jq -e --arg rid "$RUN_ID" '(.claude_session_id | length > 0) and .run_id == $rid' "$RUN_DIR/state.json" > /dev/null
check "claude: session uuid merged into existing state.json" $?

"$ROOT/scripts/builder-claude.sh" "$WT" "$prompt2" "$RUN_ID"
jq -e '.text | contains("ADAPTER-OK")' "$RUN_DIR/iterations/07.json" > /dev/null
check "claude: session resumes across attempts" $?

finish "builder-adapters"
