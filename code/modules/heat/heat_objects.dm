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
	var/tmp/datum/heat_fire_turf

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
	rel_set(src, nameof(heat_fire_turf), location)
	return TRUE

/// Ends the fire coupling: the body relaxes to its surroundings and is
/// released at equilibrium again.
/atom/movable/proc/decouple_from_fire()
	if(isnull(heat_fire_turf))
		return
	rel_clear(src, nameof(heat_fire_turf))
	if(isnull(heat_body))
		return
	vg_heat_body_couple(heat_body, 1, HEAT_TARGET_NONE, 0, 0)
	if(!granted(src, /datum/capability/burning))
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
		if(!thing.heats_in_fire())
			continue
		thing.couple_to_fire(location)

/// Whether a fire on this object's tile heats it: a physical object that
/// something happens to when hot (it has heat rules).
/atom/movable/proc/heats_in_fire()
	return FALSE

/obj/heats_in_fire()
	if(has_trait(src, TRAIT_UNDERFLOOR) || (resistance_flags & INDESTRUCTIBLE))
		return FALSE
	return dq_rules_for_type(type) ? TRUE : FALSE

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

/// The overheating state: while the object is
/// above its heat limit (the overheating rule attaches this and detaches it when it
/// cools), a thermal damage stream proportional to the excess, OVERHEAT_DAMAGE_PER_KELVIN
/// per second per kelvin, between OVERHEAT_DAMAGE_MIN and OVERHEAT_DAMAGE_MAX per second.
/// A capability the overheating rule grants, ticking once a second; it has no state of its own.
CAPABILITY_TYPE(overheating, CAP_OVERHEATING, /datum/capability/overheating, key = NONE)
/datum/capability/overheating

/datum/capability/overheating/entries()
	return list(every(1 SECONDS, then(CAP_PROC(overheat_tick))))

/datum/capability/overheating/on_activate(datum/activation/A)
	var/obj/O = A.holder
	O.on_overheat()

/datum/capability/overheating/proc/overheat_tick(datum/act/timer/A)
	var/obj/O = A.holder
	O.overheat_step(A.dt / (1 SECONDS))

/// TRUE while the object overheats.
/obj/proc/is_overheating()
	return granted(src, /datum/capability/overheating)

/// One second-scaled step of the overheating damage stream.
/obj/proc/overheat_step(seconds_per_tick)
	var/obj/O = src
	if(QDELETED(O))
		return
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


// ------------------------------------------------------ machine heat (H4)

// Type-declared thermal settings are shared until an instance is explicitly changed.
STATIC_ENTRY(machine_heat)
/proc/machine_heat(output = null, dissipation = null)
	return entry_make(ENTRY_MACHINE_HEAT, null, list("output" = output, "dissipation" = dissipation))

/datum/type_trait/machine_heat
	var/output = 0
	var/dissipation

/datum/type_trait/machine_heat/copy_values(datum/type_trait/machine_heat/into)
	into.output = output
	into.dissipation = dissipation

/datum/entry_engine/type_trait/machine_heat
	kind = ENTRY_MACHINE_HEAT
	trait_type = /datum/type_trait/machine_heat
	publish_key = MACHINE_HEAT_KEY
	base_type = /obj/machinery
	var_names = list("heat_output" = "output", "heat_dissipation" = "dissipation")

READS_AS(/proc/machine_heat_of, MACHINE_HEAT_KEY)
/proc/machine_heat_of(obj/machinery/M) as /datum/type_trait/machine_heat
	READS_FROM(M)
	return type_trait_of(M, ENTRY_MACHINE_HEAT)

/proc/machine_heat_of_type(path) as /datum/type_trait/machine_heat
	READS_FROM()
	return type_trait_of_type(path, ENTRY_MACHINE_HEAT)

// Only machines currently emitting heat retain a power reading.
sparse(/obj/machinery, heat_output_now, type = num)
/proc/emitted_machine_heat(obj/machinery/M)
	return sparse_get_or(M, heat_output_now, 0)

/obj/machinery/thermal_properties()
	. = ..()
	var/dissipation = machine_heat_of(src).dissipation
	if(dissipation)
		.[THERMAL_CONDUCTANCE] = dissipation

/// Watts the machine emits right now. Subtypes scale it by load.
/obj/machinery/proc/current_heat_output()
	var/output = machine_heat_of(src).output
	if(!output || !use_power || (!operable()))
		return 0
	return output

/// Re-reads current_heat_output(). power_change() calls it; call it when load changes.
/obj/machinery/proc/update_heat_output()
	if(!machine_heat_of(src).output && !emitted_machine_heat(src))
		return
	set_heat_output(current_heat_output())

/// Feeds `watts` into the heat body; the body is kept while it emits.
/obj/machinery/proc/set_heat_output(watts)
	watts = max(watts, 0)
	if(watts == emitted_machine_heat(src) && (!watts || !isnull(heat_body)))
		return
	if(watts)
		if(!create_heat_body(TRUE))
			sparse_set_or(src, heat_output_now, 0, 0)
			return
		vg_heat_body_keep(heat_body, TRUE)
		vg_heat_body_power(heat_body, watts)
	else if(!isnull(heat_body))
		vg_heat_body_power(heat_body, 0)
		vg_heat_body_keep(heat_body, FALSE)
	sparse_set_or(src, heat_output_now, watts, 0)
