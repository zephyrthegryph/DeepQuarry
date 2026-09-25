// Mob Life on the object-model core (doc/rewrite/life_on_om.md).
//
// Every living mob carries the `life` behaviour. Its cadence ring runs one frame per LIFE_CYCLE
// (fixed steps, capped catch-up); a frame runs the mob's composed life systems in order
// (life_frame()). Systems sleep by their idle() rule and wake on the mob change channels in their
// `wake_on`; a mob with every system asleep leaves the ring (om_sleep) until a change or a timer
// brings it back. Nothing here decides *what* a system does: that is the content in the family
// and variant files.

/// Runtime switch for mob hibernation (MOB_HIBERNATION_ENABLED is the default).
GLOBAL_VAR_INIT(mob_hibernation_enabled, MOB_HIBERNATION_ENABLED)
/// Runtime switch for per-transition hibernate and wake logging (MOB_HIBERNATION_TRACE).
GLOBAL_VAR_INIT(mob_hibernation_trace, MOB_HIBERNATION_TRACE)
/// Hibernating living mobs -> world.time they went to sleep. Written only by
/// life_hibernate() and life_resume().
GLOBAL_LIST_EMPTY(life_hibernating_mobs)
/// Frames run since boot. Benchmarks count delivered frames with it; the per-system sampler
/// samples every SSmobs.profile_sample_stride-th frame by it.
GLOBAL_VAR_INIT(life_frames, 0)

// --- Declarations -------------------------------------------------------------------------------

/datum/om/decl/living
	of = /mob/living
	behaviours = list(
		/datum/om/behaviour/life,
		/datum/om/behaviour/life_derive,
		/datum/om/behaviour/life_present,
	)

/datum/om/decl/observer
	of = /mob/observer
	behaviours = list(/datum/om/behaviour/observer_upkeep)

/// TRUE while the game runs Life (the old SSmobs runlevels: not in the lobby or setup).
/// Master.current_runlevel is an index (log2 of the RUNLEVEL_* flag, plus one).
/proc/life_runlevel_active()
	var/level = Master.current_runlevel
	return level && ((1 << (level - 1)) & (RUNLEVEL_GAME | RUNLEVEL_POSTGAME))

// --- The frame behaviour ----------------------------------------------------------------------

/// One Life frame per LIFE_CYCLE of (fixed-step) time, and the mob's wakes and timers.
/datum/om/behaviour/life
	name = "life"
	every = LIFE_CYCLE
	step_interval = LIFE_CYCLE_SECONDS
	max_catchup = LIFE_MAX_CATCHUP
	lane = LANE_SIMULATION
	wake_on = LIFE_WAKE_CHANNELS

/datum/om/behaviour/life/on_step(mob/living/L)
	if(!life_runlevel_active() || L.life_z_idle())
		return
#ifndef LIFE_NO_PROFILE
	if(!(GLOB.life_frames % SSmobs.profile_sample_stride))
		var/start = TICK_USAGE
		L.life_frame(TRUE)
		SSmobs.record_mob_cost(L, TICK_USAGE - start)
		return
#endif
	L.life_frame()

/datum/om/behaviour/life/on_wake(mob/living/L, changes)
	L.life_changed(changes)

/datum/om/behaviour/life/on_deadline(mob/living/L)
	L.life_timers_due()

/// Status derivation (canmove): run the pass the status changes, not on the cadence.
/datum/om/behaviour/life_derive
	name = "life: derive"
	lane = LANE_DERIVED
	wake_on = LIFE_DERIVE_CHANNELS

/datum/om/behaviour/life_derive/on_wake(mob/living/L, changes)
	L.life_run_wake_only(LIFE_WAKE_ONLY_DERIVE, changes, type)

/datum/om/behaviour/life_derive/on_deadline(mob/living/L)
	L.life_run_wake_only(LIFE_WAKE_ONLY_DERIVE, ALL, type)

/// HUD and vision for mobs with a client: run on their channels and their own timers.
/// Clientless mobs don't start it; their frame runs these systems instead.
/datum/om/behaviour/life_present
	name = "life: present"
	lane = LANE_PRESENTATION
	wake_on = LIFE_PRESENT_CHANNELS
	requires = list(/datum/om/check/has_client)

/datum/om/behaviour/life_present/on_start(mob/living/L)
	L.life_run_wake_only(LIFE_WAKE_ONLY_PRESENT, ALL, type)

