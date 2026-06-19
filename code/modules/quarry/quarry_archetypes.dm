// The ten concrete floor archetypes.
//
// Each pairs an objective (build_goals) with a clear condition (the
// inherited is_cleared: all objective goals satisfied) and an environmental
// treatment (on_layer_generated places objective structures; ambient_tick
// applies ongoing pressure while uncleared). Content (ore/mobs/biome) is
// still rolled from the layer's config independently — the archetype only
// decides what the floor *demands*.
//
// Families (for the wheel's anti-repeat spacing):
//   extraction | atmos | thermal | dark | bio | combat | logistics |
//   power | siege


// === shared helpers ==================================================

// Live (non-resolved, non-deleted) objective structures on a layer,
// lazily scanned once per load and cached on L.objectives. Pruned of dead
// refs on each call. Used by ambient_tick so it never rescans the z grid.
/proc/_quarry_get_objectives(datum/quarry_layer/L)
	if(isnull(L.objectives))
		L.objectives = list()
		if(L.loaded && L.z)
			for(var/turf/T as anything in block(locate(1, 1, L.z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, L.z)))
				for(var/obj/structure/quarry_objective/O in T)
					L.objectives += O
	// Prune dead/resolved refs into a fresh list (never mutate the list
	// being iterated).
	var/list/live = list()
	for(var/obj/structure/quarry_objective/O in L.objectives)
		if(QDELETED(O) || O.resolved)
			continue
		live += O
	L.objectives = live
	return live

// Place `count` objective structures of obj_type on random eligible
// floors (off the bay, unoccupied, outside player safe rooms) and
// register them on L.objectives. Returns the number placed.
/proc/_quarry_scatter_objectives(datum/quarry_layer/L, obj_type, count)
	if(!L?.loaded || !ispath(obj_type, /obj/structure/quarry_objective) || count <= 0)
		return 0
	var/list/bay = SSquarry.elevator?.bay_at(L.depth)
	var/list/cand = list()
	for(var/turf/simulated/floor/T in block(locate(1, 1, L.z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, L.z)))
		if(bay && (T in bay))
			continue
		if(length(T.contents))
			continue
		if(_quarry_tile_is_safe(T))
			continue
		cand += T
	if(isnull(L.objectives))
		L.objectives = list()
	var/placed = 0
	while(placed < count && length(cand))
		var/turf/T = pick(cand)
		cand -= T
		var/obj/structure/quarry_objective/O = new obj_type(T)
		L.objectives += O
		placed++
	return placed

// Scatter `count` objective structures and pin the matching neutralize
// goal's target to however many actually got placed, so a small cave can
// never leave a floor with more required objectives than exist (which
// would be unclearable). Returns the number placed.
/proc/_quarry_setup_neutralize(datum/quarry_layer/L, obj_type, tag, count)
	var/placed = _quarry_scatter_objectives(L, obj_type, count)
	for(var/datum/quarry_goal/neutralize/G in L.goals)
		if(G.objective_tag == tag)
			G.target = placed
			break
	return placed

// A random walkable floor on the layer that isn't the bay or occupied.
/proc/_quarry_random_layer_floor(datum/quarry_layer/L)
	if(!L?.loaded)
		return null
	var/list/bay = SSquarry.elevator?.bay_at(L.depth)
	var/tries = 30
	while(tries-- > 0)
		var/turf/simulated/floor/T = locate(rand(2, QUARRY_LAYER_SIZE - 1), rand(2, QUARRY_LAYER_SIZE - 1), L.z)
		if(!istype(T))
			continue
		if(bay && (T in bay))
			continue
		if(length(T.contents))
			continue
		if(_quarry_tile_is_safe(T))
			continue
		return T
	return null

// Live mobs currently on a layer's z.
/proc/_quarry_layer_living(datum/quarry_layer/L)
	var/list/out = list()
	if(!L?.z)
		return out
	for(var/mob/living/M in GLOB.living_mob_list)
		if(M.z == L.z)
			out += M
	return out

