// Delta-pressure response and movement force threshold are separate physical policies.
STATIC_ENTRY(pressure_response)
/proc/pressure_response(pressure = null, force = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_PRESSURE_RESPONSE, null, list("pressure" = pressure, "force" = force))
/datum/type_trait/pressure_response
	var/pressure = 10
	var/force = 100
/datum/type_trait/pressure_response/copy_values(datum/type_trait/pressure_response/into)
	into.pressure = pressure
	into.force = force
/datum/entry_engine/type_trait/pressure_response
	kind = ENTRY_PRESSURE_RESPONSE
	trait_type = /datum/type_trait/pressure_response
	publish_key = PRESSURE_RESPONSE_KEY
	base_type = /atom/movable
	var_names = list("pressure_resistance" = "pressure", "move_resist" = "force")
READS_AS(/proc/pressure_response_of, PRESSURE_RESPONSE_KEY)
/proc/pressure_response_of(atom/movable/A) as /datum/type_trait/pressure_response
	READS_FROM(A)
	return type_trait_of(A, ENTRY_PRESSURE_RESPONSE)
/proc/pressure_response_of_type(type) as /datum/type_trait/pressure_response
	READS_FROM()
	return type_trait_of_type(type, ENTRY_PRESSURE_RESPONSE)
/atom/movable/proc/set_pressure_resistance(value)
	return set_trait(src, ENTRY_PRESSURE_RESPONSE, "pressure", value)
/atom/movable/proc/set_move_resist(value)
	return set_trait(src, ENTRY_PRESSURE_RESPONSE, "force", value)
