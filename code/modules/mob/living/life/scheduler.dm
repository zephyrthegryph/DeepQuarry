// The Life scheduler (doc/mob_life_architecture.md §4.3). /mob/living/Life() is the only Life()
// for living mobs: it runs the mob's composed life systems in order. No behaviour lives here.

/// Runtime switch for mob hibernation (MOB_HIBERNATION_ENABLED is the default).
GLOBAL_VAR_INIT(mob_hibernation_enabled, MOB_HIBERNATION_ENABLED)
/// Runtime switch for per-transition hibernate and wake logging (MOB_HIBERNATION_TRACE).
GLOBAL_VAR_INIT(mob_hibernation_trace, MOB_HIBERNATION_TRACE)

/mob
	/// world.time of this mob's previous Life() call; SSmobs derives elapsed seconds from it.
	var/life_last_time = 0
	/// TRUE while SSmobs skips this mob because nothing is awake. Written only by
	/// life_hibernate() and life_wake().
	var/life_hibernating = FALSE

/mob/living
	/// Shared, ordered systems for this mob's composition key. Never mutated per mob.
	var/datum/life_composition/life_composition
	/// LIFE_SYS_* bits of the systems that want to run. Everything starts awake; a system
	/// whose idle() holds after its tick goes to sleep until life_wake() sets its bit.
	var/life_awake = LIFE_SYS_ALL
	/// Life cycles run by this mob; drives system periods.
	var/life_cycle = 0
	/// Whole local biology cycles consumed, including accelerated catch-up steps.
	var/biological_cycle = 0
	/// LIFE_SET_* of the Life sequence this mob type runs.
	var/life_set = LIFE_SET_LIVING
	/// Lazy list of extra system types (component-provided) this mob carries.
	var/list/life_extra_systems
	/// TRUE while Life() runs; wakes raised meanwhile keep their bits awake.
	var/life_in_cycle = FALSE
	/// Bits woken during the current cycle.
	var/life_cycle_wakes = NONE
	/// Bits of the pending timed wake (life_wake_in()).
	var/life_timer_bits = NONE
	/// Sparse allocation, fixed 20 slots for the individual LIFE_SYS_* deadlines.
	var/list/life_timer_due
	/// world.time the pending timed wake fires.
	var/life_timer_at = 0
	/// TRUE while the scheduled frame consumes a due wake, avoiding a second frame.
	var/life_frame_running = FALSE