// Apply `amount` environmental damage to every living mob on the layer,
// except those sheltering in a powered safe room (so Engineering building
// a safe haven actually matters). damtype: "fire" (heat/cold), "tox"
// (contagion), or "brute".
/proc/_quarry_environmental_damage(datum/quarry_layer/L, amount, damtype = "fire")
	if(amount <= 0)
		return
	for(var/mob/living/M as anything in _quarry_layer_living(L))
		if(_quarry_tile_is_safe(get_turf(M)))
			continue
		switch(damtype)
			if("tox")
				M.adjustToxLoss(amount)
			if("brute")
				M.adjustBruteLoss(amount)
			else
				M.adjustFireLoss(amount)

// Spawn up to `n` config-appropriate hostile mobs on/around a tile.
/proc/_quarry_archetype_spawn_mobs(datum/quarry_layer/L, turf/origin, n)
	if(!istype(origin) || n <= 0)
		return
	var/list/table = L.config?.default_mob_table
	if(!length(table))
		return
	var/list/spots = list(origin)
	for(var/dir in GLOB.cardinal)
		var/turf/T = get_step(origin, dir)
		if(istype(T, /turf/simulated/floor) && !length(T.contents))
			spots += T
	var/spawned = 0
	while(spawned < n && length(spots))
		var/turf/T = spots[1]
		spots.Cut(1, 2)
		var/mob_type = pickweight(table)
		if(mob_type)
			new mob_type(T)
		spawned++


// === #1 Gas flooded ==================================================
//
// Mining/seepage fills the level with choking gas. Seal the fissures
// (Engineering) while someone keeps the air survivable and the crew
// alive (Atmos/Medical). Unsealed fissures keep venting real gas.
/datum/quarry_floor_archetype/gas
	name = "Sour Vein"
	desc = "Choking gas seeps from cracked seams. Seal the fissures before the level fills."
	family = "atmos"
	depth_weights = list("3+" = 35)
	var/fissure_count = 6

/datum/quarry_floor_archetype/gas/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/neutralize/G = new
	G.name = "Seal the Fissures"
	G.description = "Pack and seal [fissure_count] gas fissures to make the level breathable."
	G.objective_tag = "seal"
	G.target = fissure_count
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/gas/on_layer_generated(datum/quarry_layer/L)
	_quarry_setup_neutralize(L, /obj/structure/quarry_objective/gas_fissure, "seal", fissure_count)

/datum/quarry_floor_archetype/gas/ambient_tick(datum/quarry_layer/L, seconds)
	// Normalize per-tick magnitudes against the current wait (see
	// QUARRY_TICK_NORMALIZE_SECONDS): scale is 1 at a 30s wait so balance
	// is unchanged today, but the hazard no longer depends on the period.
	var/scale = seconds / QUARRY_TICK_NORMALIZE_SECONDS
	var/list/objs = _quarry_get_objectives(L)
	var/leaks = 0
	for(var/obj/structure/quarry_objective/gas_fissure/F in objs)
		var/turf/T = get_turf(F)
		if(!istype(T, /turf/simulated))
			continue
		var/datum/gas_mixture/leak = new
		leak.adjust_gas_temp(GAS_PHORON, 2 * scale, T20C + 40)
		leak.adjust_gas_temp(GAS_CO2, 3 * scale, T20C + 40)
		T.assume_air(leak)
		leaks++
	if(leaks)
		SSquarry.add_layer_danger(L, 0.5 * leaks * scale)


// === #2 Lava / high heat =============================================
//
// Molten vents push killing heat. Cool them down. Deep-only.
/datum/quarry_floor_archetype/lava
	name = "The Burn"
	desc = "Molten vents bake the level. Cool them before the heat does for you."
	family = "thermal"
	depth_weights = list("8+" = 30)
	var/vent_count = 6

/datum/quarry_floor_archetype/lava/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/neutralize/G = new
	G.name = "Cool the Vents"
	G.description = "Cool [vent_count] lava vents until the level is workable."
	G.objective_tag = "cool"
	G.target = vent_count
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/lava/on_layer_generated(datum/quarry_layer/L)
	_quarry_setup_neutralize(L, /obj/structure/quarry_objective/lava_vent, "cool", vent_count)

