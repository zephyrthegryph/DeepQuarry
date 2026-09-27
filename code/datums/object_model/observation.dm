// Sparse, owner-scoped subscriptions to existing DM signals. The owner keeps
// one observation per (signal, handler); no relation or behaviour is needed.
/datum/object_model/observation
	var/datum/owner
	var/signal_name
	var/handler
	var/on_lost
	var/component
	var/key
	var/list/subjects

/datum/object_model/observation/proc/start(datum/new_owner, new_signal, new_handler, new_on_lost, new_component, new_key)
	if(om_is_dying(new_owner) || !istext(new_signal) || !istext(new_handler))
		return FALSE
	owner = new_owner
	signal_name = new_signal
	handler = new_handler
	on_lost = new_on_lost
	component = new_component
	key = new_key
	if(!om_claim(owner, "om:observation", src))
		return FALSE
	return TRUE

/datum/object_model/observation/proc/sync(list/desired)
	if(om_is_dying(owner) || QDELETED(src))
		return FALSE
	if(subjects && length(subjects) == length(desired))
		var/unchanged = TRUE
		for(var/datum/subject as anything in desired)
			if(om_is_dying(subject))
				return FALSE
			if(!(subject in subjects))
				unchanged = FALSE
		if(unchanged)
			return TRUE
	var/list/next = list()
	for(var/datum/subject as anything in desired)
		if(om_is_dying(subject))
			return FALSE
		next |= subject
	if(component)
		for(var/datum/subject as anything in next)
			if(subjects && (subject in subjects))
				continue
			var/atom/target = subject
			if(!isatom(target))
				return FALSE
			target.AddComponent(component)
			if(om_is_dying(owner) || om_is_dying(target))
				return FALSE
	// Install the replacement before releasing old registrations. The callback
	// checks subjects, so a snapshotted signal from a removed target is ignored.
	for(var/datum/subject as anything in next)
		if(subjects && (subject in subjects))
			continue
		RegisterSignal(subject, signal_name, PROC_REF(on_signal))
		RegisterSignal(subject, COMSIG_QDELETING, PROC_REF(on_subject_deleting))
	if(!subjects)
		subjects = list()
	var/list/old = subjects
	subjects = next
	for(var/datum/subject as anything in old)
		if(subject in next || QDELETED(subject))
			continue
		UnregisterSignal(subject, list(signal_name, COMSIG_QDELETING))
	return TRUE

/datum/object_model/observation/proc/on_signal(datum/source, a, b, c, d, e, f, g, h)
	SIGNAL_HANDLER
	if(!owner || om_is_dying(owner) || !(source in subjects))
		return NONE
	return call(owner, handler)(source, a, b, c, d, e, f, g, h)

/datum/object_model/observation/proc/on_subject_deleting(datum/source)
	SIGNAL_HANDLER
	if(!(source in subjects))
		return
	var/datum/previous_owner = owner
	var/lost_handler = on_lost
	subjects -= source
	if(!length(subjects))
		qdel(src)
	if(!om_is_dying(previous_owner) && lost_handler)
		call(previous_owner, lost_handler)(source)

/datum/object_model/observation/Destroy(force = FALSE)
	var/datum/previous_owner = owner
	if(previous_owner?.om_state?.observations?[key] == src)
		previous_owner.om_state.observations -= key
		if(!length(previous_owner.om_state.observations))
			previous_owner.om_state.observations = null
	for(var/datum/subject as anything in subjects)
		if(!QDELETED(subject))
			UnregisterSignal(subject, list(signal_name, COMSIG_QDELETING))
	owner = null
	subjects = null
	key = null
	handler = null
	on_lost = null
	component = null
	signal_name = null
	return ..()

/proc/om_observation_key(signal_name, handler)
	return "[length(signal_name)]:[signal_name][handler]"

/// Reconcile one or more signal sources. A failing replacement retains the
/// previous watch. The owner owns cleanup; an empty set cancels it early.
/proc/om_observe_signals(datum/owner, list/subjects, signal_name, handler, component = null, on_lost = null)
	if(!owner || om_is_dying(owner) || !istext(signal_name) || !istext(handler) || signal_name == COMSIG_QDELETING)
		return FALSE
	var/key = om_observation_key(signal_name, handler)
	var/datum/object_model/observation/O = owner.om_state?.observations?[key]
	if(!length(subjects))
		if(O)
			qdel(O)
		return TRUE
	if(!O)
		O = new
		if(!O.start(owner, signal_name, handler, on_lost, component, key))
			qdel(O)
			return FALSE
		var/datum/object_model/state/state = owner.om_state
		if(!state.observations)
			state.observations = list()
		state.observations[key] = O
	else if(O.component != component || O.on_lost != on_lost)
		return FALSE
	if(!O.sync(subjects))
		if(!length(O.subjects))
			qdel(O)
		return FALSE
	return TRUE

/datum/proc/Observe(datum/subject, signal_name, handler, component = null, on_lost = null)
	return om_observe_signals(src, subject ? list(subject) : null, signal_name, handler, component, on_lost)

/datum/proc/ObserveSet(list/subjects, signal_name, handler, component = null, on_lost = null)
	return om_observe_signals(src, subjects, signal_name, handler, component, on_lost)

/datum/proc/Unobserve(signal_name, handler)
	return om_observe_signals(src, null, signal_name, handler)

/datum/proc/Observed(datum/subject, signal_name, handler)
	var/datum/object_model/observation/O = om_state?.observations?[om_observation_key(signal_name, handler)]
	return !!(O && subject && (subject in O.subjects))

/datum/proc/ObservedSources(signal_name, handler)
	var/datum/object_model/observation/O = om_state?.observations?[om_observation_key(signal_name, handler)]
	return O?.subjects?.Copy() || list()
