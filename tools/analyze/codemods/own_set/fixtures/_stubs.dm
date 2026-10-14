#define nameof(x) #x
#define CAPABILITIES(T) ##T/__capabilities()

/datum/proc/__capabilities()
	return

/proc/owns_one(var_name, type = null)
	return null

/proc/owns_many(var_name, type = null)
	return null

/proc/own_set(datum/holder, var_name, datum/value, mob/user = null, into = null, slot = null, force = 0, log = null)
	return value

/proc/rel_set(datum/E, var_name, datum/value)
	return value
