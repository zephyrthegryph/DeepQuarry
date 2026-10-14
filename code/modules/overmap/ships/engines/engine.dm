//Engine component object

/datum/ship_engine
	var/name = "ship engine"
	var/tmp/obj/machinery/holder	//actual engine object

REGISTRY_MEMBERSHIP(/datum/ship_engine, REGISTRY_SHIP_ENGINES)

/datum/ship_engine/New(obj/machinery/_holder)
	..()
	rel_set(src, nameof(holder), _holder)
	join_registries()

/datum/ship_engine/proc/can_burn()
	return 0

//Tries to fire the engine. Returns thrust
/datum/ship_engine/proc/burn()
	return 0

//Returns status string for this engine
/datum/ship_engine/proc/get_status()
	return GLOB.ship_engine_nominal_status

GLOBAL_LIST_INIT(ship_engine_nominal_status, list("All systems nominal"))

/datum/ship_engine/proc/get_thrust()
	return 1

//Sets thrust limiter, a number between 0 and 1
/datum/ship_engine/proc/set_thrust_limit(new_limit)
	return 1

/datum/ship_engine/proc/get_thrust_limit()
	return 1

/datum/ship_engine/proc/is_on()
	return 1

/datum/ship_engine/proc/toggle()
	return 1

// ships drop the engine.
/datum/ship_engine/lifecycle_dematerialize()
	for(var/obj/effect/overmap/visitable/ship/S in shuttles_ships())
		rel_remove(S, nameof(S.engines), src)
	return ..()

/// actual engine object
/datum/ship_engine/proc/holder() as /obj/machinery
	return holder
