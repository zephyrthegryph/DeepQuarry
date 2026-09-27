/** Exact closed-form rate fields for DM-owned quantities. */
/datum/proc/om_on_rate(datum/entity, key, crossing, value)
	return

/// One subscriber per crossing: the reactor reports the model id, not the threshold token.
/datum/object_model/rate_watch
	var/datum/object_model/rate/field
	var/crossing
	var/token

/datum/object_model/rate_watch/on_react(reason, source, source_kind)
	if((reason & REACT_REASON_RATE) && field && !QDELETED(field) && field.entity && !QDELETED(field.entity) && field.handler && !QDELETED(field.handler))
		field.handler.om_on_rate(field.entity, field.key, crossing, field.value())

/datum/object_model/rate_watch/Destroy(force = FALSE)
	if(field && !QDELETED(field) && field.threshold_watches?[crossing] == src)
		field.threshold_watches -= crossing
	field = null
	crossing = null
	return ..()

/datum/object_model/rate
	var/datum/entity
	var/datum/handler
	var/key
	var/model
	var/minimum
	var/maximum
	var/list/contributions
	var/next_term = 0
	var/list/threshold_watches
	var/model_kind = "sum"

/datum/object_model/rate/proc/start(datum/new_entity, new_key, initial, low, high, datum/new_handler, new_kind = "sum", rate_or_target = 0, relax_k = 0)
	if(!new_entity || QDELETED(new_entity) || !isnum(initial) || (isnum(low) && initial < low) || (isnum(high) && initial > high) || (isnum(low) && isnum(high) && low > high))
		return FALSE
	entity = new_entity
	handler = new_handler || new_entity
	key = new_key
	minimum = low
	maximum = high
	model_kind = new_kind
	if(!om_claim(entity, "om:rate", src))
		return FALSE
	if(om_is_dying(entity) || om_is_dying(handler) || om_owner(src) != entity)
		return FALSE
	RegisterSignal(entity, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	if(handler != entity)
		RegisterSignal(handler, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	switch(model_kind)
		if("sum")
			model = RATE_SUM(initial, minimum, maximum)
		if("linear")
			model = RATE_LINEAR(initial, rate_or_target, minimum, maximum)
		if("relax")
			model = RATE_RELAX(initial, rate_or_target, relax_k)
		else
			return FALSE
	return TRUE

/datum/object_model/rate/proc/on_endpoint_deleting(datum/source)
	SIGNAL_HANDLER
	qdel(src)

/datum/object_model/rate/proc/on_contributor_deleting(datum/source)
	SIGNAL_HANDLER
	remove_contribution(source)

/datum/object_model/rate/proc/value()
	return RATE_READ(model)

/datum/object_model/rate/proc/set_value(value)
	if(!isnum(value))
		return FALSE
	RATE_SET(model, value)
	return TRUE

/datum/object_model/rate/proc/set_linear_rate(per_second)
	if(model_kind != "linear" || !isnum(per_second))
		return FALSE
	RATE_SET_RATE(model, per_second)
	return TRUE

/datum/object_model/rate/proc/contribute(datum/source, per_second)
	if(model_kind != "sum" || !source || QDELETED(source) || !isnum(per_second))
		return FALSE
	if(!contributions)
		contributions = list()
	var/term = contributions[source]
	if(!term)
		term = ++next_term
		contributions[source] = term
		if(source != entity && source != handler)
			RegisterSignal(source, COMSIG_QDELETING, PROC_REF(on_contributor_deleting))
	RATE_SET_TERM(model, term, per_second)
	return TRUE

/datum/object_model/rate/proc/remove_contribution(datum/source)
	var/term = contributions?[source]
	if(!term)
		return FALSE
	RATE_SET_TERM(model, term, 0)
	contributions -= source
	if(source != entity && source != handler && !QDELETED(source))
		UnregisterSignal(source, COMSIG_QDELETING)
	return TRUE

/// A threshold name is the semantic event ID delivered to om_on_rate.
/datum/object_model/rate/proc/watch_threshold(crossing, cmp, level)
	if(!handler || QDELETED(handler) || !isnum(level) || (cmp != REACT_CMP_ABOVE && cmp != REACT_CMP_BELOW))
		return FALSE
	if(!threshold_watches)
		threshold_watches = list()
	var/datum/object_model/rate_watch/old_watch = threshold_watches[crossing]
	if(old_watch)
		qdel(old_watch)
	var/datum/object_model/rate_watch/W = new
	W.field = src
	W.crossing = crossing
	if(!om_claim(src, "om:threshold", W))
		qdel(W)
		return FALSE
	W.token = REACT_RATE(W, model, cmp, level)
	threshold_watches[crossing] = W
	return W

/datum/object_model/rate/Destroy(force = FALSE)
	if(entity?.om_state?.declared_rates?[key] == src)
		entity.om_state.declared_rates -= key
	if(entity && !QDELETED(entity))
		UnregisterSignal(entity, COMSIG_QDELETING)
	if(handler && handler != entity && !QDELETED(handler))
		UnregisterSignal(handler, COMSIG_QDELETING)
	if(contributions)
		for(var/datum/source as anything in contributions)
			if(source != entity && source != handler && !QDELETED(source))
				UnregisterSignal(source, COMSIG_QDELETING)
		contributions = null
	if(model)
		RATE_REMOVE(model)
	entity = null
	handler = null
	threshold_watches = null
	return ..()

/// The field is claimed by its owner and cancels all contributions on destruction.
/proc/om_rate(datum/entity, key, initial, minimum, maximum, datum/handler)
	var/datum/object_model/rate/R = new
	if(!R.start(entity, key, initial, minimum, maximum, handler))
		qdel(R)
		return null
	return R

/proc/om_rate_linear(datum/entity, key, initial, per_second, minimum, maximum, datum/handler)
	if(!isnum(per_second))
		return null
	var/datum/object_model/rate/R = new
	if(!R.start(entity, key, initial, minimum, maximum, handler, "linear", per_second))
		qdel(R)
		return null
	return R

/proc/om_rate_relax(datum/entity, key, initial, target, k_per_second, datum/handler)
	if(!isnum(target) || !isnum(k_per_second) || k_per_second < 0)
		return null
	var/datum/object_model/rate/R = new
	if(!R.start(entity, key, initial, null, null, handler, "relax", target, k_per_second))
		qdel(R)
		return null
	return R

/// Resolve a declared rate on first use; untouched instances allocate nothing.
/proc/om_declared_rate(datum/entity, key)
	if(!entity || QDELETED(entity))
		return null
	var/datum/object_model/archetype/A = om_archetype_for(entity.type, entity)
	var/list/config = A?.rates?[key]
	if(!config)
		return null
	var/datum/object_model/state/state = om_state_for(entity)
	if(!state.declared_rates)
		state.declared_rates = list()
	var/entry = state.declared_rates[key]
	if(entry == TRUE)
		return null // A claim callback is already constructing this field.
	if(istype(entry, /datum/object_model/rate))
		var/datum/object_model/rate/existing = entry
		if(!QDELETED(existing))
			return existing
	state.declared_rates[key] = TRUE
	var/datum/object_model/rate/R = om_rate(entity, key, config["initial"], config["min"], config["max"], entity)
	if(!R || om_is_dying(entity))
		if(R)
			qdel(R)
		if(entity.om_state?.declared_rates?[key] == TRUE)
			entity.om_state.declared_rates -= key
		return null
	for(var/crossing in config["thresholds"])
		var/list/threshold = config["thresholds"][crossing]
		if(!R.watch_threshold(crossing, threshold[1], threshold[2]))
			qdel(R)
			if(entity.om_state?.declared_rates?[key] == TRUE)
				entity.om_state.declared_rates -= key
			return null
	state.declared_rates[key] = R
	return R

/proc/om_declared_rate_value(datum/entity, key)
	var/datum/object_model/rate/R = om_declared_rate(entity, key)
	return R?.value()

/proc/om_declared_rate_set(datum/entity, key, value)
	var/datum/object_model/rate/R = om_declared_rate(entity, key)
	return R?.set_value(value) || FALSE

/proc/om_declared_rate_contribute(datum/entity, key, datum/source, per_second)
	var/datum/object_model/rate/R = om_declared_rate(entity, key)
	return R?.contribute(source, per_second) || FALSE
