#!/usr/bin/env bash
# Shared helpers for fusion-harness scripts. Source, don't execute.

FH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export FH_ROOT

fh_die() {
  echo "fh: $*" >&2
  exit 1
}

# Next attempt number (zero-padded) for a run, derived from existing result files.
fh_next_attempt() { # <run-dir>
  local n=1
  while [ -e "$1/iterations/$(printf '%02d' "$n").json" ]; do n=$((n + 1)); done
  printf '%02d' "$n"
}

# Run a command with a timeout, killing its process tree on expiry.
# Portable across macOS/Linux (no coreutils `timeout` dependency).
# Usage: fh_timeout <secs> <marker-file> cmd [args...]
# Exit: the command's code, or 124 with <marker-file> created on timeout.
fh_timeout() {
  local secs=$1 marker=$2
  shift 2
  "$@" &
  local pid=$!
  (
    local waited=0
    while kill -0 "$pid" 2> /dev/null && [ "$waited" -lt "$secs" ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2> /dev/null; then
      touch "$marker"
      pkill -TERM -P "$pid" 2> /dev/null || true
      kill -TERM "$pid" 2> /dev/null || true
      sleep 2
      pkill -KILL -P "$pid" 2> /dev/null || true
      kill -KILL "$pid" 2> /dev/null || true
    fi
  ) &
  local watcher=$!
  local rc=0
  wait "$pid" || rc=$?
  kill "$watcher" 2> /dev/null || true
  wait "$watcher" 2> /dev/null || true
  [ -e "$marker" ] && return 124
  return "$rc"
}

# Atomically write a builder result file: stdin JSON -> <run-dir>/iterations/<NN>.json
fh_write_result() { # <run-dir> <NN>
  local tmp="$1/iterations/$2.json.tmp"
  cat > "$tmp"
  mv "$tmp" "$1/iterations/$2.json"
}