/mob/living/Life(seconds = LIFE_NOMINAL_SECONDS, profile = FALSE)
	set invisibility = INVISIBILITY_NONE
	set background = BACKGROUND_ENABLED

	var/datum/life_composition/comp = life_composition || recompose_life()
	var/datum/life_context/ctx = new(seconds, profile)
	ctx.stasis = body ? body.advance_stasis() : FALSE
	var/biology_steps = body ? body.biology_due : 1
	life_cycle++
	if(biology_steps > 0)
		biological_cycle++
	life_cycle_wakes = NONE
	life_in_cycle = TRUE
	// Gates always run while the mob runs: they decide what the rest of the cycle may do.
	var/awake = life_awake | LIFE_SYS_GATE
	var/considered = NONE
	var/busy = NONE
	var/halted = FALSE
	for(var/datum/life_system/S as anything in comp.ordered)
		var/bit = S.bit
		if(!(awake & bit))
			continue
		considered |= bit
		if((S.period > 1 && (life_cycle % S.period)) || (ctx.blocked & S.segment))
			if(life_system_wants_run(S))
				busy |= bit
			continue
		var/result
		S.telemetry_calls++
		var/dispatch_started_at = world.time
		var/dispatch_started_usage = TICK_USAGE_REAL
		SSreactor.prepare_scheduler_tick()
		var/observed_child_before = SSreactor.scheduler_tick_child_ms
		if(profile)
			var/profile_start = TICK_USAGE
			result = S.tick(src, ctx)
			if(result != LIFE_HALT && result != LIFE_SLEEP && life_system_wants_run(S))
				busy |= bit
			SSmobs.record_system_cost(S, TICK_USAGE - profile_start)
		else
			result = S.tick(src, ctx)
			if(result != LIFE_HALT && result != LIFE_SLEEP && life_system_wants_run(S))
				busy |= bit
		var/dispatch_exclusive_ms = max(TICK_DELTA_TO_MS(TICK_USAGE_REAL - dispatch_started_usage) - (SSreactor.scheduler_tick_child_ms - observed_child_before), 0)
		if(profile || dispatch_exclusive_ms >= SSreactor.scheduler_slow_call_ms || TICK_USAGE >= 50)
			SSreactor.observe_dispatch("life", S.type, type, null, dispatch_started_at, dispatch_exclusive_ms, "frame", 1, S.priority)
		if(result == LIFE_HALT)
			halted = TRUE
			break
		if(!(busy & bit))
			var/delay = S.rewake_delay(src)
			if(delay > 0)
				life_wake_in(bit, delay)
	// Faster local time repeats only audited biological work. A fresh context
	// re-evaluates gates and placement after each step; presentation and upkeep
	// remain once per real-time Life frame.
	if(!halted && !QDELETED(src) && biology_steps > 1)
		for(var/step in 2 to biology_steps)
			biological_cycle++
			var/datum/life_context/biology_ctx = new(LIFE_NOMINAL_SECONDS, profile)
			biology_ctx.biological_step = TRUE
			for(var/datum/life_system/B as anything in comp.ordered)
				if(!B.biology_catchup || !(awake & B.bit) || (B.period > 1 && (biological_cycle % B.period)))
					continue
				if(biology_ctx.blocked & B.segment)
					continue
				considered |= B.bit
				var/bio_result
				B.telemetry_calls++
				var/bio_started_at = world.time
				var/bio_started_usage = TICK_USAGE_REAL
				SSreactor.prepare_scheduler_tick()
				var/bio_child_before = SSreactor.scheduler_tick_child_ms
				if(profile)
					var/bio_profile_start = TICK_USAGE
					bio_result = B.tick_biology(src, biology_ctx)
					SSmobs.record_system_cost(B, TICK_USAGE - bio_profile_start)
				else
					bio_result = B.tick_biology(src, biology_ctx)
				var/bio_exclusive_ms = max(TICK_DELTA_TO_MS(TICK_USAGE_REAL - bio_started_usage) - (SSreactor.scheduler_tick_child_ms - bio_child_before), 0)
				if(profile || bio_exclusive_ms >= SSreactor.scheduler_slow_call_ms || TICK_USAGE >= 50)
					SSreactor.observe_dispatch("life", B.type, type, null, bio_started_at, bio_exclusive_ms, "biology catch-up", 1, B.priority)
				if(bio_result == LIFE_HALT || QDELETED(src))
					halted = TRUE
					break
				if(life_system_wants_run(B))
					busy |= B.bit
			if(halted)
				break
	life_in_cycle = FALSE
	if(halted || ctx.no_sleep || QDELETED(src))
		return
	// Bits no system in this composition carries (woken by a broad wake) have nothing to run.
	life_awake &= comp.bits
	var/sleeping = considered & ~(busy | life_cycle_wakes | LIFE_SYS_GATE)
	if(sleeping)
		life_awake &= ~sleeping
		if(GLOB.mob_hibernation_trace)
			log_runtime("MOB_HIBERNATE: [key_name(src)] ([type]) systems asleep: bits [sleeping], awake [life_awake]")
	if(!(life_awake & ~LIFE_SYS_GATE))
		life_hibernate("no awake systems")

