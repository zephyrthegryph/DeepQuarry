// Mob body heat on the heat API (doc/rewrite/temperature.md, completion plan H2).
//
// `bodytemperature` is tracked state: nothing writes it except the two setters
// below (tools/ci/check_grep.sh bans direct writes). Everything that heats or
// cools a mob goes through add_heat(joules), adjust_bodytemperature(kelvin) or
// set_bodytemperature(kelvin), so Life's thermal stages are woken on change.

/// Sets this mob's body temperature (K). The only writer of `bodytemperature`.
/mob/proc/set_bodytemperature(new_temperature)
	if(!isnum(new_temperature) || new_temperature == bodytemperature)
		return
	bodytemperature = max(new_temperature, 0)
	om_changed(src, CHANGE_MOB_VITALS)

/// Shifts this mob's body temperature by `amount` K, clamping the result to
/// [min_temp, max_temp]. Returns the change applied.
/mob/proc/adjust_bodytemperature(amount, min_temp = 0, max_temp = INFINITY)
	var/old = bodytemperature
	set_bodytemperature(clamp(bodytemperature + amount, min_temp, max_temp))
	return bodytemperature - old

/// Moves this mob's body temperature `fraction` of the way toward `target` K.
/mob/proc/approach_bodytemperature(target, fraction)
	return adjust_bodytemperature((target - bodytemperature) * fraction)

/// The heat capacity of this mob's body (J/K).
/mob/proc/body_heat_capacity()
	return HUMAN_HEAT_CAPACITY

/// A mob's temperature is its body temperature.
/mob/get_temperature()
	return bodytemperature

/// Something carried by a mob sees the mob's surroundings, not its core.
/mob/get_interior_temperature()
	return get_ambient_temperature()

/// Heat added to a mob warms its body directly (no heat body node).
/mob/add_heat(joules)
	if(!joules || !isnum(joules))
		return 0
	adjust_bodytemperature(joules / body_heat_capacity())
	return joules

/mob/thermal_properties()
	return list(body_heat_capacity(), THERMAL_CONDUCTANCE_DEFAULT, THERMAL_EMISSIVITY_DEFAULT)
