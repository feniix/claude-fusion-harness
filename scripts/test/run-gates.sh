#!/usr/bin/env bash
# Tests for the gate runner. No model calls — pure local fixtures.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PASS=0 FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "ok   - $1"; else FAIL=$((FAIL + 1)); echo "FAIL - $1"; fi; }

RUN_DIR="$(mktemp -d)"
WT="$(mktemp -d)"
trap 'rm -rf "$RUN_DIR" "$WT"' EXIT
mkdir -p "$RUN_DIR/gates"

# Fixtures: pass, fail-with-output, ordering probe
cat > "$RUN_DIR/gates/01-pass.sh" << 'EOF'
#!/usr/bin/env bash
echo "gate one fine"; exit 0
EOF
cat > "$RUN_DIR/gates/02-fail.sh" << 'EOF'
#!/usr/bin/env bash
echo "expected zig, got zag" >&2; exit 3
EOF
cat > "$RUN_DIR/gates/03-order.sh" << 'EOF'
#!/usr/bin/env bash
echo "third"; exit 0
EOF
chmod +x "$RUN_DIR/gates/"*.sh

out="$("$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" 2> /dev/null)"
rc=$?
nonzero=0; [ "$rc" -ne 0 ] || nonzero=1
check "failing gate makes overall exit non-zero" "$nonzero"
echo "$out" | jq -e 'length == 3' > /dev/null
check "JSON array has one result per gate" $?
echo "$out" | jq -e '.[0].gate == "01-pass.sh" and .[1].gate == "02-fail.sh" and .[2].gate == "03-order.sh"' > /dev/null
check "gates run in filename order" $?
echo "$out" | jq -e '.[0].pass == true and .[1].pass == false and .[1].exit == 3' > /dev/null
check "pass/fail and exit codes recorded" $?
echo "$out" | jq -e '.[1].output | contains("zig")' > /dev/null
check "failing gate output tail captured" $?

# All pass
rm "$RUN_DIR/gates/02-fail.sh"
"$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" > /dev/null 2>&1
check "all gates passing exits 0" $?

# Gates run with cwd = worktree
cat > "$RUN_DIR/gates/04-cwd.sh" << EOF
#!/usr/bin/env bash
[ "\$(pwd -P)" = "\$(cd '$WT' && pwd -P)" ]
EOF
chmod +x "$RUN_DIR/gates/04-cwd.sh"
"$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" > /dev/null 2>&1
check "gates execute with cwd = worktree" $?
rm "$RUN_DIR/gates/04-cwd.sh"

# Non-executable gate reported as error, not skipped
cat > "$RUN_DIR/gates/05-noexec.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
out="$("$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" 2> /dev/null)"
rc=$?
[ "$rc" -ne 0 ] && echo "$out" | jq -e '[.[] | select(.gate == "05-noexec.sh")] | .[0].pass == false and (.[0].output | contains("not executable"))' > /dev/null
check "non-executable gate reported as gate error" $?
rm "$RUN_DIR/gates/05-noexec.sh"

# Timeout: hanging gate killed and marked
cat > "$RUN_DIR/gates/06-hang.sh" << 'EOF'
#!/usr/bin/env bash
sleep 600
EOF
chmod +x "$RUN_DIR/gates/06-hang.sh"
out="$(FH_GATE_TIMEOUT=2 "$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" 2> /dev/null)"
rc=$?
[ "$rc" -ne 0 ] && echo "$out" | jq -e '[.[] | select(.gate == "06-hang.sh")] | .[0].pass == false and .[0].timed_out == true' > /dev/null
check "hanging gate killed and marked timed_out" $?
rm "$RUN_DIR/gates/06-hang.sh"

# Empty gates dir is a distinct error (a run with no gates is invalid, R4)
rm "$RUN_DIR/gates/"*.sh
"$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" > /dev/null 2>&1
[ $? -eq 2 ]
check "empty gates dir exits 2" $?

echo
echo "run-gates: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
