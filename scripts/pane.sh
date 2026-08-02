#!/usr/bin/env bash
# Builder container control: a Herdr pane when the server is running (watch
# live, take over), a background process otherwise (R8, R10). Either path
# kills the whole builder process group on `down` (R11). The pane is
# display-only — results travel via runs/<run-id>/iterations/NN.json (KTD2).
#
# Usage:
#   pane.sh available
#   pane.sh up <run-id> <worktree>
#   pane.sh dispatch <run-id> -- <cmd...>
#   pane.sh read <run-id>
#   pane.sh down <run-id>
# Env: FH_FORCE_HEADLESS=1 forces the background path even when Herdr runs.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

CMD=${1:-} && shift || true

herdr_up() {
  [ -n "${FH_FORCE_HEADLESS:-}" ] && return 1
  command -v herdr > /dev/null 2>&1 || return 1
  herdr status 2> /dev/null | grep -qE 'status:[[:space:]]*running'
}

ctl_file() { echo "$FH_ROOT/runs/$1/control/pane.json"; }
console() { echo "$FH_ROOT/runs/$1/iterations/console.log"; }

herdr_pane_id() { # <run-id> -> pane id for agent fusion-<run-id>
  herdr agent get "fusion-$1" 2> /dev/null | grep -oE '(pane[_ ]?id|pane)["':' ]+[A-Za-z0-9_-]+' | head -1 | grep -oE '[A-Za-z0-9_-]+$'
}

case "$CMD" in
  available)
    if herdr_up; then echo "pane"; exit 0; else echo "headless"; exit 1; fi
    ;;

  up)
    RUN_ID=${1:?run-id} WT=${2:?worktree}
    CTL=$(ctl_file "$RUN_ID")
    [ -e "$CTL" ] && fh_die "container already up for run $RUN_ID (down it first)"
    mkdir -p "$(dirname "$CTL")" "$(dirname "$(console "$RUN_ID")")"
    if herdr_up; then
      fh_herdr agent start "fusion-$RUN_ID" --cwd "$WT" --no-focus -- bash > /dev/null 2>&1 ||
        fh_die "herdr agent start failed for fusion-$RUN_ID"
      pane_id=$(herdr_pane_id "$RUN_ID" || true)
      jq -n --arg mode pane --arg agent "fusion-$RUN_ID" --arg pane_id "${pane_id:-}" --arg wt "$WT" \
        '{mode: $mode, agent: $agent, pane_id: $pane_id, worktree: $wt}' > "$CTL"
      echo "fh: builder pane up (herdr agent fusion-$RUN_ID)" >&2
    else
      jq -n --arg mode background --arg wt "$WT" '{mode: $mode, worktree: $wt, pids: []}' > "$CTL"
      echo "fh: no Herdr server — headless fallback (R10)" >&2
    fi
    ;;

  dispatch)
    RUN_ID=${1:?run-id}
    shift
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || fh_die "dispatch: no command given"
    CTL=$(ctl_file "$RUN_ID")
    [ -f "$CTL" ] || fh_die "no container for run $RUN_ID (run: pane.sh up)"
    mode=$(jq -r '.mode' "$CTL")
    if [ "$mode" = "pane" ]; then
      pane_id=$(jq -r '.pane_id // empty' "$CTL")
      [ -n "$pane_id" ] || pane_id=$(herdr_pane_id "$RUN_ID") || fh_die "cannot resolve pane id for fusion-$RUN_ID"
      # The pane shell's cwd is the worktree; SKILL.md dispatches repo-root-
      # relative paths, so anchor the command at FH_ROOT explicitly.
      cmd_str=$(printf '%q ' "$@")
      fh_herdr pane run "$pane_id" "cd $(printf '%q' "$FH_ROOT") && $cmd_str" > /dev/null 2>&1 || fh_die "herdr pane run failed"
    else
      nohup "$@" >> "$(console "$RUN_ID")" 2>&1 &
      pid=$!
      fh_jq_inplace "$CTL" '.pids += [$pid]' --argjson pid "$pid"
    fi
    echo "fh: dispatched builder turn for run $RUN_ID ($mode)" >&2
    ;;

  read)
    RUN_ID=${1:?run-id}
    CTL=$(ctl_file "$RUN_ID")
    [ -f "$CTL" ] || fh_die "no container for run $RUN_ID"
    if [ "$(jq -r '.mode' "$CTL")" = "pane" ]; then
      herdr agent read "fusion-$RUN_ID" --lines 40 2> /dev/null || true
    else
      [ -f "$(console "$RUN_ID")" ] && tail -40 "$(console "$RUN_ID")" || true
    fi
    ;;

  down)
    RUN_ID=${1:?run-id}
    CTL=$(ctl_file "$RUN_ID")
    [ -f "$CTL" ] || fh_die "no container for run $RUN_ID"
    if [ "$(jq -r '.mode' "$CTL")" = "pane" ]; then
      pane_id=$(jq -r '.pane_id // empty' "$CTL")
      [ -n "$pane_id" ] || pane_id=$(herdr_pane_id "$RUN_ID" || true)
      if [ -z "$pane_id" ]; then
        echo "fh: cannot resolve pane id for fusion-$RUN_ID — the pane may still be open; control file kept so down can be retried" >&2
        exit 1
      fi
      if ! fh_herdr pane close "$pane_id" > /dev/null 2>&1; then
        echo "fh: herdr pane close failed for pane $pane_id — control file kept so down can be retried" >&2
        exit 1
      fi
    else
      while IFS= read -r pid; do
        [ -n "$pid" ] && fh_kill_tree "$pid" TERM
      done < <(jq -r '.pids[]?' "$CTL")
      sleep 1
      while IFS= read -r pid; do
        [ -n "$pid" ] && fh_kill_tree "$pid" KILL
      done < <(jq -r '.pids[]?' "$CTL")
    fi
    rm -f "$CTL"
    echo "fh: builder container down for run $RUN_ID (worktree kept)" >&2
    ;;

  *)
    fh_die "usage: pane.sh available | up <run-id> <worktree> | dispatch <run-id> -- <cmd...> | read <run-id> | down <run-id>"
    ;;
esac
