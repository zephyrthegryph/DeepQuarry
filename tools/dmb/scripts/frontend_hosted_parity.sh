#!/usr/bin/env bash
# Hosted (incremental) against cold front end in the same daemon, through an edit sequence: after each edit state, asks
# `analyze dreamchecker --json` and `analyze check --raw --no-cache` of the daemon twice, once hosted and once with
# DQ_ANALYZE_HOSTED_FRONTEND=0 (the front end built cold for that request), and compares the two outputs byte for byte.
# usage: bash tools/dmb/scripts/frontend_hosted_parity.sh <dmbc> <namespace> <out dir> [states...]
# States (default: base body bodyrevert shift shiftrevert var varrevert proc procrevert): the edits of frontend_edit_pair.sh,
# each applied to the base files (a `...revert` state restores them). CHECKS chooses the commands ("dreamchecker check").
# ENV: extra env for every request (DMB_FRONTEND_VERIFY=1 makes the daemon verify its incremental steps as well).
# Run it in the background with output to a file: a check request takes minutes; run it again with the same <out dir> to resume.
# Retire the daemon afterwards.
set -u
BIN="$1"; NS="$2"; OUT="$3"; shift 3
STATES="${*:-base body bodyrevert shift shiftrevert var varrevert proc procrevert}"
cd "$(git rev-parse --show-toplevel)"
export DQ_ANALYZE_PARSE=dmbc DMB_DAEMON_AUTOSTART=1 DQ_ANALYZE_DAEMON_TRACE=1 DQ_FRONTEND_TRACE=1 DQ_ANALYZE_MODEL_MEMO=0 \
  DQ_ANALYZE_SHARED_CACHE=off
F=code/engine/actions/admission_query.dm
G=code/engine/lifeforms/input.dm
mkdir -p "$OUT"
# One run at a time per output directory (two would edit the same files under each other); BUDGET seconds (default 1500) bound a
# run below an agent shell's limit: no request starts after it, and a later run resumes.
LOCK="$OUT/.lock"
mkdir "$LOCK" 2>/dev/null || { echo "frontend_hosted_parity: $LOCK exists: another run uses $OUT" >&2; exit 3; }
START=$(date +%s)
git show HEAD:$F > "$OUT/orig.dm"
git show HEAD:$G > "$OUT/orig_input.dm"
restore() { cp "$OUT/orig.dm" "$F"; cp "$OUT/orig_input.dm" "$G"; }
trap 'restore; rmdir "$LOCK"' EXIT
trap 'exit 143' INT TERM
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
ask() { # label command... ; writes $OUT/<label>.out and .err (an answer already there is kept: a run killed by a shell limit resumes)
  local label="$1"; shift
  case "$(cat "$OUT/$label.code" 2>/dev/null)" in 0|1|2) return 0 ;; esac
  if [ $(( $(date +%s) - START )) -gt "${BUDGET:-1500}" ]; then echo "budget spent: run again to resume"; exit 0; fi
  env ${ENV:-} DMB_DAEMON_NAMESPACE="$NS" DQ_ANALYZE_CACHE="$(pwd)/data/meas/cache-$NS" "$BIN" analyze "$@" \
    > "$OUT/$label.out" 2> "$OUT/$label.err"
  echo $? > "$OUT/$label.code"
}
for state in $STATES; do
  edit "${state%revert}"
  case "$state" in
    *revert|base) restore ;;
    *) if cmp -s "$OUT/orig.dm" "$F" && cmp -s "$OUT/orig_input.dm" "$G"; then echo "frontend_hosted_parity: the $state edit did not apply" >&2; exit 4; fi ;;
  esac
  for command in ${CHECKS:-dreamchecker check}; do
    case "$command" in
      dreamchecker) args=(dreamchecker --json); export DQ_DREAMCHECKER_LIST=1 ;;
      check) args=(check --raw --no-cache) ;;
    esac
    ask "$state-$command-hosted" "${args[@]}"
    DQ_ANALYZE_HOSTED_FRONTEND=0 ask "$state-$command-cold" "${args[@]}"
    unset DQ_DREAMCHECKER_LIST
    # The checker's diagnostics themselves (DQ_DREAMCHECKER_LIST=1 prints each on stderr): compared beside the output.
    for side in hosted cold; do grep -a '\.dm' "$OUT/$state-$command-$side.err" | grep -av '^dmb\|^dmbd\|^analyze:' > "$OUT/$state-$command-$side.list"; done
    if cmp -s "$OUT/$state-$command-hosted.out" "$OUT/$state-$command-cold.out" \
      && cmp -s "$OUT/$state-$command-hosted.list" "$OUT/$state-$command-cold.list"; then verdict=IDENTICAL; else verdict=DIFFERENT; fi
    printf '%-12s %-12s %s (%s bytes, %s listed; exit %s/%s)%s\n' "$state" "$command" "$verdict" \
      "$(wc -c < "$OUT/$state-$command-hosted.out")" "$(wc -l < "$OUT/$state-$command-hosted.list")" "$(cat "$OUT/$state-$command-hosted.code")" \
      "$(cat "$OUT/$state-$command-cold.code")" \
      "$(grep -aqs 'confirming with a cold run' "$OUT/$state-$command-hosted.err" "$OUT/$state-$command-cold.err" && echo ' [cold unused-ALLOW recheck ran]')$(grep -aqs 'did not serve this request' "$OUT/$state-$command-hosted.err" "$OUT/$state-$command-cold.err" && echo ' [NOT SERVED BY THE DAEMON: no proof]')"
  done
done
echo DONE
