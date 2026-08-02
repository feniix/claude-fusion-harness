#!/usr/bin/env bash
# Shared test harness for scripts/test/*.sh. Source, don't execute.
# Provides ROOT, PASS/FAIL counters, check, check_nonzero, and finish.

# BASH_SOURCE[1] is the sourcing test file.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
# shellcheck disable=SC2034  # consumed by sourcing test suites
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
PASS=0 FAIL=0

check() { # <name> <exit-code: 0 = pass>
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "ok   - $1"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL - $1"
  fi
}

check_nonzero() { # <name> <exit-code that must be non-zero>
  local rcv=0
  [ "$2" -ne 0 ] || rcv=1
  check "$1" "$rcv"
}

finish() { # <suite-name>
  echo
  echo "$1: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
