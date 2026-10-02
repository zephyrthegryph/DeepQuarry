/datum/system/alpha
	var/list/needs = list(/datum/system/beta)
	var/list/uses = list(
		/datum/system/beta,
	)
	var/list/emits = list(/datum/om/event/a)

/datum/system/alpha/proc/body()
	OM_EMIT(/datum/om/event/a)
	OM_EMIT(/datum/om/event/b)
	OM_EMIT_BEFORE(/datum/om/event/before/c)
	// ALLOW(system_boundary): documented keep
	OM_EMIT(/datum/om/event/d)
	OM_EMIT(/datum/om/event/e) // ALLOW(system_boundary): same line
	// OM_EMIT(/datum/om/event/f)
	return system(/datum/system/beta).ping()
	OM_EMIT(src, /datum/om/event/srcfirst)
	OM_EMIT( /datum/om/event/g/h) OM_EMIT(/datum/om/event/a)