/// At most once per LIFE_PRESENT_MIN_INTERVAL: a player walking raises a location change most
/// ticks, and the HUD needs only the latest state.
/datum/om/behaviour/life_present/on_wake(mob/living/L, changes)
	var/wait = L.life_present_last + LIFE_PRESENT_MIN_INTERVAL - om_time_of(L)
	if(wait > 0)
		om_after(L, wait, type)
		return
	L.life_run_wake_only(LIFE_WAKE_ONLY_PRESENT, changes, type)

/datum/om/behaviour/life_present/on_deadline(mob/living/L)
	L.life_run_wake_only(LIFE_WAKE_ONLY_PRESENT, ALL, type)

/datum/om/behaviour/life_present/on_stop(mob/living/L)
	om_cancel_after(L, type)

/// Ghosts, AI eyes and the blob overmind: their old Life() upkeep.
/datum/om/behaviour/observer_upkeep
	name = "observer upkeep"
	every = OBSERVER_UPKEEP_INTERVAL
	lane = LANE_BACKGROUND

/datum/om/behaviour/observer_upkeep/tick(mob/observer/O, dt)
	if(life_runlevel_active())
		O.upkeep()

// --- Per-mob state ----------------------------------------------------------------------------

/mob/living
	/// Shared, ordered systems for this mob's composition key. Never mutated per mob.
	var/datum/life_composition/life_composition
	/// Lazy list parallel to life_composition.ordered: TRUE where the system is asleep. Null
	/// while everything is awake.
	var/list/life_asleep
	/// TRUE while the life behaviour is off its ring because nothing is awake. Written only by
	/// life_hibernate() and life_resume().
	var/life_hibernating = FALSE
	/// Lazy: life system -> scheduler time its rewake_delay() timer is due.
	var/list/life_timers
	/// Frames this mob has run.
	var/life_frame_count = 0
	/// Scheduler time the presentation systems last ran (life_present throttle).
	var/life_present_last = -INFINITY
	/// LIFE_SET_* of the Life sequence this mob type runs.
	var/life_set = LIFE_SET_LIVING
	/// Lazy list of extra system types (component-provided) this mob carries.
	var/list/life_extra_systems

/// TRUE when this mob skips frames: a low-priority mob on a z-level without living players.
/mob/living/proc/life_z_idle()
	if(!low_priority)
		return FALSE
	var/z = loc ? get_z(src) : 0
	if(!z || z > length(GLOB.living_players_by_zlevel))
		return TRUE
	return !length(GLOB.living_players_by_zlevel[z])

// --- The frame --------------------------------------------------------------------------------

/// Runs one Life frame now: every awake system of the composition, in order. The life behaviour
/// calls it once per LIFE_CYCLE; tests and a few effects call it directly.
/mob/living/proc/life_frame(profile = FALSE)
	set waitfor = FALSE
	var/datum/life_composition/comp = life_composition || recompose_life()
	var/datum/life_context/ctx = new(LIFE_CYCLE_SECONDS, profile)
	ctx.stasis = body ? body.advance_stasis() : FALSE
	GLOB.life_frames++
	life_frame_count++
	var/list/ordered = comp.ordered
	var/has_client = !!client
	var/halted = FALSE
	var/list/to_sleep
	for(var/i in 1 to length(ordered))
		var/datum/life_system/S = ordered[i]
		if(S.wake_only && (S.wake_only == LIFE_WAKE_ONLY_DERIVE || has_client))
			continue
		if(life_asleep && life_asleep[i])
			continue
		if(ctx.blocked & S.segment)
			// Skipped this frame: it may sleep if it has nothing to do (gates never do).
			if(!S.gate && !life_system_wants_run(S))
				LAZYADD(to_sleep, i)
			continue
		var/result
		if(profile)
			var/profile_start = TICK_USAGE
			result = S.tick(src, ctx)
			SSmobs.record_system_cost(S, TICK_USAGE - profile_start)
		else
			result = S.tick(src, ctx)
		if(QDELETED(src))
			return
		if(result == LIFE_HALT)
			halted = TRUE
			break
		if(S.gate)
			continue
		if(result == LIFE_SLEEP || !life_system_wants_run(S))
			LAZYADD(to_sleep, i)
			var/delay = S.rewake_delay(src)
			if(delay > 0)
				life_wake_later(S, delay)
	// Nothing sleeps in a frame that halted or that a gate stopped for a reason no wake covers.
	if(halted || ctx.no_sleep || !to_sleep)
		return
	if(!life_asleep)
		life_asleep = new /list(length(ordered))
	for(var/i in to_sleep)
		life_asleep[i] = TRUE
	if(GLOB.mob_hibernation_trace)
		log_runtime("MOB_HIBERNATE: [key_name(src)] ([type]) systems asleep: [length(to_sleep)]")
	if(life_all_asleep())
		life_hibernate("no awake systems")

