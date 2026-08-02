#!/usr/bin/env bash
# Tests for pane.sh in headless-fallback mode (no Herdr server assumed —
# the pane-mode path is exercised in the U7 e2e when a server is running).
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/harness.sh"

RUN_ID="test-pane-$$"
RUN_DIR="$ROOT/runs/$RUN_ID"
WT="$(mktemp -d)"
mkdir -p "$RUN_DIR/iterations" "$RUN_DIR/control"
trap 'rm -rf "$RUN_DIR" "$WT"' EXIT

P="$ROOT/scripts/pane.sh"

# Force fallback regardless of any running server so the test is deterministic.
export FH_FORCE_HEADLESS=1

"$P" available > /dev/null 2>&1
check_nonzero "available reports headless under FH_FORCE_HEADLESS" $?

"$P" up "$RUN_ID" "$WT" > /dev/null 2>&1
check "up succeeds in fallback mode" $?
jq -e '.mode == "background"' "$RUN_DIR/control/pane.json" > /dev/null 2>&1
check "up records background mode" $?

"$P" up "$RUN_ID" "$WT" > /dev/null 2>&1
check_nonzero "second up for same run-id refuses" $?

# Dispatch a slow command, verify it's observable, then kill it via down.
"$P" dispatch "$RUN_ID" -- bash -c 'echo dispatch-started; sleep 300; echo never' > /dev/null 2>&1
check "dispatch starts a background command" $?
sleep 1
"$P" read "$RUN_ID" 2> /dev/null | grep -q "dispatch-started"
check "read tails the console log" $?

"$P" down "$RUN_ID" > /dev/null 2>&1
check "down exits 0" $?
sleep 1
if pgrep -f "sleep 300" > /dev/null 2>&1; then survivors=1; else survivors=0; fi
check "down leaves no surviving builder process (AE5)" "$survivors"
rcv=0; [ -d "$WT" ] || rcv=1
check "worktree dir intact after down" "$rcv"

# Completion detection contract: dispatch writes results; poller sees file appear.
"$P" up "$RUN_ID" "$WT" > /dev/null 2>&1
check "up allowed again after down" $?
"$P" dispatch "$RUN_ID" -- bash -c "echo '{\"ok\":true}' > '$RUN_DIR/iterations/01.json'" > /dev/null 2>&1
for _ in 1 2 3 4 5; do [ -f "$RUN_DIR/iterations/01.json" ] && break; sleep 1; done
rcv=0; [ -f "$RUN_DIR/iterations/01.json" ] || rcv=1
check "dispatched command's result file appears (completion signal)" "$rcv"
"$P" down "$RUN_ID" > /dev/null 2>&1

finish "pane"
