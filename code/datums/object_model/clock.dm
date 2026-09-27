// Virtual time belongs to an owner and a domain. Definitions are shared;
// runtime state exists only after a non-real-time behaviour or modifier uses it.
#define OM_CLOCK_MAX_RATE 8

/datum/object_model/clock_domain

/datum/object_model/clock_domain/biology

/datum/object_model/clock_domain/decay

/datum/object_model/clock_domain/action

/datum/object_model/clock_state
	var/datum/owner
	var/domain
	/// Deciseconds of local time. Rate one starts aligned with world.time.
	var/virtual_time
	var/last_world
	var/rate = 1
	var/list/modifiers
	var/releasing = FALSE

/datum/object_model/clock_state/New(datum/new_owner, new_domain)
	. = ..()
	owner = new_owner
	domain = new_domain
	virtual_time = world.time
	last_world = world.time

/datum/object_model/clock_state/proc/settle()
	var/now = world.time
	if(now > last_world)
		virtual_time += (now - last_world) * rate
		last_world = now
	return virtual_time

/datum/object_model/clock_state/proc/set_modifier(datum/source, multiplier = 1, inhibition = 0)
	if(!source || QDELETED(source) || !isnum(multiplier) || multiplier < 0 || !isnum(inhibition) || inhibition < 0 || inhibition > 1)
		return FALSE
	if(!modifiers)
		modifiers = list()
	var/datum/object_model/clock_modifier/M = modifiers[source]
	if(multiplier == 1 && inhibition == 0)
		if(M)
			modifier_lost(M)
			qdel(M)
		return TRUE
	if(!M)
		M = new(src, source)
		modifiers[source] = M
	M.multiplier = multiplier
	M.inhibition = inhibition
	recompute_rate()
	return TRUE

/datum/object_model/clock_state/proc/modifier_lost(datum/object_model/clock_modifier/M)
	if(releasing || !modifiers || modifiers[M.source] != M)
		return
	modifiers -= M.source
	recompute_rate()

/datum/object_model/clock_state/proc/recompute_rate()
	settle() // Never apply the new rate to elapsed time before this change.
	var/next_rate = 1
	var/strongest_inhibition = 0
	for(var/datum/source in modifiers)
		var/datum/object_model/clock_modifier/M = modifiers[source]
		if(!M || QDELETED(M))
			continue
		next_rate *= M.multiplier
		strongest_inhibition = max(strongest_inhibition, M.inhibition)
	next_rate = clamp(next_rate * (1 - strongest_inhibition), 0, OM_CLOCK_MAX_RATE)
	if(rate == next_rate)
		return
	rate = next_rate
	owner?.om_state?.behaviour_runtime?.clock_rate_changed(domain)

/datum/object_model/clock_state/Destroy()
	releasing = TRUE
	for(var/datum/source in modifiers)
		var/datum/object_model/clock_modifier/M = modifiers[source]
		if(M && !QDELETED(M))
			qdel(M)
	modifiers = null
	owner = null
	return ..()

/// A source's lifetime owns its contribution. Several sources can stack.
/datum/object_model/clock_modifier
	var/datum/object_model/clock_state/clock
	var/datum/source
	var/multiplier = 1
	var/inhibition = 0

/datum/object_model/clock_modifier/New(datum/object_model/clock_state/new_clock, datum/new_source)
	. = ..()
	clock = new_clock
	source = new_source
	RegisterSignal(source, COMSIG_QDELETING, PROC_REF(on_source_deleting))

/datum/object_model/clock_modifier/proc/on_source_deleting(datum/deleting)
	SIGNAL_HANDLER
	clock?.modifier_lost(src)
	qdel(src)

/datum/object_model/clock_modifier/Destroy()
	if(source && !QDELETED(source))
		UnregisterSignal(source, COMSIG_QDELETING)
	clock?.modifier_lost(src)
	clock = null
	source = null
	return ..()

/// The source's complete contribution is updated atomically. A default contribution removes it.
/proc/om_clock_set(datum/entity, domain, datum/source, multiplier = 1, inhibition = 0)
	if(!ispath(domain, /datum/object_model/clock_domain))
		return FALSE
	return om_clock_for(entity, domain)?.set_modifier(source, multiplier, inhibition)

/proc/om_clock_time(datum/entity, domain)
	if(!ispath(domain, /datum/object_model/clock_domain))
		return null
	return om_clock_for(entity, domain)?.settle()

/proc/om_clock_for(datum/entity, domain)
	if(!entity || QDELETED(entity) || !ispath(domain, /datum/object_model/clock_domain))
		return null
	var/datum/object_model/state/S = om_state_for(entity)
	if(!S.clock_states)
		S.clock_states = list()
	var/datum/object_model/clock_state/C = S.clock_states[domain]
	if(!C)
		C = new(entity, domain)
		S.clock_states[domain] = C
	return C