/datum/quarry_floor_archetype/lava/ambient_tick(datum/quarry_layer/L, seconds)
	var/list/objs = _quarry_get_objectives(L)
	var/list/vents = list()
	for(var/obj/structure/quarry_objective/lava_vent/V in objs)
		vents += V
	if(!length(vents))
		return
	var/scale = seconds / QUARRY_TICK_NORMALIZE_SECONDS
	var/open = length(vents)
	SSquarry.add_layer_danger(L, 0.4 * open * scale)
	// Oven heat across the whole level, scaled by how many vents are
	// still open. Safe rooms (powered APC) shelter from it.
	_quarry_environmental_damage(L, (2 + 1.2 * open) * scale, "fire")
	// Lethal heat right next to an un-cooled vent — the "molten" zone.
	for(var/obj/structure/quarry_objective/lava_vent/V as anything in vents)
		for(var/mob/living/M in range(1, V))
			if(_quarry_tile_is_safe(get_turf(M)))
				continue
			M.adjustFireLoss(10 * scale)


// === #3 Ice / high cold ==============================================
//
// A frozen stratum. Heat the chokes through to make it liveable.
/datum/quarry_floor_archetype/ice
	name = "Frozen Hollows"
	desc = "Killing cold and frozen chokes. Heat the level through to work it."
	family = "thermal"
	depth_weights = list("6+" = 30)
	var/choke_count = 6

/datum/quarry_floor_archetype/ice/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/neutralize/G = new
	G.name = "Thaw the Chokes"
	G.description = "Heat [choke_count] ice chokes to clear and warm the level."
	G.objective_tag = "heat"
	G.target = choke_count
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/ice/on_layer_generated(datum/quarry_layer/L)
	_quarry_setup_neutralize(L, /obj/structure/quarry_objective/ice_choke, "heat", choke_count)

/datum/quarry_floor_archetype/ice/ambient_tick(datum/quarry_layer/L, seconds)
	var/list/objs = _quarry_get_objectives(L)
	var/frozen = 0
	for(var/obj/structure/quarry_objective/ice_choke/C in objs)
		frozen++
	if(!frozen)
		return
	var/scale = seconds / QUARRY_TICK_NORMALIZE_SECONDS
	SSquarry.add_layer_danger(L, 0.4 * frozen * scale)
	// Biting cold scaled by remaining chokes — reads as fireloss
	// (frostbite) so it's universal across mob types. Heating the chokes
	// (clearing them) warms the level back up. Safe rooms shelter from it.
	_quarry_environmental_damage(L, (2 + 1.0 * frozen) * scale, "fire")


// === #4 Darkness =====================================================
//
// Pitch black with photophobic fauna. Raise and power lighting pylons
// (Engineering) and hold them (Security) — the dark keeps spawning
// terrors near anything not yet lit.
/datum/quarry_floor_archetype/dark
	name = "The Lightless Deep"
	desc = "Total dark, and things that hate the light. Raise the pylons and hold them."
	family = "dark"
	depth_weights = list("4+" = 28)
	var/pylon_count = 5
	var/spawn_cooldown = 40 SECONDS

/datum/quarry_floor_archetype/dark/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/neutralize/G = new
	G.name = "Light the Outposts"
	G.description = "Power [pylon_count] lighting pylons to push back the dark."
	G.objective_tag = "light"
	G.target = pylon_count
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/dark/on_layer_generated(datum/quarry_layer/L)
	_quarry_setup_neutralize(L, /obj/structure/quarry_objective/dark_pylon, "light", pylon_count)

/datum/quarry_floor_archetype/dark/ambient_tick(datum/quarry_layer/L, seconds)
	// The dark hunts anything not yet lit: while pylons remain dark, send
	// a terror at the crew on a throttle.
	var/list/objs = _quarry_get_objectives(L)
	var/unlit = 0
	for(var/obj/structure/quarry_objective/dark_pylon/P in objs)
		unlit++
	if(!unlit)
		return
	SSquarry.add_layer_danger(L, 0.3 * unlit * (seconds / QUARRY_TICK_NORMALIZE_SECONDS))
	if(world.time < L.last_danger_wave + spawn_cooldown)
		return
	var/turf/T = _quarry_random_layer_floor(L)
	if(T)
		L.last_danger_wave = world.time
		_quarry_archetype_spawn_mobs(L, T, rand(1, 2))


