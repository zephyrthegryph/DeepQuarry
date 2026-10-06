// Mob Life: membership in the Life sequence, relevance, and the producers that raise mob channels.
//
// Life is a kernel sequence (/datum/sequence/life, life_sequence.dm): steps are procs on the mob types, declared in
// life_steps() (life_steps.dm). When steps run, sleep, wake and park is the kernel's business
// (code/controllers/kernel/sequence.dm); nothing here decides it.

/// A living mob runs Life while it is in the world.
/mob/living/on_materialize()
	. = ..()
	seq_start(src, /datum/sequence/life)
	// Trait states attached before the mob was live (species and trait setup in Initialize) contribute their steps now.
	for(var/datum/trait_state/S as anything in trait_states)
		if(length(S.life_steps()))
			seq_extra_add(src, /datum/sequence/life, S)

/mob/living/on_dematerialize()
	seq_stop(src, /datum/sequence/life)
	return ..()

/// Ghosts, AI eyes and the blob overmind: their old Life() upkeep, once a Life cycle while the round runs (its every() in
/// CAPABILITIES(/mob/observer)).
/mob/observer/proc/upkeep_step(datum/act/timer/A)
	if((RUNLEVEL_GAME | RUNLEVEL_POSTGAME) & (1 << (Kernel.current_runlevel - 1)))
		upkeep()

/mob/living
	/// LIFE_SET_* of the Life sequence this mob type runs.
	var/life_set = LIFE_SET_LIVING
	/// The z-level whose presence lists this low-priority mob (0: none).
	var/tmp/life_z = 0

// --- Relevance: low-priority mobs on z-levels without players -----------------------------------
// The old frame returned early for a low_priority mob on a z-level with no living player. Now a mob
// is relevant (RELEVANCE_NEAR) while something holds it: a mob that isn't low priority holds it on
// itself, and a z-level's presence holds it on the low-priority mobs there while a living player
// is on that z-level. Below RELEVANCE_NEAR the Life sequence takes it out of the sweep (min_relevance),
// so nothing is tested per frame.

/// z -> /datum/life_z_presence.
GLOBAL_LIST_EMPTY(life_z_presence)

/datum/life_z_presence
	var/z
	var/occupied = FALSE
	var/list/members

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

// There is no manual HUD or sight refresh: the HUD, sight and canmove passes are on_change() reactions
// (living_systems.dm) whose reads are generated from what their procs read (code/_generated/reads.dm), so a change to
// any input runs them. Code that changes something they show writes it through its setter or publishes the key that
// covers it (MOB_KEY_*). tools/ci/sys_rules/presentation.py rejects a direct call of the passes from content.

/// TRUE when this mob has a client HUD that no component has taken over.
/mob/proc/hud_available()
	if(!client)
		return FALSE
	var/datum/act/draw_hud/draw = ACT_TRY(src, draw_hud)
	if(!draw)
		return FALSE
	act_cancel(draw)
	return TRUE

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
