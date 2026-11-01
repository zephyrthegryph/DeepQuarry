#!/usr/bin/env bash
# The LANDED line carries what the lane waited: enqueue time, ready time (its precheck pass) and the waits, so lands per hour and queue wait can
# be measured from E:/dq-cache/train/log/train.log. Scratch state; the function is sourced from tools/dq_train.sh.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tip=0123456789abcdef0123456789abcdef01234567
run() { # <enqueued iso> <with verdict 0/1>
	( set +u; export DQ_TRAIN_STATE="$tmp/state" DQ_TRAIN_WT="$tmp/none" DQ_TRAIN_ORIGIN_REPO="$here" DQ_TRAIN_NO_START=1
	  . "$here/tools/dq_train.sh" __lib; mkdir -p "$PRE/v"; rm -f "$PRE/v/"*
	  if [ "$2" = 1 ]; then printf 'verdict=pass\nmaster=abc\n' >"$PRE/v/$(pre_key lane/x "$tip")@abc"; touch -d '2 minutes ago' "$PRE/v/$(pre_key lane/x "$tip")@abc"; fi
	  landed_times lane/x "$tip" "$1" ) 2>/dev/null
}
enq="$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
out="$(run "$enq" 1)"
case "$out" in *"enqueued $enq, ready "*"waited 6"[0-9][0-9]"s to land ("1[12][0-9]"s since ready)]"*) ok "enqueue, ready and both waits are reported" ;; *) bad "unexpected: $out" ;; esac
out="$(run "$enq" 0)"
case "$out" in *"enqueued $enq, waited 6"*) ok "a lane with no precheck verdict reports its enqueue wait only" ;; *) bad "unexpected: $out" ;; esac
grep -q 'landed_times "\$b" "\$tip"' "$here/tools/dq_train.sh" && ok "mark_landed puts it on the LANDED line" || bad "LANDED line does not use landed_times"
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
