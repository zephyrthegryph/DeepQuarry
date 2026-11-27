#!/usr/bin/env bash
# Edit-sequence check of the native compiler's incremental output against a cold compile, on the real tree.
#
#   bash tools/dmb/scripts/incremental_equiv_sequence.sh <dmbc.exe> <out dir> [dme] [steps...]
#
# A private daemon (its own DMB_DAEMON_NAMESPACE and DMB_CACHE_DIR under <out dir>) compiles the tree once, then each step
# edits the tree, compiles it on the daemon (the incremental path: a body patch, code motion, or the whole-program path
# for a declaration edit) and compares the output with a one-shot cold compile of the same source (`--no-daemon
# --no-cache`, a fresh cache dir) by sha256 and with dmb-equiv (default options: the class table, named procedures and
# variable-name strings in fresh order; and `--strict-order`). Steps (default all, in this order):
#   body         one string literal in code/engine/actions/admission_query.dm changed (a body patch appends the literal)
#   body-revert  that literal back
#   shift        a blank line inserted above the first proc of that file (code motion), and reverted (shift-revert)
#   var          `var/parity_probe = 0` added to /datum/act/input (code/engine/lifeforms/input.dm), between declared vars
#   var-revert   that var removed again (a removed var)
#   proc         `/datum/act/input/proc/parity_probe_proc()` added above the next proc of that file
#   proc-revert  that proc removed again (a removed proc)
# Exit status 1 when any step is not EQUIVALENT (default options) to its cold compile; each step's line says whether
# the bytes are identical. Cold compiles of a source state already compiled are reused (the reverts share the base's).
# Needs a dmb-equiv binary (DMB_EQUIV, default the dq_cargo_target.sh dmb-equiv release build) and the generated files
# (`tools/build/build.sh gen`). It restores both edited files from HEAD when it exits, and retires its daemon.
# Writes <out dir>/summary.txt. Takes about 3 min per cold compile on a loaded machine: run it in the background.
set -u
DMBC="${1:?usage: incremental_equiv_sequence.sh <dmbc.exe> <out dir> [dme] [steps...]}"
OUT="${2:?out dir}"
DME="${3:-deepquarry.dme}"
shift 2; [ $# -gt 0 ] && shift
STEPS=("$@")
[ ${#STEPS[@]} -eq 0 ] && STEPS=(body body-revert shift shift-revert var var-revert proc proc-revert)
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
EQUIV="${DMB_EQUIV:-$(bash tools/dq_cargo_target.sh dmb-equiv)/release/dmb-equiv.exe}"
[ -x "$EQUIV" ] || EQUIV="${EQUIV%.exe}"
[ -x "$EQUIV" ] || { echo "no dmb-equiv at $EQUIV (cargo build --release -p dmb-equiv)" >&2; exit 2; }
WORKERS="${DQ_EQUIV_WORKERS:-8}"
NS="equivseq-$(basename "$ROOT")-$$"
export DMB_DAEMON_AUTOSTART=1 DMB_DAEMON_NAMESPACE="$NS" DMB_CACHE_DIR="$OUT/cache-daemon"
unset DQ_NATIVE_NO_DAEMON
STEM="${DME%.dme}"
F_BODY=code/engine/actions/admission_query.dm
F_DECL=code/engine/lifeforms/input.dm
restore() { git show "HEAD:$F_BODY" > "$F_BODY"; git show "HEAD:$F_DECL" > "$F_DECL"; }
finish() { restore; "$DMBC" --daemon-retire >> "$OUT/retire.log" 2>&1; }
trap finish EXIT
status=0
log() { echo "$*" | tee -a "$OUT/summary.txt" >&2; }
compile() { # name [extra args]
  local name=$1; shift
  rm -f "$STEM.dmb" "$STEM.rsc"
  local start=$SECONDS
  bash tools/dq_machine_slots.sh run dm_compile --label "equivseq $name" -- \
    "$DMBC" compile "$DME" --workers "$WORKERS" "$@" > "$OUT/$name.log" 2>&1
  local rc=$?
  [ $rc -eq 0 ] || { log "$name: compile failed (rc=$rc, $OUT/$name.log)"; exit 1; }
  cp "$STEM.dmb" "$OUT/$name.dmb"; cp "$STEM.rsc" "$OUT/$name.rsc"
  log "$(printf '%-18s %4ss %10s %s' "$name" $((SECONDS - start)) "$(stat -c %s "$OUT/$name.dmb")" "$(sha256sum "$OUT/$name.dmb" | cut -c1-16)")"
}
state_key() { cat "$F_BODY" "$F_DECL" | sha256sum | cut -c1-16; }
cold_for_state() { # sets COLD to the name of the cold output of the current source state
  COLD="cold-$(state_key)"
  if [ ! -f "$OUT/$COLD.dmb" ]; then
    DMB_CACHE_DIR="$OUT/cache-cold" compile "$COLD" --no-daemon --no-cache
    rm -rf "$OUT/cache-cold"
  fi
}
compare() { # daemon-name cold-name
  local d=$1 c=$2 verdict strict same=identical
  cmp -s "$OUT/$d.dmb" "$OUT/$c.dmb" && cmp -s "$OUT/$d.rsc" "$OUT/$c.rsc" || same="bytes differ"
  "$EQUIV" "$OUT/$d.dmb" "$OUT/$c.dmb" --rsc "$OUT/$d.rsc" "$OUT/$c.rsc" --all --context 2 > "$OUT/equiv-$d.txt" 2>&1
  verdict=$([ $? -eq 0 ] && echo EQUIVALENT || echo "NOT EQUIVALENT")
  "$EQUIV" "$OUT/$d.dmb" "$OUT/$c.dmb" --rsc "$OUT/$d.rsc" "$OUT/$c.rsc" --all --strict-order --context 2 > "$OUT/equiv-strict-$d.txt" 2>&1
  strict=$([ $? -eq 0 ] && echo EQUIVALENT || echo "NOT EQUIVALENT")
  [ "$verdict" = EQUIVALENT ] || status=1
  log "$(printf '%-18s vs cold: %s, %s (strict order: %s)' "$d" "$same" "$verdict" "$strict")"
}
edit() {
  case "$1" in
    body) sed -i 's/query options must be a named scalar map"/query options must be a named scalar map!"/' "$F_BODY" ;;
    body-revert) sed -i 's/query options must be a named scalar map!"/query options must be a named scalar map"/' "$F_BODY" ;;
    shift) sed -i '0,/^\/proc\//s//\n&/' "$F_BODY" ;;
    shift-revert) git show "HEAD:$F_BODY" > "$F_BODY" ;;
    var) sed -i 's/^\tvar\/params$/\tvar\/params\n\t\/\/\/ Edit-sequence probe.\n\tvar\/parity_probe = 0/' "$F_DECL" ;;
    var-revert) git show "HEAD:$F_DECL" > "$F_DECL" ;;
    proc) sed -i '0,/^\/\/\/ The lifeform plan of /s//\/datum\/act\/input\/proc\/parity_probe_proc()\n\treturn 41\n\n&/' "$F_DECL" ;;
    proc-revert) git show "HEAD:$F_DECL" > "$F_DECL" ;;
    *) echo "unknown step $1" >&2; exit 2 ;;
  esac
}
restore
log "== $DME, $(git rev-parse --short HEAD), compiler $DMBC"
compile d-base
cold_for_state
compare d-base "$COLD"
for step in "${STEPS[@]}"; do
  before=$(state_key)
  edit "$step"
  [ "$(state_key)" != "$before" ] || { log "$step: the edit changed nothing"; exit 1; }
  compile "d-$step"
  cold_for_state
  compare "d-$step" "$COLD"
done
log "$([ $status -eq 0 ] && echo "ALL EQUIVALENT" || echo "SOME STEP NOT EQUIVALENT")"
exit $status
