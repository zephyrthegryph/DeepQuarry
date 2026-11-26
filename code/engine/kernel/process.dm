// The core's per-datum process() hook. Periodic gameplay work is every() (code/engine/actions/reactions.dm); the old
// cadences (periodic_cadence / periodic_step / cadence_start, the /datum/cadence sweeps) are gone and banned.

/// The core's own per-datum hook, kept for tgui windows and database queries (SStgui, SSdbcore).
/// No gameplay type defines it any more (tools/ci/pollers_lint.py counts the overrides).
/datum/proc/process()
	return PROCESS_KILL
