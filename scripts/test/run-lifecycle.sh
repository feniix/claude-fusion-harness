#!/usr/bin/env bash
# Tests for run-init/run-finish/log-run. Operates on a scratch clone of this
# repo so the real checkout is never touched.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/harness.sh"

# Copy the working tree (tracked + untracked, minus ignored) into a scratch
# repo so uncommitted script changes are exercised and the real repo is safe.
CLONE="$(mktemp -d)/clone"
mkdir -p "$CLONE"
(cd "$ROOT" && git ls-files -co --exclude-standard | tar -cf - -T -) | (cd "$CLONE" && tar -xf -)
rm -f "$CLONE/runs/log.jsonl" # tests assert absolute line counts from a clean log
git -C "$CLONE" init -q -b main
git -C "$CLONE" config user.email test@example.com
git -C "$CLONE" config user.name test
git -C "$CLONE" add -A
git -C "$CLONE" commit -qm init
trap 'rm -rf "$(dirname "$CLONE")"' EXIT
S="$CLONE/scripts"

# init happy path
"$S/run-init.sh" test-1 gpt 5 "$CLONE/tasks/sample-task/task.md" > /dev/null 2>&1
check "init exits 0" $?
rcv=0; { [ -d "$CLONE/worktrees/test-1" ] && [ "$(git -C "$CLONE/worktrees/test-1" branch --show-current)" = "fusion/test-1" ]; } || rcv=1
check "worktree created on branch fusion/test-1" "$rcv"
rcv=0; [ -z "$(git -C "$CLONE" status --porcelain)" ] || rcv=1
check "main working tree untouched by init" "$rcv"
jq -e '.run_id == "test-1" and .builder == "gpt" and .max_attempts == 5 and .status == "running" and .gate_rewrite_used == false' "$CLONE/runs/test-1/state.json" > /dev/null
check "state.json has run fields" $?
rcv=0; { [ -f "$CLONE/runs/test-1/task.md" ] && [ -d "$CLONE/runs/test-1/gates" ] && [ -d "$CLONE/runs/test-1/control" ]; } || rcv=1
check "run dir skeleton complete" "$rcv"

# collision refusal
"$S/run-init.sh" test-1 gpt 5 > /dev/null 2>&1
check_nonzero "init refuses existing run-id" $?

# finish updates state
"$S/run-finish.sh" test-1 failed > /dev/null 2>&1
jq -e '.status == "failed" and (.ended_at | length > 0)' "$CLONE/runs/test-1/state.json" > /dev/null
check "finish records outcome and end time" $?
rcv=0; [ -d "$CLONE/worktrees/test-1" ] || rcv=1
check "worktree survives finish (kept for inspection)" "$rcv"

# log-run appends a valid record with per-gate outcomes (AE6 record shape)
cat > "$CLONE/runs/test-1/gates-result.json" << 'EOF'
[{"gate":"01-x.sh","pass":true,"exit":0,"timed_out":false,"duration_secs":1,"output":"ok"},
 {"gate":"02-y.sh","pass":false,"exit":1,"timed_out":false,"duration_secs":2,"output":"boom"}]
EOF
echo '{"builder":"gpt","model":"m","attempt":"01","exit":1,"timed_out":false,"text":"t","usage":{"input":10,"output":5,"total":15,"cost":0.01}}' > "$CLONE/runs/test-1/iterations/01.json"
"$S/log-run.sh" test-1 > /dev/null 2>&1
check "log-run exits 0" $?
tail -1 "$CLONE/runs/log.jsonl" | jq -e '.run_id == "test-1" and .outcome == "failed" and .attempts == 1 and (.gates | length == 2) and .gates[1].pass == false and .usage.total == 15' > /dev/null
check "log record carries outcome, per-gate results, usage" $?

# second run appends a second line
"$S/run-init.sh" test-2 claude 3 > /dev/null 2>&1
"$S/run-finish.sh" test-2 passed > /dev/null 2>&1
"$S/log-run.sh" test-2 > /dev/null 2>&1
[ "$(wc -l < "$CLONE/runs/log.jsonl" | tr -d ' ')" = "2" ] && tail -1 "$CLONE/runs/log.jsonl" | jq -e '.run_id == "test-2" and .builder == "claude"' > /dev/null
check "two runs append two JSONL lines" $?

finish "run-lifecycle"