/// TRUE when system `S` has work to do for this mob now. A dead mob never runs the
/// segments its gates block, so those systems never keep it awake.
/mob/living/proc/life_system_wants_run(datum/life_system/S)
	if(stat == DEAD && (S.segment & LIFE_SEGS_BLOCKED_WHEN_DEAD))
		return FALSE
	return !S.idle(src)

/// Rebuilds this mob's system list from its type and extras (species, plan or trait change).
/mob/living/proc/recompose_life()
	var/datum/life_composition/old = life_composition
	var/datum/life_composition/comp = compose_life_systems(src)
	if(comp == old)
		return comp
	life_composition = comp
	if(old)
		for(var/datum/life_system/S as anything in old.ordered)
			if(!(S in comp.ordered))
				S.detach(src)
	var/gained = NONE
	for(var/datum/life_system/S as anything in comp.ordered)
		if(!old || !(S in old.ordered))
			S.attach(src)
			gained |= S.bit
	if(old && gained)
		life_wake(gained, "recomposed")
	return comp

/// Drops the composition, detaching every system. Called from Destroy().
/mob/living/proc/clear_life_systems()
	if(life_composition)
		for(var/datum/life_system/S as anything in life_composition.ordered)
			S.detach(src)
	life_composition = null
	life_extra_systems = null
	life_timer_bits = NONE
	life_timer_at = 0
	life_timer_due = null
	if(life_hibernating)
		life_wake(NONE, "deleted", TRUE)

// --- Wake and hibernate -------------------------------------------------------------------
// The only two procs that change whether a mob runs. Every producer, the timers and the
// hibernation audit go through them (doc/mob_life_architecture.md §4.9).

/// Wakes the systems in `bits`. O(1). A hibernating mob rejoins SSmobs; unless `partial`,
/// it wakes whole, so every system gets one pass to re-check its sleep rule. `reason` is a
/// short constant string for the trace and the wake-reason summary.
/mob/living/proc/life_wake(bits = LIFE_SYS_ALL, reason, partial = FALSE)
	var/was_hibernating = life_hibernating
	if(life_in_cycle)
		life_cycle_wakes |= bits
	if(life_hibernating)
		if(!partial)
			bits = LIFE_SYS_ALL
		life_hibernating = FALSE
		life_last_time = 0 // the next Life() gets nominal seconds, not the whole nap
		if(reason != "timer")
			life_discard_elapsed_biology()
		var/slept_since = SSmobs.hibernating_mobs[src]
		SSmobs.hibernating_mobs -= src
		SSmobs.note_wake(reason)
		if(GLOB.mob_hibernation_trace)
			log_runtime("MOB_HIBERNATE: [key_name(src)] ([type]) woke ([reason || "unspecified"]) after [DisplayTimeText(world.time - slept_since)], bits [bits]; [length(SSmobs.hibernating_mobs)] hibernating")
	life_awake |= bits
	if(was_hibernating && !life_frame_running)
		var/datum/object_model/behaviour_runtime/R = om_state?.behaviour_runtime
		if(R?.run_last)
			R.run_last -= /datum/object_model/behaviour/living_life_frame
		om_behaviour_wake(src, /datum/object_model/behaviour/living_life_frame, reason || "life wake")

/// A paused or externally woken mob resumes without simulating its entire nap.
/mob/living/proc/life_discard_elapsed_biology()
	if(!body)
		return
	var/datum/object_model/clock_state/biology_clock = om_state?.clock_states?[/datum/object_model/clock_domain/biology]
	body.stasis_last_virtual = biology_clock?.settle()
	body.stasis_clock = 0

/// Takes a mob with no awake systems out of the SSmobs run until life_wake(). Returns TRUE
/// when the mob now hibernates.
/mob/living/proc/life_hibernate(reason)
	if(life_hibernating || !GLOB.mob_hibernation_enabled || QDELETED(src))
		return FALSE
	life_hibernating = TRUE
	SSmobs.hibernating_mobs[src] = world.time
	SSmobs.hibernations++
	if(GLOB.mob_hibernation_trace)
		log_runtime("MOB_HIBERNATE: [key_name(src)] ([type]) hibernating ([reason || "unspecified"]); [length(SSmobs.hibernating_mobs)] hibernating")
	return TRUE

