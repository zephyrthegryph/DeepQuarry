#!/usr/bin/env bash
# Compile side of a front end change: daemon compiles of two compilers through the same edit sequence, compared byte for byte.
# usage: bash tools/dmb/scripts/frontend_compile_pair.sh <dmbcA> <nsA> <dmbcB> <nsB> <out dir> [states...]
# States as frontend_hosted_parity.sh (default: base body bodyrevert shift shiftrevert var varrevert proc procrevert). After each
# state each daemon compiles deepquarry.dme (`dmbc compile`, holding the machine's dm_compile slot); the .dmb and .rsc are hashed
# and kept under <out dir>, and the line says whether the two compilers' outputs are identical. Copy the binaries out of a cargo
# target first and retire both daemons afterwards. ENV_A / ENV_B: extra env for each compiler's requests.
set -u
A="$1"; NA="$2"; B="$3"; NB="$4"; OUT="$5"; shift 5
STATES="${*:-base body bodyrevert shift shiftrevert var varrevert proc procrevert}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
export DMB_DAEMON_AUTOSTART=1
F=code/engine/actions/admission_query.dm
G=code/engine/lifeforms/input.dm
mkdir -p "$OUT"
git show HEAD:$F > "$OUT/orig.dm"
git show HEAD:$G > "$OUT/orig_input.dm"
restore() { cp "$OUT/orig.dm" "$F"; cp "$OUT/orig_input.dm" "$G"; }
trap restore EXIT INT TERM
restore
edit() {
  restore
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
compile() { # binary namespace label env
  local started=$(date +%s)
  env ${4:-} DMB_DAEMON_NAMESPACE="$2" bash tools/dq_machine_slots.sh run dm_compile --label "frontend-compile-pair $2" -- \
    "$1" compile deepquarry.dme > "$OUT/$3-$2.log" 2>&1
  local code=$?
  cp deepquarry.dmb "$OUT/$3-$2.dmb" 2>/dev/null
  cp deepquarry.rsc "$OUT/$3-$2.rsc" 2>/dev/null
  echo "$code $(( $(date +%s) - started ))"
}
for state in $STATES; do
  edit "${state%revert}"
  case "$state" in *revert|base) restore ;; esac
  ra=$(compile "$A" "$NA" "$state" "${ENV_A:-}")
  rb=$(compile "$B" "$NB" "$state" "${ENV_B:-}")
  da=$(sha256sum < "$OUT/$state-$NA.dmb" | cut -c1-16); db=$(sha256sum < "$OUT/$state-$NB.dmb" | cut -c1-16)
  sa=$(sha256sum < "$OUT/$state-$NA.rsc" | cut -c1-16); sb=$(sha256sum < "$OUT/$state-$NB.rsc" | cut -c1-16)
  if [ "$da" = "$db" ] && [ "$sa" = "$sb" ]; then verdict=IDENTICAL; else verdict=DIFFERENT; fi
  printf '%-12s %s  A %s/%s (exit, s: %s)  B %s/%s (%s)\n' "$state" "$verdict" "$da" "$sa" "$ra" "$db" "$sb" "$rb"
done
echo DONE
