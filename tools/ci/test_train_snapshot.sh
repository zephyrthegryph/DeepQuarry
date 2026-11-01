#!/usr/bin/env bash
# The integrator runs from a snapshot (E:/dq-cache/train/self, SNAP_FILES in tools/dq_train.sh). A script it runs that calls a sibling the
# snapshot lacks fails there, not here: dq_disk_budget.sh called dq_live_world.sh, which was never copied, so every cycle logged "No such
# file" and the "a live game server uses this worktree" protection silently answered "not live". Every sibling a snapshot script calls through
# its own directory must be in SNAP_FILES. Argument: an alternative dq_train.sh to read SNAP_FILES from (the test's own negative case).
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
train="${1:-$here/tools/dq_train.sh}"
fail=0
snap="$(sed -n 's/^SNAP_FILES=(\(.*\))$/\1/p' "$train")"
for f in $snap; do
	case "$f" in *.sh) ;; *) continue ;; esac
	[ -f "$here/tools/$f" ] || { echo "FAIL: SNAP_FILES names $f, which does not exist"; fail=1; continue; }
	for sib in $(grep -oE '(BASH_SOURCE\[0\]%/\*|SELF_DIR|HERE)\}?/[A-Za-z0-9_./-]+\.(sh|js|py|toml)' "$here/tools/$f" | sed -E 's#.*/##' | sort -u); do
		[ -f "$here/tools/$sib" ] || continue
		case "$sib" in dq_declared_tests.sh|dq_light_paths.sh) continue ;; esac   # enqueue-only: they run from the lane checkout, never the snapshot
		case " $snap " in *" $sib "*) ;; *) echo "FAIL: $f calls $sib, which is not in SNAP_FILES"; fail=1 ;; esac
	done
done
[ "$fail" -eq 0 ] && echo "PASS: every sibling a snapshot script calls is in SNAP_FILES" || { echo "SOME FAILED"; exit 1; }
