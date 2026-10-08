// Publication cadence as timed grants (doc/rewrite/unified_plan.md, live simulation).
//
// A system whose results are published in steps (gas) can publish faster for a while when
// something visible is happening. That is a hold on STAT_CADENCE_HOLDS of the system's cadence
// datum: a canister rupture, hull breach or pressure-jump storm asks for fast gas, and the
// system runs at the shortest step any live grant names. Grants stack and lapse on their own,
// so the last one to expire drops the system back to its base step, and a grant dies with
// its source.
//
//   hold(SSvg.get_step_cadence(), STAT_CADENCE_HOLDS, 1, src, lasts = 5 SECONDS, key = CADENCE_GAS_FAST)
//
// Rust only ever sees the resulting step length (vg_world_set_dt): the law step, the
// publication drain and SSvg's own wait all follow it.

/// Step length in seconds a cadence id asks for. Unknown ids ask for nothing.
/proc/cadence_dt_of(id)
	var/static/list/table = list(
		CADENCE_GAS_FAST = 0.1,
		CADENCE_GAS_BRISK = 0.25,
	)
	return table[id]

/// Holds the cadence grants for one system and tells its owner when the step length changes.
/datum/step_cadence
	/// The step with no grant held, seconds.
	var/base_dt = CADENCE_BASE_DT

/// The shortest step any live grant names, else the base step, in seconds.
/datum/step_cadence/proc/dt_seconds()
	. = base_dt
	var/list/held = stat_value(src, STAT_CADENCE_HOLDS)
	if(!length(held))
		return
	for(var/id in held)
		if(held[id] <= 0)
			continue
		var/dt = cadence_dt_of(id)
		if(dt && dt < .)
			. = dt

/// The step length changed (a hold began or lapsed). Owners override it.
/datum/step_cadence/proc/cadence_changed()
	return

CAPABILITIES(/datum/step_cadence)
	on_change(STAT_CADENCE_HOLDS, ANY, then(PROC_REF(cadence_stat_changed)))

/datum/step_cadence/proc/cadence_stat_changed(datum/act/A)
	cadence_changed()

// ---- the native system's step: the system's own procs are in code/datums/native/system.dm ----

/// The native system's grant holder: a step change reaches Rust.
/datum/step_cadence/native

/datum/step_cadence/native/cadence_changed()
	SSvg.apply_step_cadence()