// === #5 Virus ========================================================
//
// A blight sickens the level; the cure has to be worked up (Chem/Medical,
// largely surface reachback) and applied to the blight nodes to cleanse
// the source.
/datum/quarry_floor_archetype/virus
	name = "The Blight"
	desc = "A spreading sickness rots flora and fauna. Cleanse the blight nodes at the source."
	family = "bio"
	depth_weights = list("7+" = 24)
	var/node_count = 5

/datum/quarry_floor_archetype/virus/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/neutralize/G = new
	G.name = "Cleanse the Blight"
	G.description = "Cleanse [node_count] blight nodes to kill the contagion at its source."
	G.objective_tag = "cure"
	G.target = node_count
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/virus/on_layer_generated(datum/quarry_layer/L)
	_quarry_setup_neutralize(L, /obj/structure/quarry_objective/blight_node, "cure", node_count)

/datum/quarry_floor_archetype/virus/ambient_tick(datum/quarry_layer/L, seconds)
	var/list/objs = _quarry_get_objectives(L)
	var/active = 0
	for(var/obj/structure/quarry_objective/blight_node/B in objs)
		active++
	if(!active)
		return
	var/scale = seconds / QUARRY_TICK_NORMALIZE_SECONDS
	SSquarry.add_layer_danger(L, 0.3 * active * scale)
	// The contagion sickens everyone on the level until the source blooms
	// are cleansed — toxin damage scaled by how many are still active.
	// Survival needs Medical support; cleansing fast needs the antiviral
	// (Chem). Safe rooms don't help — the sickness is already in you.
	_quarry_environmental_damage(L, (1 + 0.8 * active) * scale, "tox")


// === #6 Resource delivery ============================================
//
// Pure logistics: ship a quota of ore up the elevator. Engages Mining +
// Cargo end to end; clears when the haul reaches the surface.
/datum/quarry_floor_archetype/resource
	name = "Freight Quota"
	desc = "Central wants tonnage. Haul the ore up and ship it off at the surface freight terminal."
	family = "logistics"
	depth_weights = list("1+" = 22)
	// Quota scales with depth (deeper hauls are worth more tonnage).
	var/quota_base = 40
	var/quota_per_depth = 8

/datum/quarry_floor_archetype/resource/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/deliver_resource/G = new
	var/quota = quota_base + quota_per_depth * L.depth
	G.name = "Ship the Quota"
	G.description = "Ship [quota] units of ore off at the surface freight terminal."
	G.target = quota
	G.owner_layer = L
	return list(G)


// === #7 Boss hives ===================================================
//
// Spawning hives spew fauna until destroyed. A combat sweep: clear the
// cores. Each live core keeps pumping out mobs.
/datum/quarry_floor_archetype/hives
	name = "Infested Warren"
	desc = "Hive cores are spewing fauna across the level. Hunt them down and destroy them."
	family = "combat"
	depth_weights = list("6+" = 26)
	var/hive_count = 4
	var/spawn_cooldown = 35 SECONDS

/datum/quarry_floor_archetype/hives/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/neutralize/G = new
	G.name = "Destroy the Hives"
	G.description = "Destroy [hive_count] hive cores to end the infestation."
	G.objective_tag = "hive"
	G.target = hive_count
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/hives/on_layer_generated(datum/quarry_layer/L)
	_quarry_setup_neutralize(L, /obj/structure/quarry_objective/hive_core, "hive", hive_count)

/datum/quarry_floor_archetype/hives/ambient_tick(datum/quarry_layer/L, seconds)
	var/list/objs = _quarry_get_objectives(L)
	var/list/cores = list()
	for(var/obj/structure/quarry_objective/hive_core/C in objs)
		cores += C
	if(!length(cores))
		return
	SSquarry.add_layer_danger(L, 0.4 * length(cores) * (seconds / QUARRY_TICK_NORMALIZE_SECONDS))
	if(world.time < L.last_danger_wave + spawn_cooldown)
		return
	L.last_danger_wave = world.time
	// Every live core keeps pumping out fauna — more cores, more pressure.
	for(var/obj/structure/quarry_objective/hive_core/C as anything in cores)
		var/turf/T = get_turf(C)
		if(T)
			_quarry_archetype_spawn_mobs(L, T, rand(2, 3))


