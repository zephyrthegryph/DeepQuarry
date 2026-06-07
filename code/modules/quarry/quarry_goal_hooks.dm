// Runtime hooks that drive stabilization-goal progress.
//
// Detection is event-based: goals tick when the *work* happens (mining
// a wall, pumping a pool, venting a gas pocket, killing a mob, walking
// a tile), not when the resulting items arrive at the surface. This
// means players can't cheese ore goals by riding the elevator up and
// down with the same haul, and matches the engineering-loop intent
// ("you did the work, you get the credit").
//
// Event sources:
//   - Mineral wall drilled       -> dispatch on_node_mined(name, type)
//   - Pool reagent pumped        -> dispatch on_reagent_pumped(id, units)
//   - Gas pocket vented          -> dispatch on_gas_vented(id, moles)
//   - Mob death                  -> dispatch on_mob_killed(mob)
//   - Player turf entry          -> dispatch on_tile_visited(turf)

// Find the loaded quarry layer for a given z, or null if z isn't a
// procedural quarry layer (the surface station z, an unrelated z, etc).
/datum/controller/subsystem/quarry/proc/layer_at_z(z)
	if(!isnum(z) || z < 1)
		return null
	for(var/key in layers)
		var/datum/quarry_layer/L = layers[key]
		if(L?.loaded && L.z == z)
			return L
	return null


// Dispatch helpers. Each routes the event to the layer that owns the
// z it happened on, then walks that layer's goals. recompute is
// fired so a satisfied goal can advance the unlock state immediately.

/datum/controller/subsystem/quarry/proc/on_layer_node_mined(z, mineral_name, item_type)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(!L || !length(L.goals))
		return
	for(var/datum/quarry_goal/G as anything in L.goals)
		G.on_node_mined(mineral_name, item_type)
	recompute_unlocked_depth()

/datum/controller/subsystem/quarry/proc/on_layer_reagent_pumped(z, reagent_id, units)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(!L)
		return
	// Pumping is noise. emit_noise also bumps danger so we don't
	// double-count.
	var/turf/origin = locate(rand(1, QUARRY_LAYER_SIZE), rand(1, QUARRY_LAYER_SIZE), z)
	// Actually, the pump source matters — find a /turf with a pump
	// machine on it and use that as origin so the alert centers on
	// the noise source.
	for(var/obj/machinery/pump/P in GLOB.machines)
		if(P.z == z && P.on)
			origin = get_turf(P)
			break
	if(origin)
		emit_noise(origin, QUARRY_NOISE_PUMP, origin)
	if(!length(L.goals))
		return
	for(var/datum/quarry_goal/G as anything in L.goals)
		G.on_reagent_pumped(reagent_id, units)
	recompute_unlocked_depth()

/datum/controller/subsystem/quarry/proc/on_layer_gas_vented(z, gas_id, moles)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(!L)
		return
	// Gas vents are loud. emit_noise also handles the danger bump.
	// The vent already emits its gas at a specific turf — we don't
	// have a handle here, so use a layer-relative anchor (the bay) as
	// a fallback. In practice the vent's noise hook fires from
	// raw_chem_vent.dm directly.
	if(!length(L.goals))
		return
	for(var/datum/quarry_goal/G as anything in L.goals)
		G.on_gas_vented(gas_id, moles)
	recompute_unlocked_depth()


// Hook for mob death. Quarry layer mobs only — guard on z so we don't
// pay the lookup cost for every other mob in the world.
/mob/living/death(gibbed, deathmessage, show_dead_message)
	. = ..()
	if(!SSquarry || !z)
		return
	var/datum/quarry_layer/L = SSquarry.layer_at_z(z)
	if(!L)
		return
	// Mob death is noise. Death cries summon nearby kin.
	var/turf/here = get_turf(src)
	if(here)
		SSquarry.emit_noise(here, QUARRY_NOISE_MOBDEATH, src)
	// If the stalker died, free the slot so the event can re-roll.
	// The body itself is the tell — no need to broadcast it.
	if(L.active_stalker == src)
		L.active_stalker = null
	if(!length(L.goals))
		return
	for(var/datum/quarry_goal/G as anything in L.goals)
		G.on_mob_killed(src)
	SSquarry.recompute_unlocked_depth()


// Hook for player turf entry. Only fires on mineable cave floors that
// belong to a quarry layer — the elevator bay, station rooms, and
// corridors don't count. Single-player layers see one trigger per new
// tile per traversal; multi-player layers see triggers from each
// player but the goal datum dedupes via its seen_tiles set.
/turf/simulated/mineral/cave/quarry/Entered(atom/movable/AM, atom/old_loc)
	. = ..()
	if(!ismob(AM) || !SSquarry)
		return
	var/mob/M = AM
	// Only count player-controlled living mobs. AI mobs wandering
	// around shouldn't be filling in the player's map for them, and
	// neither should observers/ghosts who can phase through walls.
	if(!M.client)
		return
	if(istype(M, /mob/observer))
		return
	if(!isliving(M))
		return
	var/datum/quarry_layer/L = SSquarry.layer_at_z(z)
	if(!L || !length(L.goals))
		return
	for(var/datum/quarry_goal/G as anything in L.goals)
		G.on_tile_visited(src)
	SSquarry.recompute_unlocked_depth()
