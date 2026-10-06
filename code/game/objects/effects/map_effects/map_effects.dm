// These are objects you can use inside special maps (like PoIs), or for adminbuse.
// Players cannot see or interact with these.
/obj/effect/map_effect
	resistance_flags = BOMB_PROOF
	anchored = TRUE
	invisibility = INVISIBILITY_BADMIN // So a badmin can go view these by changing their see_invisible.
	icon = 'icons/effects/map_effects.dmi'

	// Map effects are ambient: the proximity tracker (code/controllers/subsystems/proximity.dm) holds them relevant while a client eye is near.
	proximity_tracked = TRUE
	/// If true, the effect is held relevant everywhere: it runs even with nobody around to see it.
	var/always_run = FALSE

// ALLOW(init/INSTANCE_STATE): an always_run effect holds itself relevant from the start
/obj/effect/map_effect/Initialize(mapload)
	. = ..()
	if(always_run)
		hold(src, STAT_RELEVANCE, RELEVANCE_NEAR, src)

/obj/effect/map_effect/singularity_pull()
	return

/obj/effect/map_effect/singularity_act()
	return

// Base type for effects that run on variable intervals.
/obj/effect/map_effect/interval
	var/interval_lower_bound = 5 SECONDS // Lower number for how often the map_effect will trigger.
	var/interval_upper_bound = 5 SECONDS // Higher number for above.

/// Runs trigger() every interval while a client is near (STAT_RELEVANCE); parks the rest of the time.
CAPABILITIES(/obj/effect/map_effect/interval)
	every(PROC_REF(interval_delay), then(PROC_REF(interval_fire)), when = STAT_RELEVANCE)

// Override this for the specific thing to do.
/obj/effect/map_effect/interval/proc/trigger()
	return

/// The deciseconds to the next trigger.
/obj/effect/map_effect/interval/proc/interval_delay(datum/act/A)
	return rand(interval_lower_bound, interval_upper_bound)

/obj/effect/map_effect/interval/proc/interval_fire(datum/act/A)
	trigger()

// Helper proc to optimize the use of effects by making sure they do not run if nobody is around to perceive it.
/proc/check_for_player_proximity(atom/proximity_to, radius = 12, ignore_ghosts = FALSE, ignore_afk = TRUE)
	if(!proximity_to)
		return FALSE

	for(var/thing in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		var/mob/M = thing // Avoiding typechecks for more speed, REGISTRY_MEMBERS(REGISTRY_PLAYERS) will only contain mobs anyways.
		if(ignore_ghosts && isobserver(M))
			continue
		if(ignore_afk && M.client && M.client.is_afk(5 MINUTES))
			continue
		if(M.z == proximity_to.z && get_dist(M, proximity_to) <= radius)
			return TRUE
	return FALSE
