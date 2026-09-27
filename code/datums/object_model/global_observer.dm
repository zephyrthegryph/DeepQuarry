/// One listener per declared global system. Entity behaviours may subscribe to
/// related sources; broad from_any() rules live here so event fanout does not
/// grow one subscription token for every active entity.
/datum/object_model/global_observer
	var/list/subscriptions

/datum/object_model/global_observer/om_kind()
	return OM_KIND_SERVICE

/datum/object_model/global_observer/proc/declare_observers(datum/object_model/subscription_plan/P)
	return

/datum/object_model/global_observer/proc/start()
	var/datum/object_model/subscription_plan/P = new
	declare_observers(P)
	for(var/datum/object_model/subscription_rule/R as anything in P.rules)
		if(R.source_mode != OM_SUBJECT_GLOBAL || !ispath(R.event_path, /datum/object_model/event) || !om_observer_has_proc(type, R.handler))
			return FALSE
		if(R.condition_expr)
			var/list/errors = list()
			om_validate_observer_condition(R.condition_expr, errors, "[type] global observer")
			if(length(errors))
				return FALSE
	for(var/datum/object_model/subscription_rule/R as anything in P.rules)
		var/datum/object_model/subscription/S = om_subscribe(src, R, null, FALSE)
		if(!S)
			for(var/datum/object_model/subscription/active as anything in subscriptions)
				qdel(active)
			subscriptions = null
			return FALSE
		LAZYADD(subscriptions, S)
	return TRUE

/datum/object_model/global_observer/Destroy(force = FALSE)
	var/list/services = om_global_observer_services()
	if(services[type] == src)
		services -= type
	subscriptions = null
	return ..()

/proc/om_global_observer_services()
	var/static/list/services = list()
	return services

/// Lazily starts a singleton. qdel()ing it cancels its event subscriptions;
/// the next lookup starts a fresh instance.
/proc/om_global_observer(path) as /datum/object_model/global_observer
	if(!ispath(path, /datum/object_model/global_observer) || path == /datum/object_model/global_observer)
		return null
	var/list/services = om_global_observer_services()
	var/datum/object_model/global_observer/S = services[path]
	if(S && !QDELETED(S))
		return S
	S = new path
	if(!S.start())
		qdel(S)
		return null
	services[path] = S
	return S
