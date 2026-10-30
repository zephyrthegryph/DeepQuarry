#!/usr/bin/env bash
# Live game servers: a running DreamDaemon uses its .dmb/.rsc (a run directory under E:/dq-cache/dmb-build-integration) and writes its rounds' logs under
# the -cd worktree's data/logs. Cleanup (the pool's release, the disk budget) must never pull those out from under it.
#
#   bash tools/dq_live_world.sh list              command lines of running dd/DreamDaemon processes, lowercased, / separators (fresh, never cached)
#   bash tools/dq_live_world.sh worktree <path>   exit 0 when a running world has <path> as its -cd directory
#   bash tools/dq_live_world.sh unit <path>       exit 0 when a running world's command line names <path> (a run directory)
live_list() {
	[ -n "${DQ_LIVE_WORLD_CMD:-}" ] && { eval "$DQ_LIVE_WORLD_CMD" | tr 'A-Z\\' 'a-z/'; return; }
	powershell.exe -NoProfile -NonInteractive -Command "Get-CimInstance Win32_Process -Filter \"Name='dd.exe' or Name='DreamDaemon.exe'\" | ForEach-Object { \$_.CommandLine }" 2>/dev/null | tr -d '\r' | tr 'A-Z\\' 'a-z/'
}
norm() { local p="${1,,}"; p="${p//\\//}"; [[ "$p" =~ ^/([a-z])/ ]] && p="${BASH_REMATCH[1]}:/${p:3}"; p="${p%/}"; printf '%s' "$p"; }
case "${1:-}" in
	list) live_list ;;
	worktree) p="$(norm "${2:?path}")"; live_list | grep -qE -- "-cd $p( |\$)" && exit 0; exit 1 ;;
	unit) p="$(norm "${2:?path}")"; live_list | grep -qF -- "$p/" && exit 0; exit 1 ;;
	*) echo "usage: dq_live_world.sh list|worktree <path>|unit <path>" >&2; exit 2 ;;
esac