// === #8 Shaft assault (siege) ========================================
//
// The milestone gate every 5 depths (forced by select_archetype). The
// floor is calm until a crew triggers the assault at the shaft-assault
// console placed by the bay. Once triggered it's a 3-minute defend-the-
// elevator hold: the console roars at the bay drawing waves, and if any
// hostile gets INTO the lift the sequence aborts and must be retriggered.
// All the live logic lives on /obj/structure/quarry_siege_console — the
// archetype just places it and holds the survive_timer goal.
/datum/quarry_floor_archetype/siege
	name = "Shaft Assault"
	desc = "Trigger the assault at the shaft console and hold the elevator for three minutes."
	family = "siege"
	depth_weights = null  // never rolls normally; forced at every 5th depth
	var/hold_seconds = 3 MINUTES / 10

/datum/quarry_floor_archetype/siege/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/survive_timer/G = new
	G.name = "Hold the Shaft"
	G.description = "Trigger the assault and hold the elevator for [hold_seconds / 60] minutes."
	G.target = hold_seconds
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/siege/on_layer_generated(datum/quarry_layer/L)
	// Place the trigger console on a floor next to this layer's bay so the
	// "defend the elevator" fight happens right at the lift.
	var/list/bay = SSquarry.elevator?.bay_at(L.depth)
	if(!length(bay))
		return
	for(var/turf/B as anything in bay)
		for(var/dir in GLOB.cardinal)
			var/turf/T = get_step(B, dir)
			if(!istype(T, /turf/simulated/floor))
				continue
			if(T in bay)
				continue
			if(T.density)
				continue
			var/blocked = FALSE
			for(var/obj/O in T)
				if(O.density || istype(O, /obj/machinery/door))
					blocked = TRUE
					break
			if(blocked)
				continue
			new /obj/structure/quarry_siege_console(T)
			return


// === #9 Power overcharge =============================================
//
// Energize a set of grid taps into the strata (Engineering). Standalone
// objective for now; the better long-term wiring is to feed another
// floor's lights/heaters, but as a floor it stands on the taps.
/datum/quarry_floor_archetype/power
	name = "Overcharge"
	desc = "Central wants power. Fuel and run the level's generators to feed the relay."
	family = "power"
	depth_weights = list("4+" = 22)
	// Target scales with depth: deeper orders demand more throughput.
	var/kwmin_base = 300
	var/kwmin_per_depth = 60
	var/generator_count = 3

/datum/quarry_floor_archetype/power/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/power_output/G = new
	var/target_kwmin = kwmin_base + kwmin_per_depth * L.depth
	G.name = "Feed the Grid"
	G.description = "Generate [target_kwmin] kW-minutes from the level's generators."
	G.target = target_kwmin
	G.owner_layer = L
	return list(G)

/datum/quarry_floor_archetype/power/on_layer_generated(datum/quarry_layer/L)
	// Drop portable generators (off, unfueled) plus starter fuel. Players
	// fuel and run them (Engineering); Cargo can haul more fuel down to
	// hit the quota faster.
	var/placed = 0
	while(placed < generator_count)
		var/turf/T = _quarry_random_layer_floor(L)
		if(!T)
			break
		var/obj/machinery/power/port_gen/pacman/P = new(T)
		P.anchored = TRUE
		placed++
	for(var/i in 1 to 2)
		var/turf/T = _quarry_random_layer_floor(L)
		if(T)
			new /obj/item/stack/material/phoron(T, 30)


// === #10 Exterminate =================================================
//
// Clear the level's population. Reuses the existing kill_mob goal with a
// high target; the layer's config already spawns the fauna.
/datum/quarry_floor_archetype/exterminate
	name = "Extermination Order"
	desc = "The level is overrun. Cull the population to clear it for work crews."
	family = "combat"
	depth_weights = list("1+" = 22)
	// Cull count scales with depth (deeper levels are more overrun).
	var/cull_base = 15
	var/cull_per_depth = 3

/datum/quarry_floor_archetype/exterminate/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/kill_mob/G = new
	var/cull_target = cull_base + cull_per_depth * L.depth
	G.name = "Cull the Fauna"
	G.description = "Kill [cull_target] hostile creatures to clear the level."
	G.mob_type = /mob/living/simple_mob
	G.target = cull_target
	G.owner_layer = L
	return list(G)
