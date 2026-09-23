// Heat for objects (doc/rewrite/temperature.md §4-5, roadmap H3).
//
// An object's heat node is its heat body (heat.dm). What happens at a
// temperature is a rule on that node (code/datums/rules/declarations.dm):
// ignition, melting, overheating, cooking, cook-off and the per-type heat
// behaviours. This file holds what feeds the node:
//
//   thermal_properties()   capacity from the object's materials (and reagents)
//   expose_heat(T)         an explicit fire exposure: a pulse of heat
//   couple_to_fire(turf)   a hotspot couples the object to the burning tile's
//                          gas; the heat domain does the exchange from then on
//
// and the overheating state (a thermal damage stream while above the limit).

/atom/movable
	/// The burning tile whose gas this object's body is coupled to (slot 1),
	/// while a hotspot is on it.
	var/tmp/turf/heat_fire_turf

// ------------------------------------------------------ thermal properties

/// Items take their heat capacity from their materials (PROP_HEAT_CAPACITY:
/// kg x specific heat), falling back to their size class.
/obj/item/thermal_properties()
	var/size = max(w_class, 1)
	var/capacity = PROPERTY(src, PROP_HEAT_CAPACITY)
	if(!(capacity > 0))
		capacity = size * THERMAL_CAPACITY_PER_W_CLASS
	return list(capacity, size * THERMAL_CONDUCTANCE_PER_W_CLASS, THERMAL_EMISSIVITY_DEFAULT)

/// Reagent containers add their contents' heat capacity (reagents.dm).
/obj/item/reagent_containers/thermal_properties()
	. = ..()
	if(reagents?.total_volume)
		.[THERMAL_CAPACITY] += reagents.heat_capacity()

/// Conductance (W/K) between this object and a flame or burning gas.
/atom/proc/fire_conductance()
	return FIRE_CONDUCTANCE_DEFAULT

/obj/item/fire_conductance()
	return max(w_class, 1) * FIRE_CONDUCTANCE_PER_W_CLASS

// ------------------------------------------------------------- exposure

/// An explicit exposure to fire at `temperature` (lava, a flamethrower, a
/// bonfire): `seconds` of contact through fire_conductance(), never past the
/// flame's temperature. Returns the joules added.
/atom/proc/expose_heat(temperature, seconds = FIRE_EXPOSURE_SECONDS)
	if(!isnum(temperature) || !create_heat_body())
		return 0
	var/current = get_temperature()
	if(!(temperature > current))
		return 0
	var/list/properties = thermal_properties()
	var/per_kelvin = min(fire_conductance() * seconds, properties[THERMAL_CAPACITY])
	return add_heat(per_kelvin * (temperature - current))

// ------------------------------------------------------- burning tiles

/// Couples this object's heat body to `location`'s gas at fire conductance
/// (slot 1), creating and keeping the body while the tile burns. The heat
/// domain then moves the heat both ways, conserving it. Returns TRUE if coupled.
/atom/movable/proc/couple_to_fire(turf/location)
	if(heat_fire_turf == location && !isnull(heat_body))
		return TRUE
	// Resting on the floor it was at the floor's temperature, not the flame's.
	if(!create_heat_body(TRUE, min(location.get_temperature(), get_ambient_temperature())))
		return FALSE
	vg_heat_body_keep(heat_body, TRUE)
	vg_heat_body_couple(heat_body, 1, HEAT_TARGET_TURF_AIR, location, fire_conductance())
	heat_fire_turf = location
	return TRUE

/// Ends the fire coupling: the body relaxes to its surroundings and is
/// released at equilibrium again.
/atom/movable/proc/decouple_from_fire()
	if(isnull(heat_fire_turf))
		return
	heat_fire_turf = null
	if(isnull(heat_body))
		return
	vg_heat_body_couple(heat_body, 1, HEAT_TARGET_NONE, 0, 0)
	if(!GetComponent(/datum/component/burning))
		vg_heat_body_keep(heat_body, FALSE)

/// A hotspot heats everything on its tile through each object's heat node:
/// objects are coupled once to the burning gas, and the heat domain does the
/// rest. Mobs still take fire_act() (their body heat is H2's). This replaces
/// calling fire_act() on every atom on the tile on every SSair fire.
/obj/effect/hotspot/proc/heat_tile(turf/location)
	for(var/atom/movable/thing as anything in location)
		if(thing == src || QDELETED(thing))
			continue
		if(isliving(thing))
			thing.fire_act(temperature, volume)
			continue
		if(thing.heat_fire_turf == location && !isnull(thing.heat_body))
			continue
		if(!isobj(thing) || HAS_TRAIT(thing, TRAIT_UNDERFLOOR))
			continue
		var/obj/O = thing
		if(O.resistance_flags & INDESTRUCTIBLE)
			continue
		thing.couple_to_fire(location)

/// The tile stopped burning: uncouple what it heated.
/obj/effect/hotspot/proc/cool_tile(turf/location)
	for(var/atom/movable/thing as anything in location)
		if(thing.heat_fire_turf == location)
			thing.decouple_from_fire()

// ---------------------------------------------------------- overheating

/// Called when the overheating rule starts the damage stream.
/obj/proc/on_overheat()
	return

/// One step of the overheating damage stream, through the damage pipeline.
/obj/proc/apply_heat_damage(amount)
	if(!uses_integrity || get_integrity() <= 0)
		return
	deal_damage(DAMAGE_THERMAL, amount, FIRE, flags = DAMAGE_PACKET_SILENT)

/// The overheating state: while the object is above its heat limit (the
/// overheating rule adds this and removes it when it cools), a thermal damage
/// stream proportional to the excess, OVERHEAT_DAMAGE_PER_KELVIN per second
/// per kelvin, between OVERHEAT_DAMAGE_MIN and OVERHEAT_DAMAGE_MAX per second.
/datum/component/overheating
	dupe_mode = COMPONENT_DUPE_UNIQUE

/datum/component/overheating/Initialize()
	if(!isobj(parent))
		return COMPONENT_INCOMPATIBLE
	var/obj/O = parent
	O.on_overheat()
	START_PROCESSING(SSburning, src)

/datum/component/overheating/Destroy(force)
	STOP_PROCESSING(SSburning, src)
	return ..()

/datum/component/overheating/process(seconds_per_tick)
	var/obj/O = parent
	if(QDELETED(O))
		return PROCESS_KILL
	var/limit = PROPERTY(O, PROP_MELTING_POINT)
	var/excess = O.get_temperature() - (isnull(limit) ? INFINITY : limit)
	if(!(excess > 0))
		return
	O.apply_heat_damage(clamp(excess * OVERHEAT_DAMAGE_PER_KELVIN, OVERHEAT_DAMAGE_MIN, OVERHEAT_DAMAGE_MAX) * seconds_per_tick)

// --------------------------------------------------------------- cook-off

/obj/item/reagent_containers/food/snacks
	/// Cooked by the cooking rule (time above FOOD_COOKING_TEMPERATURE).
	var/heat_cooked = FALSE

/// The cook-off rule: the round goes off in a random direction.
/obj/item/ammo_casing/proc/rule_cook_off(datum/rule/rule)
	var/turf/T = get_turf(src)
	if(!T || !BB)
		return
	var/obj/item/projectile/P = expend()
	P.forceMove(T)
	visible_message(span_danger("\The [src] cooks off!"))
	P.launch_projectile_from_turf(get_step(T, pick(GLOB.alldirs)))
