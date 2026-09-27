// A scoped, source-owned hold on one group of scheduled behaviours. Holds do
// not slow virtual time and do not accumulate work to replay on release.
/datum/object_model/schedule_set

/datum/object_model/schedule_set/biology

/datum/object_model/schedule_set/presentation

/datum/object_model/suspension
	var/datum/entity
	var/datum/source
	var/set_path

/datum/object_model/suspension/New(datum/new_entity, new_set_path, datum/new_source)
	. = ..()
	entity = new_entity
	set_path = new_set_path
	source = new_source
	RegisterSignal(source, COMSIG_QDELETING, PROC_REF(on_source_deleting))

/datum/object_model/suspension/proc/on_source_deleting(datum/deleting)
	SIGNAL_HANDLER
	qdel(src)

/datum/object_model/suspension/Destroy()
	if(source && !QDELETED(source))
		UnregisterSignal(source, COMSIG_QDELETING)
	var/datum/object_model/state/S = entity?.om_state
	var/list/tokens = S?.suspensions?[set_path]
	if(tokens && (src in tokens))
		tokens -= src
		if(!length(tokens))
			S.suspensions -= set_path
			if(!S.dying)
				S.behaviour_runtime?.set_resumed(set_path)
	entity = null
	source = null
	return ..()

/// Each source gets one token; multiple sources must all release their holds.
/proc/om_suspend(datum/entity, set_path, datum/source)
	if(!entity || QDELETED(entity) || !source || QDELETED(source) || !ispath(set_path, /datum/object_model/schedule_set))
		return null
	var/datum/object_model/state/S = om_state_for(entity)
	if(!S.suspensions)
		S.suspensions = list()
	var/list/tokens = S.suspensions[set_path]
	if(!tokens)
		tokens = list()
		S.suspensions[set_path] = tokens
	for(var/datum/object_model/suspension/T as anything in tokens)
		if(T.source == source)
			return T
	var/was_active = length(tokens)
	var/datum/object_model/suspension/T = new(entity, set_path, source)
	tokens += T
	if(!was_active)
		S.behaviour_runtime?.set_suspended(set_path)
	return T

/proc/om_resume(datum/object_model/suspension/T)
	if(T && !QDELETED(T))
		qdel(T)

/proc/om_set_suspended(datum/entity, set_path)
	return !!length(entity?.om_state?.suspensions?[set_path])
