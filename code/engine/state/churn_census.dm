// What keeps an idle server busy: counts of the repeated small things whose cost is spread too thinly over
// many procs for a profile to name the source. Framework points count into GLOB.churn_census (each count is
// one assoc increment), and the churn metrics source reports the busiest keys of each kind every sample:
//  - draw: entities refreshed by the refresh drain (their look, verbs and windows), by type
//  - timer: OM timers fired, by owner type and proc
//  - signal: radio signals posted, by frequency and sender type
//  - light: light sources updated by the lighting queue, by source atom type
//  - power_edit: cable network topology edits (power_topology_edited()), by what made them

GLOBAL_DATUM_INIT(churn_census, /datum/churn_census, new)

/// A singleton (GLOB.churn_census). Count with CHURN_COUNT() (__defines/metrics.dm).
/datum/churn_census
	/// key -> count since the churn source last took them (take()). Never null, so a count is one increment.
	var/list/draws
	var/list/timers
	var/list/signals
	var/list/lights
	var/list/power_edits

/datum/churn_census/New()
	. = ..()
	take()

/// The counts of every kind since the last call, as list(kind = list(key = count)); starts the next window.
/datum/churn_census/proc/take()
	. = list("draw" = draws, "timer" = timers, "signal" = signals, "light" = lights, "power_edit" = power_edits)
	draws = list()
	timers = list()
	signals = list()
	lights = list()
	power_edits = list()
