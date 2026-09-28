// Per-atom catalogue scan-delay. Per-type defaults in GLOB lookup, per-instance
// overrides in /atom/var/catalogue_delay_override (was a component; an unset var
// costs an instance nothing).

GLOBAL_LIST_INIT(dq_catalogue_delay_by_type, list(
	/mob = 10 SECONDS,
	/turf/simulated/floor/outdoors/grass/sif = 2 SECONDS,
))

/atom
	/// Per-instance catalogue scan delay, or null for the per-type default.
	var/catalogue_delay_override

// The original proc lived on /atom and is called extensively. Keep it as
// an /atom/proc (it's not a *new* proc-table entry — it already existed).
GLOBAL_LIST_EMPTY(_dq_catalogue_delay_resolved)

/atom/proc/get_catalogue_delay()
	if(!isnull(catalogue_delay_override))
		return catalogue_delay_override
	return _dq_resolve_typed_default(type, GLOB.dq_catalogue_delay_by_type, GLOB._dq_catalogue_delay_resolved, 5 SECONDS)

/proc/dq_set_catalogue_delay(atom/a, delay)
	a.catalogue_delay_override = delay
