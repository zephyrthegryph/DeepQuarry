#!/usr/bin/env bash
# Interleaved A/B: each edit state is asked of daemon A then daemon B (same machine load, same edit sequence).
# usage: bash tools/dmb/scripts/frontend_edit_pair.sh <dmbcA> <nsA> <dmbcB> <nsB> <out dir> [rounds]
# Copy the binaries out of a cargo target first (cargo cannot replace a running daemon), give each its own namespace, and
# retire both daemons afterwards (dmbc --daemon-retire with the namespace). ENV_A / ENV_B: extra env for the daemon each starts.
# Prints the hosted front end time (`front end`) and the phase sum (`total=`) of every request; edits code/engine/actions/admission_query.dm
# and restores it from HEAD.
set -u
A="$1"; NA="$2"; B="$3"; NB="$4"; OUT="$5"; ROUNDS="${6:-4}"
cd "$(git rev-parse --show-toplevel)"
export DQ_ANALYZE_PARSE=dmbc DMB_DAEMON_AUTOSTART=1 DQ_ANALYZE_DAEMON_TRACE=1 DQ_FRONTEND_TRACE=1 DQ_ANALYZE_MODEL_MEMO=0 \
  DQ_ANALYZE_SHARED_CACHE=off
F=code/engine/actions/admission_query.dm
mkdir -p "$OUT"
git show HEAD:$F > "$OUT/orig.dm"
one() { # binary ns label [env assignments for the daemon this starts]
  env ${4:-} DMB_DAEMON_NAMESPACE="$2" DQ_ANALYZE_CACHE="$(pwd)/data/meas/cache-$2" \
    "$1" analyze dreamchecker --json ${DQ_MEAS_ARGS:---parse-only} > "$OUT/$3-$2.json" 2> "$OUT/$3-$2.err"
  printf '%-14s %-16s %s | %s\n' "$3" "$2" "$(grep -ao 'front end [0-9.]*s' "$OUT/$3-$2.err" | head -1)" \
    "$(grep -ao 'total=[0-9.]*s' "$OUT/$3-$2.err" | tail -1)"
}
req() { one "$A" "$NA" "$1" "${ENV_A:-}"; one "$B" "$NB" "$1" "${ENV_B:-}"; }
req base
req noop
for i in $(seq 1 "$ROUNDS"); do
  sed -i 's/query options must be a named scalar map/query options must be a named scalar map!/' "$F"
  req body$i
  cp "$OUT/orig.dm" "$F"
  req revert$i
done
for i in $(seq 1 "$ROUNDS"); do
  sed -i '9i\
' "$F"
  req shift$i
  cp "$OUT/orig.dm" "$F"
  req shiftrevert$i
done
req noop2
cp "$OUT/orig.dm" "$F"
echo DONE
