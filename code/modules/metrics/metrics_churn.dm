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

/// The busiest keys of each churn kind, in events per second: churn/<kind>/<key>/per_s for the
/// METRICS_CHURN_TOP busiest keys, and churn/<kind>/total/per_s.
/datum/metrics_source/churn
	/// FALSE until the first sample: what was counted before it is boot (every type drawn once, every first
	/// timer), which is neither a rate nor cheap to rank.
	var/started = FALSE

/datum/metrics_source/churn/collect(datum/world_service/server_metrics/M, dt)
	var/list/kinds = GLOB.churn_census.take()
	if(!started)
		started = TRUE
		return
	for(var/kind in kinds)
		var/list/counts = kinds[kind]
		var/total = 0
		// The busiest keys, kept in order by insertion: a full sort of every key costs more than the rest of
		// the sample when something new churns.
		var/list/top_keys = list()
		var/list/top_counts = list()
		for(var/key in counts)
			var/count = counts[key]
			total += count
			var/at = length(top_keys) + 1
			while(at > 1 && top_counts[at - 1] < count)
				at--
			if(at > METRICS_CHURN_TOP)
				continue
			top_keys.Insert(at, key)
			top_counts.Insert(at, count)
			if(length(top_keys) > METRICS_CHURN_TOP)
				top_keys.Cut(METRICS_CHURN_TOP + 1)
				top_counts.Cut(METRICS_CHURN_TOP + 1)
		M.gauge("churn/[kind]/total/per_s", total / dt, METRICS_CAT_CHURN, kind, "per_s")
		for(var/i in 1 to length(top_keys))
			M.gauge("churn/[kind]/[top_keys[i]]/per_s", top_counts[i] / dt, METRICS_CAT_CHURN, kind, "per_s")