/// TRUE when every system the frame would run is asleep.
/mob/living/proc/life_all_asleep()
	if(!life_asleep)
		return FALSE
	var/datum/life_composition/comp = life_composition
	var/has_client = !!client
	for(var/i in comp.sleepers)
		if(life_asleep[i])
			continue
		var/datum/life_system/S = comp.ordered[i]
		if(S.wake_only == LIFE_WAKE_ONLY_PRESENT && has_client)
			continue
		return FALSE
	return TRUE

/// TRUE when system `S` has work to do for this mob now. A dead mob never runs the
/// segments its gates block, so those systems never keep it awake.
/mob/living/proc/life_system_wants_run(datum/life_system/S)
	if(stat == DEAD && (S.segment & LIFE_SEGS_BLOCKED_WHEN_DEAD))
		return FALSE
	return !S.idle(src)

/// Runs this mob's wake-only systems of `kind` whose channels are in `changes`, then arms the
/// behaviour's timer for those that still have work (next frame) or asked to be re-run.
/mob/living/proc/life_run_wake_only(kind, changes, behaviour_type)
	set waitfor = FALSE
	var/datum/life_composition/comp = life_composition || recompose_life()
	var/list/systems = kind == LIFE_WAKE_ONLY_DERIVE ? comp.derive : comp.present
	if(!length(systems))
		return
	// The old frame skipped these while transforming or in nullspace (LIFE_SEG_LIVING).
	if(transforming || !loc)
		return
	var/soonest = 0
	if(kind == LIFE_WAKE_ONLY_PRESENT)
		life_present_last = om_time_of(src)
	for(var/datum/life_system/S as anything in systems)
		if(!(S.wake_on & changes))
			continue
		S.tick(src, null)
		if(QDELETED(src))
			return
		// A presentation system with work left (a component-driven HUD) runs again next cycle.
		// A derivation doesn't: every change to what it reads raises its channels already.
		var/delay = (kind == LIFE_WAKE_ONLY_PRESENT && life_system_wants_run(S)) ? LIFE_CYCLE : S.rewake_delay(src)
		if(delay > 0 && (!soonest || delay < soonest))
			soonest = delay
	if(soonest)
		om_after(src, soonest, behaviour_type)

// --- Wakes, hibernation and timers ------------------------------------------------------------

/// The life behaviour's on_wake: `changes` (mob channels) wake the systems that declared them.
/// A hibernating mob wakes whole, so every system re-checks its rule once.
/mob/living/proc/life_changed(changes)
	if(life_hibernating)
		life_resume(life_wake_reason(changes))
		return
	if(!life_asleep)
		return
	var/list/ordered = life_composition?.ordered
	var/any_asleep = FALSE
	for(var/i in 1 to length(life_asleep))
		if(!life_asleep[i])
			continue
		var/datum/life_system/S = ordered[i]
		if(S.wake_on & changes)
			life_asleep[i] = null
		else
			any_asleep = TRUE
	if(!any_asleep)
		life_asleep = null

/// A short name for the wake summary, from the channels that caused it.
/proc/life_wake_reason(changes)
	var/static/list/names = list(
		"stat" = CHANGE_MOB_STAT, "client" = CHANGE_MOB_CLIENT, "health" = CHANGE_MOB_HEALTH,
		"status" = CHANGE_MOB_STATUS, "moved" = CHANGE_MOB_LOC, "equipment" = CHANGE_MOB_EQUIPMENT,
		"conditions" = CHANGE_MOB_CONDITIONS, "explicit" = CHANGE_EXPLICIT,
	)
	for(var/name in names)
		if(changes & names[name])
			return name
	return "other"

/// Takes this mob off the life ring until something wakes it. The only proc that parks a mob.
/mob/living/proc/life_hibernate(reason)
	if(life_hibernating || !GLOB.mob_hibernation_enabled || QDELETED(src))
		return FALSE
	life_hibernating = TRUE
	GLOB.life_hibernating_mobs[src] = world.time
	SSmobs.hibernations++
	om_sleep(src, /datum/om/behaviour/life)
	if(GLOB.mob_hibernation_trace)
		log_runtime("MOB_HIBERNATE: [key_name(src)] ([type]) hibernating ([reason || "unspecified"]); [length(GLOB.life_hibernating_mobs)] hibernating")
	return TRUE

