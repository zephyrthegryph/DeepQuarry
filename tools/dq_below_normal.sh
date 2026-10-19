#!/usr/bin/env bash
# Source this at the top of a long-running script: it lowers this shell to below-normal priority, so everything the script starts
# (cargo and rustc, bun and the builds it runs, DreamDaemon, DreamChecker, dmbc) inherits it. The machine is also the user's desktop;
# lanes and gates running at normal priority beside a game lagged it badly (2026-10-19). DQ_PRIORITY=normal leaves it alone.
if [ "${DQ_PRIORITY:-}" != normal ] && [ -z "${DQ_BELOW_NORMAL_DONE:-}" ]; then
	export DQ_BELOW_NORMAL_DONE=1
	if [ -r "/proc/$$/winpid" ] && command -v powershell.exe >/dev/null 2>&1; then
		powershell.exe -NoProfile -NonInteractive -Command "try { (Get-Process -Id $(cat /proc/$$/winpid)).PriorityClass = 'BelowNormal' } catch {}" >/dev/null 2>&1 || true
	elif command -v renice >/dev/null 2>&1; then
		renice -n 10 -p $$ >/dev/null 2>&1 || true
	fi
fi
