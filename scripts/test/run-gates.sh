#!/usr/bin/env bash
# Tests for the gate runner. No model calls — pure local fixtures.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/harness.sh"

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
check_nonzero "failing gate makes overall exit non-zero" $?
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
{ [ "$rc" -ne 0 ] && echo "$out" | jq -e '[.[] | select(.gate == "05-noexec.sh")] | .[0].pass == false and (.[0].output | contains("not executable"))' > /dev/null; }
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

# Relative paths must resolve (regression: gate exec after cd into worktree)
cat > "$RUN_DIR/gates/07-rel.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$RUN_DIR/gates/07-rel.sh"
BASE="$(mktemp -d)"
ln -s "$RUN_DIR" "$BASE/rel-run"
ln -s "$WT" "$BASE/rel-wt"
(cd "$BASE" && "$ROOT/scripts/run-gates.sh" rel-run rel-wt > /dev/null 2>&1)
check "relative run-dir/worktree paths resolve" $?
rm "$RUN_DIR/gates/07-rel.sh"
rm -rf "$BASE"

# Empty gates dir is a distinct error (a run with no gates is invalid, R4)
rm "$RUN_DIR/gates/"*.sh
"$ROOT/scripts/run-gates.sh" "$RUN_DIR" "$WT" > /dev/null 2>&1
rc=$?
rcv=0; [ "$rc" -eq 2 ] || rcv=1
check "empty gates dir exits 2" "$rcv"

finish "run-gates"