/// Puts a hibernating mob back on the life ring. The only proc that unparks a mob. A change
/// wakes it whole, so every system re-checks its rule once; a timer passes `only` (the systems
/// whose timers are due) and wakes just those, as the old partial timer wake did. Its next frame
/// covers at most one cycle: the ring never hands a rejoining entity the length of its nap.
/mob/living/proc/life_resume(reason, list/only)
	if(!life_hibernating)
		return FALSE
	life_hibernating = FALSE
	life_asleep = null
	if(only && life_composition)
		var/list/ordered = life_composition.ordered
		life_asleep = new /list(length(ordered))
		for(var/i in life_composition.sleepers)
			if(!(ordered[i] in only))
				life_asleep[i] = TRUE
	var/slept_since = GLOB.life_hibernating_mobs[src]
	GLOB.life_hibernating_mobs -= src
	SSmobs.note_wake(reason)
	if(!QDELETED(src))
		om_resume(src, /datum/om/behaviour/life)
	if(GLOB.mob_hibernation_trace)
		log_runtime("MOB_HIBERNATE: [key_name(src)] ([type]) woke ([reason || "unspecified"]) after [DisplayTimeText(world.time - slept_since)]; [length(GLOB.life_hibernating_mobs)] hibernating")
	return TRUE

/// Wakes system `S` after `delay` deciseconds (an idle system that still drifts slowly). One
/// deadline per mob on the life behaviour, at the earliest due; a later request for the same
/// system keeps the earlier one.
/mob/living/proc/life_wake_later(datum/life_system/S, delay)
	var/due = om_time_of(src) + delay
	var/current = LAZYACCESS(life_timers, S)
	if(current && current <= due)
		return
	LAZYSET(life_timers, S, due)
	life_arm_timer()

/// Arms the life behaviour's deadline at the soonest pending timer, or cancels it.
/mob/living/proc/life_arm_timer()
	var/soonest = 0
	for(var/datum/life_system/S as anything in life_timers)
		var/due = life_timers[S]
		if(!soonest || due < soonest)
			soonest = due
	if(soonest)
		om_after(src, max(soonest - om_time_of(src), 0), /datum/om/behaviour/life)
	else
		om_cancel_after(src, /datum/om/behaviour/life)

/// The life behaviour's deadline: wakes the systems whose timers are due. It never runs a
/// frame: a woken system runs in the mob's next frame.
/mob/living/proc/life_timers_due()
	var/now = om_time_of(src)
	var/list/due_systems
	for(var/datum/life_system/S as anything in life_timers)
		if(life_timers[S] <= now)
			LAZYADD(due_systems, S)
	for(var/datum/life_system/S as anything in due_systems)
		LAZYREMOVE(life_timers, S)
	if(due_systems)
		if(life_hibernating)
			life_resume("timer", due_systems)
		else if(life_asleep)
			var/list/ordered = life_composition?.ordered
			for(var/datum/life_system/S as anything in due_systems)
				var/i = ordered?.Find(S)
				if(i && i <= length(life_asleep))
					life_asleep[i] = null
	life_arm_timer()

/// The hibernation audit's check: the first sleeping system whose sleep rule no longer holds,
/// or null. A hit means a producer changed the mob without raising the channel.
/mob/living/proc/life_missed_wake()
	var/datum/life_composition/comp = life_composition
	if(!comp)
		return null
	var/has_client = !!client
	for(var/i in comp.sleepers)
		if(!life_hibernating && !(life_asleep && life_asleep[i]))
			continue
		var/datum/life_system/S = comp.ordered[i]
		if(S.wake_only == LIFE_WAKE_ONLY_PRESENT && has_client)
			continue
		if(LAZYACCESS(life_timers, S))
			continue
		if(life_system_wants_run(S))
			return S
	return null

// --- Suspension (doc/rewrite/life_on_om.md §9) ------------------------------------------------

/// Takes this mob off every ring until resume_life(): a digested body kept for reforming. A
/// suspension hold the mob holds on itself, so it lasts exactly until resumed or deleted.
/mob/living/proc/suspend_life()
	om_suspend(src, src)

/mob/living/proc/resume_life()
	om_unsuspend(src, src)

/// TRUE while suspend_life() holds.
/mob/living/proc/life_suspended()
	return om_value_of(src, EFFECT_SUSPENDED)

