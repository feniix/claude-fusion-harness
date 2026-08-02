#!/usr/bin/env bash
# Gate runner: execute a run's acceptance gates in the worktree and emit
# structured results. Gates are executable files with exit-code semantics
# (exit 0 = pass) — the loop's definition of done.
#
# Usage: run-gates.sh <run-dir> <worktree>
# Output: JSON results array on stdout [{gate, pass, exit, timed_out, duration_secs, output}]
#         human summary on stderr.
# Exit:   0 all gates pass, 1 any gate fails, 2 no gates found.
# Env:    FH_GATE_TIMEOUT secs per gate (default 300)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -eq 2 ] || fh_die "usage: run-gates.sh <run-dir> <worktree>"
RUN_DIR=$1 WT=$2
[ -d "$RUN_DIR" ] || fh_die "run dir missing: $RUN_DIR"
[ -d "$WT" ] || fh_die "worktree missing: $WT"
# Resolve before any cd: callers may pass repo-relative paths.
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
WT="$(cd "$WT" && pwd)"
GATES_DIR="$RUN_DIR/gates"
GATE_TIMEOUT="${FH_GATE_TIMEOUT:-300}"
TAIL_LINES=50

[ -d "$GATES_DIR" ] || { echo "fh: no gates directory at $GATES_DIR" >&2; exit 2; }

gates=()
while IFS= read -r g; do gates+=("$g"); done < <(find "$GATES_DIR" -maxdepth 1 -name '*.sh' | sort)
[ "${#gates[@]}" -gt 0 ] || { echo "fh: no gates in $GATES_DIR — a run with no gates is invalid" >&2; exit 2; }

results='[]'
overall=0
for gate in "${gates[@]}"; do
  name=$(basename "$gate")
  outfile=$(mktemp)
  marker=$(mktemp -u)
  start=$SECONDS
  if [ ! -x "$gate" ]; then
    rc=126
    echo "gate file is not executable" > "$outfile"
  else
    rc=0
    fh_timeout "$GATE_TIMEOUT" "$marker" bash -c 'cd "$1" && exec "$2"' _ "$WT" "$gate" > "$outfile" 2>&1 || rc=$?
  fi
  duration=$((SECONDS - start))
  timed_out=false
  [ "$rc" -eq 124 ] && timed_out=true
  pass=false
  [ "$rc" -eq 0 ] && pass=true
  [ "$rc" -ne 0 ] && overall=1

  output=$(tail -n "$TAIL_LINES" "$outfile")
  results=$(jq -c --arg gate "$name" --argjson pass "$pass" --argjson exit "$rc" \
    --argjson timed_out "$timed_out" --argjson duration "$duration" --arg output "$output" \
    '. + [{gate: $gate, pass: $pass, exit: $exit, timed_out: $timed_out, duration_secs: $duration, output: $output}]' <<< "$results")
  printf 'fh[gate] %-30s %s (exit %d, %ds)\n' "$name" "$([ "$pass" = true ] && echo PASS || echo FAIL)" "$rc" "$duration" >&2
  rm -f "$outfile" "$marker"
done

echo "$results" | jq .
exit "$overall"