/// Wakes each requested system bit after `delay`. One wheel token serves the
/// earliest deadline, while later systems retain their own due times.
/mob/living/proc/life_wake_in(bits, delay)
	if(!bits || delay <= 0)
		return
	var/at = world.time + delay
	if(!life_timer_due)
		life_timer_due = list()
		life_timer_due.len = 20
	var/bit = 1
	for(var/index in 1 to 20)
		if(bits & bit)
			var/old_due = life_timer_due[index]
			if(isnull(old_due) || at < old_due)
				life_timer_due[index] = at
		bit *= 2
	life_timer_bits |= bits
	if(!life_timer_at || at < life_timer_at)
		life_timer_at = at
		om_behaviour_due_at(src, /datum/object_model/behaviour/living_life_frame, at)

/// Consumes only due systems and re-arms the next per-bit deadline.
/mob/living/proc/life_timer_fired()
	var/due_bits = NONE
	var/remaining_bits = NONE
	var/next_at = 0
	var/bit = 1
	for(var/index in 1 to 20)
		var/at = life_timer_due?[index]
		if(!isnull(at))
			if(at <= world.time)
				due_bits |= bit
				life_timer_due[index] = null
			else
				remaining_bits |= bit
				if(!next_at || at < next_at)
					next_at = at
		bit *= 2
	life_timer_bits = remaining_bits
	life_timer_at = next_at
	if(next_at)
		om_behaviour_due_at(src, /datum/object_model/behaviour/living_life_frame, next_at)
	if(due_bits)
		life_wake(due_bits, "timer", TRUE)

/// The hibernation audit's check: the first sleeping system whose sleep rule no longer
/// holds, or null. A hit means a producer forgot to call life_wake().
/mob/living/proc/life_missed_wake()
	var/datum/life_composition/comp = life_composition
	if(!comp)
		return null
	var/awake = life_hibernating ? NONE : life_awake
	for(var/datum/life_system/S as anything in comp.ordered)
		if(S.bit == LIFE_SYS_GATE || (awake & S.bit))
			continue
		if(life_system_wants_run(S))
			return S
	return null

/// Gives this mob an extra (component-provided) system.
/mob/living/proc/add_life_system(path)
	if(path in life_extra_systems)
		return
	LAZYADD(life_extra_systems, path)
	if(life_composition)
		recompose_life()
	var/datum/life_system/S = get_life_system(path)
	life_wake(S?.bit, "system added")

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
// Code outside Life() asks for an immediate HUD or vision refresh through these. Living mobs
// run their HUD and Senses systems; other mobs keep the base behaviour.

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
// Hooks on /mob that the generic mob code calls; living mobs turn them into life_wake().

/// Stun, weaken, paralysis, sleep, confusion and blindness setters call this.
/mob/proc/on_status_counter_changed(reason)
	return

/mob/living/on_status_counter_changed(reason)
	life_wake(LIFE_WAKE_STATUS, reason)

/// A client logged into or out of this mob: the HUD, senses and client systems restart.
/mob/living/proc/on_client_changed(reason)
	life_wake(LIFE_SYS_ALL, reason)
	om_behaviour_start(src)
	om_behaviour_refresh(src)
	om_behaviour_wake(src, /datum/object_model/behaviour/living_afk)
	om_behaviour_wake(src, /datum/object_model/behaviour/living_ambience)

/// Something was equipped or unequipped.
/mob/proc/on_equipment_changed()
	return

/mob/living/on_equipment_changed()
	body?.invalidate(BODY_DIRTY_ARMOR)
	life_wake(LIFE_WAKE_EQUIPMENT, "equipment")
