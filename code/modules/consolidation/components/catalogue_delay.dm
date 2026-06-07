// Per-atom catalogue scan-delay. Per-type defaults in GLOB lookup, per-instance
// overrides in a component. Global helpers to avoid proc-table bloat.
//
// Note: get_catalogue_delay is *still* an /atom/proc (not a global) because
// it pre-existed in the codebase — but its body now consults the component.

GLOBAL_LIST_INIT(dq_catalogue_delay_by_type, list(
	/mob = 10 SECONDS,
	/turf/simulated/floor/outdoors/grass/sif = 2 SECONDS,
))

/datum/component/catalogue_delay_override
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/delay

/datum/component/catalogue_delay_override/Initialize(d)
	. = ..()
	delay = d

// The original proc lived on /atom and is called extensively. Keep it as
// an /atom/proc (it's not a *new* proc-table entry — it already existed).
GLOBAL_LIST_EMPTY(_dq_catalogue_delay_resolved)

/atom/proc/get_catalogue_delay()
	var/datum/component/catalogue_delay_override/c = GetComponent(/datum/component/catalogue_delay_override)
	if(c)
		return c.delay
	return _dq_resolve_typed_default(type, GLOB.dq_catalogue_delay_by_type, GLOB._dq_catalogue_delay_resolved, 5 SECONDS)

/proc/dq_set_catalogue_delay(atom/a, delay)
	var/datum/component/catalogue_delay_override/c = a.GetComponent(/datum/component/catalogue_delay_override)
	if(!c)
		a.AddComponent(/datum/component/catalogue_delay_override, delay)
	else
		c.delay = delay
