// The Life scheduler (doc/mob_life_architecture.md §4.3). /mob/living/Life() is the only Life()
// for living mobs: it runs the mob's composed life systems in order. No behaviour lives here.

/mob
	/// world.time of this mob's previous Life() call; SSmobs derives elapsed seconds from it.
	var/life_last_time = 0
	/// TRUE while SSmobs skips this mob because nothing is awake (MOB_HIBERNATION_ENABLED).
	var/life_hibernating = FALSE

/mob/living
	/// Shared, ordered systems for this mob's composition key. Never mutated per mob.
	var/datum/life_composition/life_composition
	/// LIFE_SYS_* bits of the systems that want to run. All awake until systems gain sleep rules.
	var/life_awake = LIFE_SYS_ALL
	/// Life cycles run by this mob; drives system periods.
	var/life_cycle = 0
	/// LIFE_SET_* of the Life sequence this mob type runs.
	var/life_set = LIFE_SET_LIVING
	/// Lazy list of extra system types (component-provided) this mob carries.
	var/list/life_extra_systems

/mob/living/Life(seconds = LIFE_NOMINAL_SECONDS, profile = FALSE)
	set invisibility = INVISIBILITY_NONE
	set background = BACKGROUND_ENABLED

	var/datum/life_composition/comp = life_composition || recompose_life()
	var/datum/life_context/ctx = new(seconds, profile)
	ctx.stasis = body ? body.advance_stasis() : FALSE
	life_cycle++
	for(var/datum/life_system/S as anything in comp.ordered)
		if(!(life_awake & S.bit))
			continue
		if(S.period > 1 && (life_cycle % S.period))
			continue
		if(ctx.blocked & S.segment)
			continue
		var/result
		if(profile)
			var/profile_start = TICK_USAGE
			result = S.tick(src, ctx)
			SSmobs.record_system_cost(S, TICK_USAGE - profile_start)
		else
			result = S.tick(src, ctx)
		if(result == LIFE_HALT)
			break
		if(result == LIFE_SLEEP)
			life_awake &= ~S.bit
	if(!life_awake)
		SSmobs.hibernate(src)

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
	for(var/datum/life_system/S as anything in comp.ordered)
		if(!old || !(S in old.ordered))
			S.attach(src)
	return comp

/// Drops the composition, detaching every system. Called from Destroy().
/mob/living/proc/clear_life_systems()
	if(life_composition)
		for(var/datum/life_system/S as anything in life_composition.ordered)
			S.detach(src)
	life_composition = null
	life_extra_systems = null
	if(life_hibernating)
		SSmobs.wake_mob(src)

/// Wakes the systems in `bits`. O(1); a hibernating mob rejoins SSmobs.
/mob/living/proc/wake(bits = LIFE_SYS_ALL)
	life_awake |= bits
	if(life_hibernating)
		SSmobs.wake_mob(src)

/// Gives this mob an extra (component-provided) system.
/mob/living/proc/add_life_system(path)
	if(path in life_extra_systems)
		return
	LAZYADD(life_extra_systems, path)
	if(life_composition)
		recompose_life()
	var/datum/life_system/S = get_life_system(path)
	wake(S?.bit)

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
