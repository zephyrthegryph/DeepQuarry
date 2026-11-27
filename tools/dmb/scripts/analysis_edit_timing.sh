#!/usr/bin/env bash
# Times `dmbc analyze check` through a daemon: the first request, three no-ops, and two rounds of a one-line body edit and its
# revert, for each compiler given. Each compiler gets its own daemon namespace and its own analysis cache directory
# (DQ_ANALYZE_CACHE under the worktree's data/), so two compilers measured back to back never read or rewrite each other's
# model, walk or result stores. Runs one compiler after the other (a daemon's read-ahead after a request must not compete with the
# other's request). Output: one line per request (client wall time, exit code, stdout digest) and the daemon's own line for it.
#
#   bash tools/dmb/scripts/analysis_edit_timing.sh master=E:/dq-cache/dmb-bin/v/<id>/dmbc.exe branch=tools/dmb/target/release/dmbc.exe
#
# EDIT_FILE / EDIT_LINE / EDIT_FROM / EDIT_TO choose the edit (default: a `return 0` body line in code/content/admin/topic.dm).
# CHECK_ARGS are the check's arguments (default --raw). The edited file is restored at the end, also on interrupt.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
file="${EDIT_FILE:-code/content/admin/topic.dm}"
line="${EDIT_LINE:-39}"
from="${EDIT_FROM:-	return 0}"
to="${EDIT_TO:-	return 1 - 1}"
read -r -a check_args <<<"${CHECK_ARGS:---raw}"
[ "$(sed -n "${line}p" "$file")" = "$from" ] || { echo "analysis_edit_timing: $file:$line is not '$from'" >&2; exit 2; }
restore() { sed -i "${line}s/.*/$(printf '%s' "$from" | sed 's/[\/&]/\\&/g')/" "$file"; }
trap restore EXIT INT TERM
set_line() { sed -i "${line}s/.*/$(printf '%s' "$1" | sed 's/[\/&]/\\&/g')/" "$file"; }
log="${DMB_DAEMON_DIR:-E:/dq-cache/dmb-daemon}/lifecycle.log"
ms() { date +%s%N | cut -c1-13; }
for spec in "$@"; do
	label="${spec%%=*}"
	bin="${spec#*=}"
	ns="timing-$label-$$"
	cache="$root/data/analyze-cache-timing-$label"
	echo "== $label: $bin (namespace $ns, cache $cache)"
	one() {
		local what="$1" before after start end lines
		before=$(wc -l <"$log" 2>/dev/null || echo 0)
		start=$(ms)
		DMB_DAEMON_AUTOSTART=1 DMB_DAEMON_NAMESPACE="$ns" DQ_ANALYZE_CACHE="$cache" "$bin" analyze check "${check_args[@]}" >"/tmp/timing-$label-$what.out" 2>/dev/null
		local code=$?
		end=$(ms)
		lines=$(tail -n +"$((before + 1))" "$log" 2>/dev/null | grep -E "dmbd analyze: (answered|request finished)" | tail -1)
		printf '%-8s %-8s %7d ms  exit %d  %s  | %s\n' "$label" "$what" "$((end - start))" "$code" "$(md5sum <"/tmp/timing-$label-$what.out" | cut -c1-8)" "$lines"
	}
	one first
	for i in 1 2 3; do one "noop$i"; done
	for i in 1 2; do
		set_line "$to"
		one "edit$i"
		restore
		one "revert$i"
	done
	one noop4
	DMB_DAEMON_NAMESPACE="$ns" "$bin" --daemon-retire >/dev/null 2>&1
done
