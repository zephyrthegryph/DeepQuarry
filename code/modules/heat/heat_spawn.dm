// Starting/fallback configuration only. Actual runtime temperature stays in the native heat body.
STATIC_ENTRY(heat_spawn)

/proc/heat_spawn(temperature = null)
	return entry_make(ENTRY_HEAT_SPAWN, null, list("temperature" = temperature))

/datum/type_trait/heat_spawn
	var/temperature = BODYTEMP_NORMAL

/datum/type_trait/heat_spawn/copy_values(datum/type_trait/heat_spawn/into)
	into.temperature = temperature

/datum/entry_engine/type_trait/heat_spawn
	kind = ENTRY_HEAT_SPAWN
	trait_type = /datum/type_trait/heat_spawn
	publish_key = HEAT_SPAWN_KEY
	base_type = /mob
	var_names = list("bodytemperature" = "temperature")

READS_AS(/proc/heat_spawn_of, HEAT_SPAWN_KEY)
/proc/heat_spawn_of(mob/M) as /datum/type_trait/heat_spawn
	READS_FROM(M)
	return type_trait_of(M, ENTRY_HEAT_SPAWN)

/// Compiled type default, deliberately excluding a holder's map/VV COW changes (the old initial()).
/proc/heat_spawn_of_type(path) as /datum/type_trait/heat_spawn
	READS_FROM()
	return type_trait_of_type(path, ENTRY_HEAT_SPAWN)
