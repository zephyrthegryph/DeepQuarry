#!/usr/bin/env bash
# Interleaved A/B: each edit state is asked of daemon A then daemon B (same machine load, same edit sequence).
# usage: bash tools/dmb/scripts/frontend_edit_pair.sh <dmbcA> <nsA> <dmbcB> <nsB> <out dir> [rounds]
# Copy the binaries out of a cargo target first (cargo cannot replace a running daemon), give each its own namespace, and
# retire both daemons afterwards (dmbc --daemon-retire with the namespace). ENV_A / ENV_B: extra env for the daemon each starts.
# B may be "-" to time one daemon alone.
# EDITS chooses the edit kinds, each done `rounds` times and reverted after each (default "body shift"):
#   body   one string changed in code/engine/actions/admission_query.dm
#   shift  a blank line inserted at its line 9 (every later declaration moves)
#   var    `var/parity_probe = 0` added to /datum/act/input (code/engine/lifeforms/input.dm); its revert removes a var
#   proc   `proc/parity_probe_proc()` added to the same type; its revert removes a proc
# Prints the hosted front end time (`front end`) and the phase sum (`total=`) of every request; restores both files from HEAD.
set -u
A="$1"; NA="$2"; B="$3"; NB="$4"; OUT="$5"; ROUNDS="${6:-4}"
cd "$(git rev-parse --show-toplevel)"
export DQ_ANALYZE_PARSE=dmbc DMB_DAEMON_AUTOSTART=1 DQ_ANALYZE_DAEMON_TRACE=1 DQ_FRONTEND_TRACE=1 DQ_ANALYZE_MODEL_MEMO=0 \
  DQ_ANALYZE_SHARED_CACHE=off
F=code/engine/actions/admission_query.dm
G=code/engine/lifeforms/input.dm
mkdir -p "$OUT"
# Both files as git stores them (LF): a checkout may hold CRLF, and `sed -i` here writes LF, so an edit would otherwise touch every line.
git show HEAD:$F > "$OUT/orig.dm"
git show HEAD:$G > "$OUT/orig_input.dm"
cp "$OUT/orig.dm" "$F"; cp "$OUT/orig_input.dm" "$G"
restore() { cp "$OUT/orig.dm" "$F"; cp "$OUT/orig_input.dm" "$G"; }
trap restore EXIT INT TERM
one() { # binary ns label [env assignments for the daemon this starts]
  env ${4:-} DMB_DAEMON_NAMESPACE="$2" DQ_ANALYZE_CACHE="$(pwd)/data/meas/cache-$2" \
    "$1" analyze dreamchecker --json ${DQ_MEAS_ARGS:---parse-only} > "$OUT/$3-$2.json" 2> "$OUT/$3-$2.err"
  printf '%-14s %-16s %s | %s\n' "$3" "$2" "$(grep -ao 'front end [0-9.]*s' "$OUT/$3-$2.err" | head -1)" \
    "$(grep -ao 'total=[0-9.]*s' "$OUT/$3-$2.err" | tail -1)"
}
req() { one "$A" "$NA" "$1" "${ENV_A:-}"; [ "$B" = "-" ] || one "$B" "$NB" "$1" "${ENV_B:-}"; }
edit() {
  case "$1" in
    body) sed -i 's/query options must be a named scalar map/query options must be a named scalar map!/' "$F" ;;
    shift) sed -i '9i\
' "$F" ;;
    var) sed -i '/^\/datum\/act\/input$/{n;a\
	var/parity_probe = 0
}' "$G" ;;
    proc) sed -i '/^\/datum\/act\/input$/{n;a\
	proc/parity_probe_proc()\
		return 1
}' "$G" ;;
  esac
}
req base
req noop
for kind in ${EDITS:-body shift}; do
  for i in $(seq 1 "$ROUNDS"); do
    edit "$kind"
    req "$kind$i"
    restore
    req "${kind}revert$i"
  done
done
req noop2
echo DONE
