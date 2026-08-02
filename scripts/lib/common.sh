#!/usr/bin/env bash
# Shared helpers for fusion-harness scripts. Source, don't execute.

FH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export FH_ROOT

# Shared empty-usage shape for the iteration-result schema.
# shellcheck disable=SC2034  # consumed by sourcing scripts
FH_ZERO_USAGE='{"input":0,"output":0,"total":0,"cost":0}'

fh_die() {
  echo "fh: $*" >&2
  exit 1
}

fh_abspath() { (cd "$1" && pwd); }

# Next attempt number (zero-padded) for a run, derived from existing result files.
fh_next_attempt() { # <run-dir>
  local n=1
  while [ -e "$1/iterations/$(printf '%02d' "$n").json" ]; do n=$((n + 1)); done
  printf '%02d' "$n"
}

# Signal a process and all its descendants (depth-first), reaching
# grandchildren that a plain `pkill -P` one-generation walk would miss.
fh_kill_tree() { # <pid> <signal>
  local child
  for child in $(pgrep -P "$1" 2> /dev/null || true); do
    fh_kill_tree "$child" "$2"
  done
  kill -"$2" "$1" 2> /dev/null || true
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
      fh_kill_tree "$pid" TERM
      sleep 2
      fh_kill_tree "$pid" KILL
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

# Atomic in-place jq edit: fh_jq_inplace <file> <filter> [jq-args...]
fh_jq_inplace() {
  local file=$1 filter=$2
  shift 2
  local tmp
  tmp=$(mktemp)
  jq "$@" "$filter" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Common builder-adapter preamble: validates args, resolves paths before any
# cd (callers may pass repo-relative paths), and sets the globals
# WT, RUN_ID, RUN_DIR, PROMPT_TEXT, TURN_TIMEOUT, NN, MARKER.
# shellcheck disable=SC2034  # globals consumed by the sourcing adapter
fh_builder_setup() { # <adapter-name> <worktree> <prompt-file> <run-id>
  local name=$1
  [ $# -eq 4 ] || fh_die "usage: $name <worktree> <prompt-file> <run-id>"
  WT=$2 RUN_ID=$4
  local prompt=$3
  RUN_DIR="$FH_ROOT/runs/$RUN_ID"
  [ -d "$RUN_DIR/iterations" ] || fh_die "run dir missing: $RUN_DIR/iterations"
  [ -f "$prompt" ] || fh_die "prompt file missing: $prompt"
  [ -d "$WT" ] || fh_die "worktree missing: $WT"
  WT=$(fh_abspath "$WT")
  PROMPT_TEXT="$(cat "$prompt")"
  TURN_TIMEOUT="${FH_TURN_TIMEOUT:-1800}"
  NN=$(fh_next_attempt "$RUN_DIR")
  MARKER="$RUN_DIR/iterations/$NN.timeout"
}

# Atomically write a builder result file: stdin JSON -> <run-dir>/iterations/<NN>.json
fh_write_result() { # <run-dir> <NN>
  local tmp="$1/iterations/$2.json.tmp"
  cat > "$tmp"
  mv "$tmp" "$1/iterations/$2.json"
}

# A silent turn (exit 0 but no final text) is an error, not a pass.
fh_effective_rc() { # <rc> <text>
  if [ "$1" -eq 0 ] && [ -z "$2" ]; then echo 1; else echo "$1"; fi
}

# Assemble and atomically write the shared iteration-result schema; computes
# timed_out from the exit code (124 = fh_timeout expiry). Owning this shape
# here keeps the two adapters from drifting apart. Builds the JSON fully
# before publishing so a malformed input can never leave a truncated
# iterations/NN.json behind (the file's appearance is the completion signal).
fh_emit_result() { # <run-dir> <NN> <builder> <model> <text> <usage-json> <exit-code>
  local timed_out=false
  [ "$7" -eq 124 ] && timed_out=true
  local usage_json=$6
  [ -n "$usage_json" ] || usage_json=$FH_ZERO_USAGE
  local json
  json=$(jq -n --arg builder "$3" --arg model "$4" --arg attempt "$2" --arg text "$5" \
    --argjson usage "$usage_json" --argjson exit "$7" --argjson timed_out "$timed_out" \
    '{builder: $builder, model: $model, attempt: $attempt, exit: $exit, timed_out: $timed_out, text: $text, usage: $usage}') ||
    fh_die "fh_emit_result: failed to assemble result JSON for attempt $2"
  printf '%s\n' "$json" | fh_write_result "$1" "$2"
}

# Herdr CLI wrapper: every herdr call gets a bounded budget so a wedged
# server cannot hang the loop.
fh_herdr() {
  local m
  m=$(mktemp -u)
  fh_timeout "${FH_HERDR_TIMEOUT:-30}" "$m" herdr "$@"
}
