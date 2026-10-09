// Legacy entry points keep existing callers on the engine-owned cadence runtime.
/proc/_om_periodic_start(datum/E, P)
	return cadence_start(E, P)

/proc/_om_periodic_stop(datum/E)
	return cadence_stop(E)

/datum/compatibility_periodic_allowed(cadence)
	return sys_periodic_allows(src, cadence) && sys_every_allows(src)
