// Global procs under code/datums/capabilities/ are followed as constructor bundles.
/proc/door_bundle(subtypes)
	. = list(cap_lock(), cap_cycle_a())

/proc/cap_cycle_a()
	return list(cap_cycle_b())

/proc/cap_cycle_b()
	var/list/l = list(cap_cycle_a())
	return list(new /datum/capability/cycle, l)

/proc/cap_lock()
	return new /datum/capability/lock

/proc/cap_lock_airlock()
	var/datum/capability/lock/airlock/c = new
	return c

/proc/cap_weird()
	var//datum/capability/weird/w = new
	return w

/proc/cap_args()
	return slot(a, slot_type = /datum/capability/slot/x)

// not under cap_ and not in this dir's followed set when called from elsewhere: bundle by dir anyway
/proc/plain_noun()
	return new /datum/capability/plain
