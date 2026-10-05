// Mob body heat on the heat network (doc/rewrite/temperature.md §3).
//
// A mob's body temperature is its Rust heat body's: body_temperature() reads it, and nothing in DM stores it. `bodytemperature` is only the
// type's starting value (the body starts there). Life couples the body to its surroundings through clothing (set_surroundings()): slot 0 to
// its tile's air (or the container it is in), heat links to the air of the tiles open to it, to the floor solid and the walls beside it, and to
// the sky in space or near vacuum. Metabolism is the body's own power (set_metabolic_power()). Writes from reagents, afflictions and machines go
// through the setters below, which book them in the heat ledger.

/// The mob's heat body handle, made on first use at its starting temperature and kept for its life.
/mob/proc/mob_heat_body()
	if(isnull(heat_body))
		create_heat_body(TRUE, bodytemperature)
	else
		HEAT_BODY_RESOLVE(src)
	return heat_body

/mob/heat_reservoir()
	var/h = mob_heat_body()
	return h ? list(HEAT_TARGET_BODY, h) : null

/// This mob's body temperature, K.
/mob/proc/body_temperature()
	var/h = mob_heat_body()
	var/t = h ? vg_heat_body_temperature(h) : null
	return isnull(t) ? bodytemperature : t

/// Sets this mob's body temperature (K): an authority write (a machine, a spawn, a test), booked.
/mob/proc/set_bodytemperature(new_temperature, source = HEAT_SOURCE_AUTHORITY)
	if(!isnum(new_temperature) || new_temperature == body_temperature())
		return
	heat_set(src, max(new_temperature, TCMB), source)
	changed(src, CHANGE_MOB_VITALS)

/// Shifts this mob's body temperature by `amount` K, clamping the result to [min_temp, max_temp]: the joules it takes, booked under `source`.
/// Returns the change applied.
/mob/proc/adjust_bodytemperature(amount, min_temp = 0, max_temp = INFINITY, source = HEAT_SOURCE_METABOLISM)
	var/old = body_temperature()
	var/target = clamp(old + amount, min_temp, max_temp)
	if(target == old)
		return 0
	heat_add(src, (target - old) * body_heat_capacity(), source)
	changed(src, CHANGE_MOB_VITALS)
	return body_temperature() - old

/// Moves this mob's body temperature `fraction` of the way toward `target` K.
/mob/proc/approach_bodytemperature(target, fraction)
	return adjust_bodytemperature((target - body_temperature()) * fraction)

/// Seconds between two runs of Life's environment stage (one Life frame): the old convection moved 1/divisor of the gap per run.
#define LIFE_ENVIRONMENT_SECONDS LIFE_CYCLE_SECONDS

/// The heat capacity of this mob's body (J/K).
/mob/proc/body_heat_capacity()
	return HUMAN_HEAT_CAPACITY

/// The body's coupling to its surroundings (Life, environment), re-made only on a real change or a move:
///   air_conductance      W/K of convection, shared between the tile's air (coupling slot 0) and the air of the tiles open to it
///                        (the plume the body stirs, so the heat it gives the air spreads instead of warming one tile's 2 kJ/K)
///   surface_conductance  W/K of contact with the floor solid it stands on; each wall solid beside it takes BODY_WALL_CONDUCTANCE_FRACTION
///                        of it (contact and radiation to the surface)
///   sky_area             m² radiating to the 2.7 K sky (in space or near vacuum), 0 for none
/mob/living/proc/set_surroundings(air_conductance, surface_conductance, sky_area = 0)
	air_conductance = max(0, air_conductance)
	surface_conductance = max(0, surface_conductance)
	sky_area = max(0, sky_area)
	if(!body)
		return
	var/turf/T = isturf(loc) ? loc : null
	if(body.surroundings_at == surroundings_key(T) && near_enough(air_conductance, body.environment_conductance) && near_enough(surface_conductance, body.surface_conductance) \
		&& near_enough(sky_area, body.sky_area))
		return
	body.environment_conductance = air_conductance
	body.surface_conductance = surface_conductance
	body.sky_area = sky_area
	rebuild_surroundings()

/// The key set_surroundings() compares to tell whether the body is still where its links were made.
/mob/living/proc/surroundings_key(turf/T)
	return T ? "[T.x],[T.y],[T.z]" : ""

/// Whether a coupling value is within 2 % (or 0.01) of what it is at: not worth re-making the links.
/mob/living/proc/near_enough(value, current)
	return abs(value - current) <= max(0.01, current * 0.02)

