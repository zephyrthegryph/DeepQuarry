//"immutable" gas mixture — arena-backed (auxmos).
//
//Immutability is enforced Rust-side: after the mixture is populated we call
//mark_immutable(), and the arena silently drops any future mutation (set_moles/
//set_temperature/merge/react/etc. become no-ops once marked). The old DM
//archive()/share()/temperature_share()/garbage_collect() overrides that faked
//immutability by resetting the (now-deleted) `gases` list every share are gone —
//the base no longer has those procs, and the arena + mark_immutable() replace the
//behaviour. Turf sharing runs Rust-side (SSair.process_turfs_auxtools).
//
//IMPORTANT ordering: mark_immutable() is a one-way latch — once set, further
//writes are ignored. So it must be the LAST thing done, after the mix is fully
//populated. The base New() only registers the mix + sets its initial temperature;
//each concrete subtype marks itself immutable once it is done being populated
//(space immediately, since it's empty; planetary in parse_string_immutable()).

/datum/gas_mixture/immutable
	var/initial_temperature = TCMB

/datum/gas_mixture/immutable/New()
	..() // register the mixture in the arena first
	set_temperature(initial_temperature)

//used by space tiles — empty and fixed at construction, so mark immutable now.
/datum/gas_mixture/immutable/space
	initial_temperature = TCMB

/datum/gas_mixture/immutable/space/New()
	..()
	mark_immutable()

/datum/gas_mixture/immutable/space/heat_capacity(data = MOLES)
	return HEAT_CAPACITY_VACUUM

/datum/gas_mixture/immutable/space/remove(amount)
	return copy() //we're always empty, so we can just return a copy.

/datum/gas_mixture/immutable/space/remove_ratio(ratio)
	return copy() //we're always empty, so we can just return a copy.

//planet side stuff — populated after construction via parse_string_immutable(),
//which marks the mix immutable once its gases are loaded. NOT marked in New().
/datum/gas_mixture/immutable/planetary

/datum/gas_mixture/immutable/planetary/proc/parse_string_immutable(gas_string) //I know I know, I need this tho
	gas_string = SSair.preprocess_gas_string(gas_string)

	var/list/gas = params2list(gas_string)
	if(gas["TEMP"])
		initial_temperature = text2num(gas["TEMP"])
		gas -= "TEMP"
	set_temperature(initial_temperature)

	for(var/id in gas)
		var/path = id
		if(!ispath(path))
			path = gas_id2path(path) //a lot of these strings can't have embedded expressions (especially for mappers), so support for IDs needs to stick around
		set_moles(path, text2num(gas[id]))

	mark_immutable()
