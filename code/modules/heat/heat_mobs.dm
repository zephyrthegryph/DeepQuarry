// Mob body heat on the heat network (doc/rewrite/temperature.md §3).
//
// A mob's body temperature is its Rust heat body's: body_temperature() reads it, and nothing in DM stores it. `bodytemperature` is only the
// type's starting value (the body starts there). The body is coupled to its surroundings by slot 0 (turf air, or the container it is in) at a
// conductance Life sets from clothing (set_environment_conductance()); metabolism is the body's own power (set_metabolic_power()). Writes from
// reagents, afflictions and machines go through the setters below, which book them in the heat ledger.

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

/// Seconds between two runs of Life's environment stage: the old convection moved 1/divisor of the gap per run.
#define LIFE_ENVIRONMENT_SECONDS 2

/// The heat capacity of this mob's body (J/K).
/mob/proc/body_heat_capacity()
	return HUMAN_HEAT_CAPACITY

/// The body's coupling to its surroundings, W/K: clothing and the air's density decide it (Life, environment). Re-coupled only on a real change.
/mob/living/proc/set_environment_conductance(conductance)
	conductance = max(0, conductance)
	if(!body || abs(conductance - body.environment_conductance) <= max(0.01, body.environment_conductance * 0.02))
		return
	body.environment_conductance = conductance
	var/h = mob_heat_body()
	if(!h)
		return
	var/list/coupling = heat_coupling()
	vg_heat_body_couple(h, 0, coupling[1], coupling[2], conductance)

/// The body's own heat, W (metabolism, an overheating prosthetic): booked as metabolism by Rust.
/mob/living/proc/set_metabolic_power(watts)
	if(!body || watts == body.metabolic_power)
		return
	body.metabolic_power = watts
	var/h = mob_heat_body()
	if(h)
		vg_heat_body_power(h, watts)

/datum/body
	/// The conductance the body's heat coupling to its surroundings is at, W/K.
	var/environment_conductance = 0
	/// The body's own heat output, W.
	var/metabolic_power = 0
	/// The body's radiative heat link to space while it is on a space turf, or null.
	var/space_radiation_edge

/// Off a space turf: the body stops radiating to space.
/mob/living/proc/stop_radiating()
	if(body?.space_radiation_edge)
		vg_heat_edge_remove(body.space_radiation_edge)
		body.space_radiation_edge = null

/// A living body couples to its surroundings at the conductance Life sets, not the default object conductance.
/mob/living/heat_recouple()
	if(isnull(heat_body))
		return
	HEAT_BODY_RESOLVE(src)
	var/list/coupling = heat_coupling()
	if(!vg_heat_body_couple(heat_body, 0, coupling[1], coupling[2], body?.environment_conductance || 0))
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