// --- Composition ------------------------------------------------------------------------------

/// Rebuilds this mob's system list from its type and extras (species, plan or trait change).
/// A changed composition wakes the mob whole.
/mob/living/proc/recompose_life()
	RETURN_TYPE(/datum/life_composition)
	var/datum/life_composition/old = life_composition
	var/datum/life_composition/comp = compose_life_systems(src)
	if(comp == old)
		return comp
	life_composition = comp
	if(old)
		for(var/datum/life_system/S as anything in old.ordered)
			if(!(S in comp.ordered))
				S.detach(src)
				LAZYREMOVE(life_timers, S)
	for(var/datum/life_system/S as anything in comp.ordered)
		if(!old || !(S in old.ordered))
			S.attach(src)
	// Positions changed: nothing stays asleep.
	life_asleep = null
	if(old)
		if(life_hibernating)
			life_resume("recomposed")
		om_changed(src, CHANGE_EXPLICIT)
	return comp

/// Drops the composition, detaching every system. Called from Destroy().
/mob/living/proc/clear_life_systems()
	if(life_composition)
		for(var/datum/life_system/S as anything in life_composition.ordered)
			S.detach(src)
	life_composition = null
	life_extra_systems = null
	life_asleep = null
	life_timers = null
	if(life_hibernating)
		life_hibernating = FALSE
		GLOB.life_hibernating_mobs -= src

/// Gives this mob an extra (component-provided) system.
/mob/living/proc/add_life_system(path)
	if(path in life_extra_systems)
		return
	LAZYADD(life_extra_systems, path)
	if(life_composition)
		recompose_life()

/// Removes an extra system added by add_life_system().
/mob/living/proc/remove_life_system(path)
	if(!(path in life_extra_systems))
		return
	LAZYREMOVE(life_extra_systems, path)
	if(life_composition)
		recompose_life()

/// Adds a trait system to a mob if it is living (components may sit on any mob).
/proc/add_trait_life_system(mob/M, path)
	var/mob/living/L = M
	if(istype(L))
		L.add_life_system(path)

/// Removes a trait system added by add_trait_life_system().
/proc/remove_trait_life_system(mob/M, path)
	var/mob/living/L = M
	if(istype(L))
		L.remove_life_system(path)

/// The variant of a system family that serves this mob, whether or not it is scheduled.
/mob/living/proc/life_system_for(family)
	return resolve_life_system(family, type)

/// Runs one system family for this mob now, outside the schedule. Returns its tick() result.
/mob/living/proc/run_life_system(family)
	var/datum/life_system/S = resolve_life_system(family, type)
	return S?.tick(src, null)

// --- Public refresh entry points --------------------------------------------------------------
// Code outside Life asks for an immediate HUD or vision refresh through these. Living mobs
// run their HUD and senses systems; other mobs keep the base behaviour.

/// Refreshes the player HUD now. Returns FALSE when there is no HUD to refresh.
/mob/proc/refresh_hud()
	return hud_available()

/// TRUE when this mob has a client HUD that no component has taken over.
/mob/proc/hud_available()
	if(!client)
		return FALSE
	if(SEND_SIGNAL(src,COMSIG_MOB_HANDLE_HUD) & COMSIG_COMPONENT_HANDLED_HUD)
		return FALSE
	return TRUE

/mob/living/refresh_hud()
	return run_life_system(/datum/life_system/hud)

/// Recomputes sight flags (SEE_TURFS, see_in_dark, ...) now.
/mob/proc/refresh_vision()
	SEND_SIGNAL(src,COMSIG_MOB_HANDLE_VISION)

/mob/living/refresh_vision()
	run_life_system(/datum/life_system/vision)

// --- Producers ----------------------------------------------------------------------------
// Hooks on /mob that the generic mob code calls; living mobs raise the matching channel.

/// Stun, weaken, paralysis, sleep, confusion and blindness setters call this.
/mob/proc/on_status_counter_changed(reason)
	return

/mob/living/on_status_counter_changed(reason)
	om_changed(src, CHANGE_MOB_STATUS)

/// A client logged into or out of this mob: the HUD, senses and client systems restart.
/mob/living/proc/on_client_changed(reason)
	om_changed(src, CHANGE_MOB_CLIENT)

/// Something was equipped or unequipped.
/mob/proc/on_equipment_changed()
	return

/mob/living/on_equipment_changed()
	body?.invalidate(BODY_DIRTY_ARMOR)
	om_changed(src, CHANGE_MOB_EQUIPMENT)