/// Re-makes the body's links to its surroundings for where it is now: slot 0 to its tile's air (or its container), and heat links to the
/// open neighbours' air, the floor solid, the walls beside it and the sky. Nothing is linked while every conductance is zero (the comfort
/// range), so a body at ease costs nothing when it moves.
/mob/living/proc/rebuild_surroundings()
	drop_surroundings()
	var/h = mob_heat_body()
	if(!h)
		return
	var/turf/T = isturf(loc) ? loc : null
	body.surroundings_at = surroundings_key(T)
	var/list/plume = T ? surroundings_plume(T) : list()
	var/air = body.environment_conductance
	var/list/coupling = heat_coupling()
	// Slot 0 is the tile (or the container), at its share of the convection.
	vg_heat_body_couple(h, 0, coupling[1], coupling[2], air / (1 + length(plume)))
	if(!T)
		return
	var/list/edges = list()
	for(var/turf/N as anything in plume)
		edges += vg_heat_link_create(HEAT_TARGET_BODY, h, HEAT_TARGET_TURF_AIR, N, air / (1 + length(plume)), 0, 0)
	var/surface = body.surface_conductance
	if(surface > 0)
		if(T.heat_cell_kind() == HEAT_CELL_SOLID && !istype(T, /turf/space))
			edges += vg_heat_link_create(HEAT_TARGET_BODY, h, HEAT_TARGET_SOLID, T, surface, 0, 0)
		for(var/direction in GLOB.cardinal)
			var/turf/simulated/wall/W = get_step(T, direction)
			if(istype(W))
				edges += vg_heat_link_create(HEAT_TARGET_BODY, h, HEAT_TARGET_SOLID, W, surface * BODY_WALL_CONDUCTANCE_FRACTION, 0, 0)
	if(body.sky_area > 0)
		edges += vg_heat_link_create(HEAT_TARGET_BODY, h, HEAT_TARGET_SPACE, TCMB, 0, 1, body.sky_area)
	for(var/id in edges)
		if(id)
			LAZYADD(body.surroundings_edges, id)

/// The turfs whose air the body's convection reaches besides its own tile: the ones open to it on its level, while it has air.
/mob/living/proc/surroundings_plume(turf/T)
	. = list()
	if(body.environment_conductance <= 0 || !T.heat_has_air())
		return
	for(var/turf/N as anything in vg_atmos_adjacent_turfs(T))
		if(N.z == T.z && N.heat_has_air())
			. += N

/// Removes the body's links to its surroundings (slot 0 is left to heat_recouple()).
/mob/living/proc/drop_surroundings()
	if(!body)
		return
	for(var/id in body.surroundings_edges)
		vg_heat_edge_remove(id)
	body.surroundings_edges = null
	body.surroundings_at = null

/mob/living/release_heat_body()
	drop_surroundings()
	return ..()

/// The body's own heat, W (metabolism, an overheating prosthetic): booked as metabolism by Rust.
/mob/living/proc/set_metabolic_power(watts)
	if(!body || watts == body.metabolic_power)
		return
	body.metabolic_power = watts
	var/h = mob_heat_body()
	if(h)
		vg_heat_body_power(h, watts)

/datum/body
	/// The convection to the surrounding air, W/K (slot 0 and the plume links share it).
	var/environment_conductance = 0
	/// The contact with the floor (and, by BODY_WALL_CONDUCTANCE_FRACTION, the walls beside it), W/K.
	var/surface_conductance = 0
	/// The area radiating to the sky, m².
	var/sky_area = 0
	/// The body's own heat output, W.
	var/metabolic_power = 0
	/// The heat link ids to the plume's air, the floor, the walls and the sky.
	var/list/surroundings_edges
	/// Where those links were made for ("x,y,z" of the turf, "" off a turf; a key, not a reference to the turf).
	var/surroundings_at

/// A living body couples to its surroundings at the conductance Life sets, not the default object conductance; after a move its links are
/// re-made for the new tile.
/mob/living/heat_recouple()
	if(isnull(heat_body))
		return
	HEAT_BODY_RESOLVE(src)
	if(body && (body.environment_conductance > 0 || body.surface_conductance > 0 || body.sky_area > 0))
		rebuild_surroundings()
		return
	drop_surroundings()
	var/list/coupling = heat_coupling()
	if(!vg_heat_body_couple(heat_body, 0, coupling[1], coupling[2], 0))
		set_heat_body(null)

/// Inside something with an interior of its own (an exosuit's cabin) the body meets that; a container that links its occupant itself (the cryo
/// cell) gives no coupling here.
/mob/heat_coupling()
	var/atom/holder = loc
	var/inner = holder?.interior_heat_reservoir()
	if(inner == HEAT_TARGET_NONE)
		inner = GLOB.heat_coupling_none
	return inner || ..()

/// What a body inside this atom couples to (list(HEAT_TARGET_*, ref)), HEAT_TARGET_NONE for nothing, or null to use the usual chain.
/atom/proc/interior_heat_reservoir()
	return null

/obj/mecha/interior_heat_reservoir()
	return cabin_air ? list(HEAT_TARGET_MIXTURE, cabin_air) : null

/// A mob's temperature is its body temperature.
/mob/get_temperature()
	return body_temperature()

/// Something carried by a mob sees the mob's surroundings, not its core.
/mob/get_interior_temperature()
	return get_ambient_temperature()

/// Heat added to a mob warms its body.
/mob/add_heat(joules)
	if(!joules || !isnum(joules))
		return 0
	return heat_add(src, joules, HEAT_SOURCE_OTHER)

/mob/thermal_properties()
	return list(body_heat_capacity(), 0, THERMAL_EMISSIVITY_DEFAULT)
