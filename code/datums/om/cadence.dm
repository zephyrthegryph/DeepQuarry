// Publication cadence as timed grants (doc/rewrite/unified_plan.md, live simulation).
//
// A system whose results are published in steps (gas) can publish faster for a while when
// something visible is happening. That is a GRANT_CADENCE grant held on the system's cadence
// datum: a canister rupture, hull breach or pressure-jump storm asks for fast gas, and the
// system runs at the shortest step any live grant names. Grants stack and lapse on their own,
// so the last one to expire drops the system back to its base step, and a grant dies with
// its source.
//
//   om_grant_for(SSvg.get_step_cadence(), GRANT_CADENCE, CADENCE_GAS_FAST, src, 5 SECONDS)
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
	var/list/held = om_value_of(src, GRANT_CADENCE)
	if(!islist(held))
		return
	for(var/id in held)
		if(held[id] <= 0)
			continue
		var/dt = cadence_dt_of(id)
		if(dt && dt < .)
			. = dt

/// The step length changed (a grant began or lapsed). Owners override it.
/datum/step_cadence/proc/cadence_changed()
	return

/// GRANT_CADENCE's effect: the same store as GRANT_VERB and the other grants. A grant beginning
/// or lapsing (or its source dying) changes the combined value, and the holder is told once.
/datum/om/effect/grant_cadence

/datum/om/effect/grant_cadence/on_changed(datum/E, old_value, new_value)
	var/datum/step_cadence/C = E
	if(istype(C))
		C.cadence_changed()

// ---- the native system's step (was on SSvg, now /datum/system/native) ----

/// The step length last handed to Rust (vg_world_set_dt), seconds.
/datum/system/native/var/current_dt = CADENCE_BASE_DT
/// Holds the GRANT_CADENCE grants for the gas step, created on first use.
/datum/system/native/var/datum/step_cadence/native/step_cadence

/// The cadence datum to hold GRANT_CADENCE grants on.
/datum/system/native/proc/get_step_cadence()
	RETURN_TYPE(/datum/step_cadence)
	if(!step_cadence)
		step_cadence = new
	return step_cadence

/// Runs the world at the shortest step any cadence grant names.
/datum/system/native/proc/apply_step_cadence()
	set_step_dt(get_step_cadence().dt_seconds())

/// Sets the step length: Rust integrates it from the next step (the native frame runs every tick either way).
/datum/system/native/proc/set_step_dt(dt)
	if(dt == current_dt)
		return
	current_dt = vg_world_set_dt(dt)

/// The native system's grant holder: a step change reaches Rust.
/datum/step_cadence/native

/datum/step_cadence/native/cadence_changed()
	SSvg.apply_step_cadence()
