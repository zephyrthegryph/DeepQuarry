// Mob Life on object-model pipelines (doc/rewrite/life_on_om.md).
//
// Life is declarations: a pipeline of /datum/om/stage/life stages, a frame with the old gates
// as facts, and the producers that raise mob channels. When stages run, idle, wake and park is
// the core pipeline runner's business (code/datums/om/pipeline.dm); nothing here decides it.

/datum/om/decl/living
	of = /mob/living
	behaviours = list(/datum/om/pipeline/life)

/datum/om/decl/observer
	of = /mob/observer
	behaviours = list(/datum/om/behaviour/observer_upkeep)

/// One Life frame per LIFE_CYCLE of (fixed-step) time. Parked while every stage is idle, and at
/// relevance NONE: a low-priority mob on a z-level with no living player (life_update_relevance()).
/datum/om/pipeline/life
	name = "life"
	every = LIFE_CYCLE
	step_interval = LIFE_CYCLE_SECONDS
	max_catchup = LIFE_MAX_CATCHUP
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	relevance = list(OM_PARK, null, null, null)
	stages = list(/datum/om/stage/life)
	frame_type = /datum/om/frame/life
	wake_all = LIFE_WAKE_ALL
	park_after = LIFE_PARK_AFTER
	profile_stride = LIFE_PROFILE_STRIDE

/// Ghosts, AI eyes and the blob overmind: their old Life() upkeep.
/datum/om/behaviour/observer_upkeep
	name = "observer upkeep"
	every = OBSERVER_UPKEEP_INTERVAL
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

/datum/om/behaviour/observer_upkeep/tick(mob/observer/O, dt)
	O.upkeep()

/mob/living
	/// LIFE_SET_* of the Life sequence this mob type runs.
	var/life_set = LIFE_SET_LIVING
	/// The z-level whose presence lists this low-priority mob (0: none).
	var/tmp/life_z = 0

// --- Relevance: low-priority mobs on z-levels without players -----------------------------------
// The old frame returned early for a low_priority mob on a z-level with no living player. Now a mob
// is relevant (RELEVANCE_NEAR) while something holds it: a mob that isn't low priority holds it on
// itself, and a z-level's presence holds it on the low-priority mobs there while a living player
// is on that z-level. At RELEVANCE_NONE the life pipeline parks (its relevance list), so nothing
// is tested per frame.

/// z -> /datum/life_z_presence.
GLOBAL_LIST_EMPTY(life_z_presence)

/datum/life_z_presence
	var/z
	var/occupied = FALSE
	var/list/members = list()

/proc/life_z_presence(z)
	RETURN_TYPE(/datum/life_z_presence)
	var/list/all = GLOB.life_z_presence
	if(length(all) < z)
		all.len = z
	var/datum/life_z_presence/P = all[z]
	if(!P)
		P = new
		P.z = z
		P.occupied = z <= length(GLOB.living_players_by_zlevel) && length(GLOB.living_players_by_zlevel[z])
		all[z] = P
	return P

/// A living player arrived on or left z-level `z`.
/proc/life_z_occupancy_changed(z)
	if(!z || z > length(GLOB.life_z_presence))
		return
	var/datum/life_z_presence/P = GLOB.life_z_presence[z]
	if(!P)
		return
	var/occupied = z <= length(GLOB.living_players_by_zlevel) && length(GLOB.living_players_by_zlevel[z]) > 0
	if(occupied == P.occupied)
		return
	P.occupied = occupied
	for(var/mob/living/L as anything in P.members)
		if(occupied)
			om_observe(L, P, RELEVANCE_NEAR)
		else
			om_unobserve(L, P)

/// Re-decides who keeps this mob relevant: itself, or its z-level's presence.
/mob/living/proc/life_update_relevance()
	if(QDELETED(src))
		return
	if(!low_priority)
		life_leave_z()
		om_observe(src, src, RELEVANCE_NEAR)
		return
	om_unobserve(src, src)
	var/new_z = loc ? get_z(src) : 0
	if(new_z == life_z)
		return
	life_leave_z()
	if(!new_z)
		return
	var/datum/life_z_presence/P = life_z_presence(new_z)
	rel_add(P, nameof(P.members), src)
	life_z = new_z
	if(P.occupied)
		om_observe(src, P, RELEVANCE_NEAR)

/mob/living/proc/life_leave_z()
	if(!life_z)
		return
	var/datum/life_z_presence/P = GLOB.life_z_presence[life_z]
	life_z = 0
	if(P)
		rel_remove(P, nameof(P.members), src)
		om_unobserve(src, P)

/mob/proc/set_low_priority(value)
	low_priority = value

/mob/living/set_low_priority(value)
	..()
	life_update_relevance()

/mob/living/onTransitZ(old_z, new_z)
	..()
	if(low_priority)
		life_update_relevance()

// --- Public refresh entry points --------------------------------------------------------------
// Code outside Life asks for an immediate HUD or vision refresh through these. Living mobs run
// life_hud() / life_vision() (the handlers of their HUD and sight reactions, living_systems.dm) now;
// other mobs keep the base behaviour.

/// Refreshes the player HUD now. Returns FALSE when there is no HUD to refresh.
/mob/proc/refresh_hud()
	return hud_available()

/// TRUE when this mob has a client HUD that no component has taken over.
/mob/proc/hud_available()
	if(!client)
		return FALSE
	if(OM_EMIT(src, /datum/om/event/before/mob_handle_hud) & HUD_EVENT_HANDLED)
		return FALSE
	return TRUE

/mob/living/refresh_hud()
	return life_hud()

/// Recomputes sight flags (SEE_TURFS, see_in_dark, ...) now.
/mob/proc/refresh_vision()
	OM_EMIT(src, /datum/om/event/mob_handle_vision)

/mob/living/refresh_vision()
	life_vision()

// --- Producers ----------------------------------------------------------------------------
// Hooks on /mob that the generic mob code calls; living mobs raise the matching channel.

/// A client logged into or out of this mob: the HUD, senses and client stages restart.
/mob/living/proc/on_client_changed(reason)
	changed(src, CHANGE_MOB_CLIENT)
	PUBLISH_CHANGE(src, MOB_KEY_CLIENT)

/// An admin edit of a plain var (one with no setter) announces nothing, so the canmove, HUD and sight reactions
/// would keep their stale result: status is the key all three read.
/mob/living/vv_edit_var(var_name, var_value)
	. = ..()
	if(.)
		PUBLISH_CHANGE(src, MOB_KEY_STATUS)

/// Something was equipped or unequipped.
/mob/proc/on_equipment_changed()
	return

/mob/living/on_equipment_changed()
	body?.invalidate(BODY_DIRTY_ARMOR)
	changed(src, CHANGE_MOB_EQUIPMENT)
	PUBLISH_CHANGE(src, MOB_KEY_EQUIPMENT)
