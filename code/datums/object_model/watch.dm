/** Event-driven DM watches. Producers call om_changed after observable writes. */
/datum/object_model/watch_definition
	/// A transition can be delivered as a typed event to active behaviours.
	var/event_path
	/// Optional outgoing source-single relation whose current target is watched.
	var/relation_path

/datum/object_model/watch_definition/om_kind()
	return OM_KIND_DEF

/datum/object_model/watch_definition/proc/validate_config(list/config)
	if(config && (("dynamic_subject" in config) || ("subject" in config)))
		return "watch subjects come from self or the definition's declared source-single relation"
	if(event_path && !om_event(event_path))
		return "unknown watch event [event_path]"
	return null

/datum/object_model/watch_definition/proc/test(datum/entity, datum/subject, list/config)
	return FALSE

/datum/object_model/watch_definition/proc/changed(datum/entity, datum/subject, list/config, truth, previous)
	if(event_path)
		om_emit(entity, event_path, subject, truth, previous)

/datum/object_model/watch_definition/om_watch_value(datum/entity, datum/subject, key)
	var/datum/object_model/archetype/A = om_archetype_for(entity.type, entity)
	return test(entity, subject, A?.watches?[key])

/datum/object_model/watch_definition/om_on_watch(datum/entity, datum/subject, key, truth, previous)
	var/datum/object_model/archetype/A = om_archetype_for(entity.type, entity)
	changed(entity, subject, A?.watches?[key], truth, previous)

/proc/om_watch_definition(path)
	if(!ispath(path, /datum/object_model/watch_definition) || path == /datum/object_model/watch_definition)
		return null
	var/static/list/definitions = list()
	var/datum/object_model/watch_definition/D = definitions[path]
	if(!D)
		D = new path
		definitions[path] = D
	return D

/datum/proc/om_watch_value(datum/entity, datum/subject, key)
	return FALSE

/datum/proc/om_on_watch(datum/entity, datum/subject, key, truth, previous)
	return

/datum/object_model/watch
	var/datum/entity
	var/datum/subject
	var/datum/handler
	var/key
	var/truth
	var/token

/datum/object_model/watch/proc/start(datum/new_entity, datum/new_subject, datum/new_handler, new_key, report_initial = FALSE)
	if(!new_entity || QDELETED(new_entity) || !new_subject || QDELETED(new_subject) || !new_handler || QDELETED(new_handler))
		return FALSE
	entity = new_entity
	subject = new_subject
	handler = new_handler
	key = new_key
	if(!om_claim(entity, "om:watch", src))
		return FALSE
	RegisterSignal(entity, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	if(subject != entity)
		RegisterSignal(subject, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	if(handler != entity && handler != subject && handler.om_kind() != OM_KIND_DEF)
		RegisterSignal(handler, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	truth = !!handler.om_watch_value(entity, subject, key)
	token = REACT_ON_KEY(src, REACT_KEY_OBJECT_MODEL, REACT_ID(subject), REACT_KEY_CHANGED)
	if(report_initial)
		handler.om_on_watch(entity, subject, key, truth, null)
	return TRUE

/datum/object_model/watch/proc/on_endpoint_deleting(datum/source)
	SIGNAL_HANDLER
	qdel(src)

/datum/object_model/watch/on_react(reason, source, source_kind)
	if(!entity || QDELETED(entity) || !subject || QDELETED(subject) || !handler || QDELETED(handler))
		return
	var/next_truth = !!handler.om_watch_value(entity, subject, key)
	if(next_truth == truth)
		return
	var/previous = truth
	truth = next_truth
	handler.om_on_watch(entity, subject, key, truth, previous)

/datum/object_model/watch/react_sleep_violation()
	if(entity && subject && handler && !QDELETED(entity) && !QDELETED(subject) && !QDELETED(handler))
		if(!!handler.om_watch_value(entity, subject, key) != truth)
			return "object model watch missed a change for [subject.type]:[key]"
	return null

/datum/object_model/watch/Destroy(force = FALSE)
	if(entity && !QDELETED(entity))
		UnregisterSignal(entity, COMSIG_QDELETING)
	if(subject && subject != entity && !QDELETED(subject))
		UnregisterSignal(subject, COMSIG_QDELETING)
	if(handler && handler != entity && handler != subject && handler.om_kind() != OM_KIND_DEF && !QDELETED(handler))
		UnregisterSignal(handler, COMSIG_QDELETING)
	entity = null
	subject = null
	handler = null
	key = null
	return ..()

/// A retained watch, cancelled by qdel, owner destruction or endpoint destruction.
/proc/om_watch(datum/entity, datum/subject, datum/handler, key, report_initial = FALSE)
	var/datum/object_model/watch/W = new
	if(!W.start(entity, subject, handler, key, report_initial))
		qdel(W)
		return null
	return W

/// Observable producers publish after state mutation. Watch callbacks are coalesced by the reactor.
/proc/om_changed(datum/subject, channel = null, changed_mask = 0)
	if(!subject || QDELETED(subject))
		return
	subject.om_cache_changed(channel)
	om_subscription_on_changed(subject, channel)
	if(subject.om_state?.behaviour_runtime)
		om_behaviour_refresh(subject, null, changed_mask)
	if(subject.reactor_id)
		REACT_PUBLISH(REACT_KEY_OBJECT_MODEL, subject.reactor_id, REACT_KEY_CHANGED)
