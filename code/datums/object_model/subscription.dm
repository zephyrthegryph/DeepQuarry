// Composable event subscriptions. Rule and condition datums are shared definitions;
// only active subscriptions allocate tokens. Predicates must be pure and must not sleep.
#define OM_SUBJECT_DIRECT 1
#define OM_SUBJECT_RELATED 2
#define OM_SUBJECT_GLOBAL 3

/datum/object_model/subscription_rule
	var/event_path
	var/source_mode = OM_SUBJECT_DIRECT
	var/relation_path
	var/condition_path
	var/list/condition_expr
	/// PROC_REF on the subscriber. Arguments: (source, event, a, b, c, d).
	var/handler
	/// PROC_REF on the subscriber. Arguments: (source).
	var/match_handler

/datum/object_model/subscription_rule/proc/from_related(path)
	source_mode = OM_SUBJECT_RELATED
	relation_path = path
	return src

/datum/object_model/subscription_rule/proc/from_any()
	source_mode = OM_SUBJECT_GLOBAL
	return src

/datum/object_model/subscription_rule/proc/when_all(list/conditions)
	condition_expr = om_condition_all(conditions)
	return src

/datum/object_model/subscription_rule/proc/when_any(list/conditions)
	condition_expr = om_condition_any(conditions)
	return src

/datum/object_model/subscription_rule/proc/when_not(condition)
	condition_expr = om_condition_not(condition)
	return src

/datum/object_model/subscription_rule/proc/on_match(proc_ref)
	match_handler = proc_ref
	return src

/datum/object_model/subscription_plan
	var/list/rules = list()

/datum/object_model/subscription_plan/proc/on(event_path, handler)
	var/datum/object_model/subscription_rule/R = new
	R.event_path = event_path
	R.handler = handler
	rules += R
	return R

/// Behaviour definitions are singletons. The plan and its composed rules are
/// created once and reused by every active entity with this behaviour.
/datum/object_model/behaviour/var/datum/object_model/subscription_plan/observer_plan

/datum/object_model/behaviour/proc/declare_observers(datum/object_model/subscription_plan/P)
	return

/datum/object_model/behaviour/proc/om_observer_plan() as /datum/object_model/subscription_plan
	if(!observer_plan)
		observer_plan = new
		declare_observers(observer_plan)
	return observer_plan

/proc/om_validate_observer_condition(expression, list/errors, context, depth = 0)
	if(depth > 32)
		errors += "[context]: condition nesting exceeds 32"
		return
	if(ispath(expression, /datum/object_model/subscription_condition))
		return
	var/list/node = expression
	if(!islist(node))
		errors += "[context]: invalid condition [expression]"
		return
	var/op = node["op"]
	var/list/children = node["args"]
	if(!(op in list("all", "any", "not")) || !islist(children) || !length(children) || (op == "not" && length(children) != 1))
		errors += "[context]: invalid condition expression"
		return
	for(var/child in children)
		om_validate_observer_condition(child, errors, context, depth + 1)

/proc/om_observer_has_proc(entity_type, proc_name)
	if(!istext(proc_name))
		return FALSE
	for(var/datum/T = entity_type; T; T = initial(T.parent_type))
		if(text2path("[T]/proc/[proc_name]"))
			return TRUE
	return FALSE

/// Called by archetype validation after the behaviour is known. Rules are
/// shared metadata, so invalid callbacks or ambiguous duplicates fail early.
/proc/om_validate_observer_plan(datum/object_model/subscription_plan/P, entity_type, list/errors)
	if(!P)
		return
	var/list/seen = list()
	for(var/datum/object_model/subscription_rule/R in P.rules)
		var/context = "[entity_type] observer [R.event_path]"
		if(!ispath(R.event_path, /datum/object_model/event))
			errors += "[context]: invalid event"
		if(R.source_mode == OM_SUBJECT_RELATED)
			var/datum/object_model/relation/relation = om_relation_def(R.relation_path)
			if(!relation || !ispath(entity_type, relation.from_type))
				errors += "[context]: incompatible relation [R.relation_path]"
		else if(R.source_mode == OM_SUBJECT_DIRECT)
			errors += "[context]: direct rules need om_subscribe() with an explicit source"
		else if(R.source_mode == OM_SUBJECT_GLOBAL)
			errors += "[context]: from_any rules belong in a global observer service"
		else
			errors += "[context]: invalid source mode [R.source_mode]"
		if(!om_observer_has_proc(entity_type, R.handler))
			errors += "[context]: missing event callback [R.handler]"
		if(R.match_handler && !om_observer_has_proc(entity_type, R.match_handler))
			errors += "[context]: missing match callback [R.match_handler]"
		if(R.condition_path && !ispath(R.condition_path, /datum/object_model/subscription_condition))
			errors += "[context]: invalid condition [R.condition_path]"
		if(R.condition_expr)
			om_validate_observer_condition(R.condition_expr, errors, context)
		var/key = "[R.event_path]|[R.source_mode]|[R.relation_path]|[R.handler]"
		if(seen[key])
			errors += "[context]: duplicate observer rule"
		seen[key] = TRUE

/// Expression lists are built once on a shared plan, not once per subscriber.
/proc/om_condition_all(list/conditions)
	return list("op" = "all", "args" = conditions?.Copy())

/proc/om_condition_any(list/conditions)
	return list("op" = "any", "args" = conditions?.Copy())

/proc/om_condition_not(condition)
	return list("op" = "not", "args" = list(condition))

/proc/om_condition_test(expression, datum/listener, datum/source, depth = 0)
	if(depth > 32)
		CRASH("object model subscription condition nesting exceeded 32")
	if(ispath(expression, /datum/object_model/subscription_condition))
		var/datum/object_model/subscription_condition/C = om_subscription_condition(expression)
		return !!C.test(listener, source)
	var/list/node = expression
	if(!islist(node))
		return FALSE
	var/list/children = node["args"]
	switch(node["op"])
		if("all")
			for(var/child in children)
				if(!om_condition_test(child, listener, source, depth + 1))
					return FALSE
			return TRUE
		if("any")
			for(var/child in children)
				if(om_condition_test(child, listener, source, depth + 1))
					return TRUE
			return FALSE
		if("not")
			return !om_condition_test(children[1], listener, source, depth + 1)
	return FALSE

/proc/om_condition_dependencies(expression, datum/listener, datum/source, depth = 0)
	if(depth > 32)
		CRASH("object model subscription condition nesting exceeded 32")
	if(ispath(expression, /datum/object_model/subscription_condition))
		var/datum/object_model/subscription_condition/C = om_subscription_condition(expression)
		return C.dependencies(listener, source)
	var/list/node = expression
	var/list/result = list()
	if(!islist(node))
		return result
	for(var/child in node["args"])
		result |= om_condition_dependencies(child, listener, source, depth + 1)
	return result

/datum/object_model/subscription_condition
	/// Override for a non-sleeping, side-effect-free predicate.
/datum/object_model/subscription_condition/proc/test(datum/listener, datum/source)
	SHOULD_NOT_SLEEP(TRUE)
	return TRUE

/// Return additional tracked datums whose om_changed() can alter test().
/// Listener and source are watched automatically.
/datum/object_model/subscription_condition/proc/dependencies(datum/listener, datum/source)
	SHOULD_NOT_SLEEP(TRUE)
	return list()

/datum/object_model/subscription_condition/all
	var/list/conditions

/datum/object_model/subscription_condition/all/test(datum/listener, datum/source)
	for(var/path in conditions)
		var/datum/object_model/subscription_condition/C = om_subscription_condition(path)
		if(!C || !C.test(listener, source))
			return FALSE
	return TRUE

/datum/object_model/subscription_condition/all/dependencies(datum/listener, datum/source)
	var/list/result = list()
	for(var/path in conditions)
		var/datum/object_model/subscription_condition/C = om_subscription_condition(path)
		if(C)
			result |= C.dependencies(listener, source)
	return result

/datum/object_model/subscription_condition/any
	var/list/conditions

/datum/object_model/subscription_condition/any/test(datum/listener, datum/source)
	for(var/path in conditions)
		var/datum/object_model/subscription_condition/C = om_subscription_condition(path)
		if(C && C.test(listener, source))
			return TRUE
	return FALSE

/datum/object_model/subscription_condition/any/dependencies(datum/listener, datum/source)
	var/list/result = list()
	for(var/path in conditions)
		var/datum/object_model/subscription_condition/C = om_subscription_condition(path)
		if(C)
			result |= C.dependencies(listener, source)
	return result

/datum/object_model/subscription_condition/not
	var/condition

/datum/object_model/subscription_condition/not/test(datum/listener, datum/source)
	var/datum/object_model/subscription_condition/C = om_subscription_condition(condition)
	return C && !C.test(listener, source)

/datum/object_model/subscription_condition/not/dependencies(datum/listener, datum/source)
	var/datum/object_model/subscription_condition/C = om_subscription_condition(condition)
	return C ? C.dependencies(listener, source) : list()

/proc/om_subscription_condition(path)
	if(!ispath(path, /datum/object_model/subscription_condition))
		return null
	var/static/list/definitions = list()
	var/datum/object_model/subscription_condition/C = definitions[path]
	if(!C)
		C = new path
		definitions[path] = C
	return C

/proc/om_subscription_rule(path)
	if(istype(path, /datum/object_model/subscription_rule))
		return path
	if(!ispath(path, /datum/object_model/subscription_rule))
		return null
	var/static/list/definitions = list()
	var/datum/object_model/subscription_rule/R = definitions[path]
	if(!R)
		R = new path
		definitions[path] = R
	return R

/datum/object_model/subscription_registry
	var/list/by_event = list()
	var/list/by_source = list()
	var/list/by_endpoint = list()

/datum/object_model/subscription_registry/om_kind()
	return OM_KIND_SERVICE

/proc/om_subscription_registry() as /datum/object_model/subscription_registry
	var/static/datum/object_model/subscription_registry/registry
	if(!registry)
		registry = new
	return registry

/// Cheap producer-side check for opt-in typed events on legacy objects that
/// have no object-model state of their own.
/proc/om_event_has_subscribers(datum/source, event_path)
	var/datum/object_model/subscription_registry/registry = om_subscription_registry()
	return length(registry.by_source[source]?[event_path]) || length(registry.by_event[event_path])

/datum/object_model/subscription_registry/proc/add_event(datum/object_model/subscription/S)
	if(S.rule.source_mode != OM_SUBJECT_GLOBAL)
		return
	var/list/subscriptions = by_event[S.rule.event_path]
	if(!subscriptions)
		subscriptions = list()
		by_event[S.rule.event_path] = subscriptions
	subscriptions += S

/datum/object_model/subscription_registry/proc/remove_event(datum/object_model/subscription/S)
	if(S.rule?.source_mode != OM_SUBJECT_GLOBAL)
		return
	var/list/subscriptions = by_event[S.rule?.event_path]
	subscriptions -= S
	if(!length(subscriptions))
		by_event -= S.rule?.event_path

/datum/object_model/subscription_registry/proc/add_source(datum/source, datum/object_model/subscription/S)
	var/list/events = by_source[source]
	if(!events)
		events = list()
		by_source[source] = events
	var/list/subscriptions = events[S.rule.event_path]
	if(!subscriptions)
		subscriptions = list()
		events[S.rule.event_path] = subscriptions
	subscriptions |= S

/datum/object_model/subscription_registry/proc/remove_source(datum/source, datum/object_model/subscription/S)
	var/list/events = by_source[source]
	if(!events)
		return
	var/list/subscriptions = events?[S.rule?.event_path]
	if(!subscriptions)
		return
	subscriptions -= S
	if(!length(subscriptions))
		events -= S.rule?.event_path
	if(!length(events))
		by_source -= source

/datum/object_model/subscription_registry/proc/add_endpoint(datum/endpoint, datum/object_model/subscription/S)
	var/list/subscriptions = by_endpoint[endpoint]
	if(!subscriptions)
		subscriptions = list()
		by_endpoint[endpoint] = subscriptions
	subscriptions |= S

/datum/object_model/subscription_registry/proc/remove_endpoint(datum/endpoint, datum/object_model/subscription/S)
	var/list/subscriptions = by_endpoint[endpoint]
	subscriptions -= S
	if(!length(subscriptions))
		by_endpoint -= endpoint

/datum/object_model/subscription
	var/datum/listener
	var/datum/direct_source
	var/datum/object_model/subscription_rule/rule
	var/list/bound = list()
	var/list/dependencies = list()
	var/list/matched = list()
	var/refreshing = FALSE
	var/refresh_pending = FALSE

/datum/object_model/subscription/proc/start(datum/new_listener, rule_path, datum/new_source, report_initial)
	rule = om_subscription_rule(rule_path)
	if(!new_listener || QDELETED(new_listener) || !rule || !ispath(rule.event_path, /datum/object_model/event) || !istext(rule.handler))
		return FALSE
	if(rule.source_mode == OM_SUBJECT_DIRECT && (!new_source || QDELETED(new_source)))
		return FALSE
	if(rule.source_mode == OM_SUBJECT_RELATED && !om_relation_def(rule.relation_path))
		return FALSE
	if(rule.source_mode != OM_SUBJECT_DIRECT && rule.source_mode != OM_SUBJECT_RELATED && rule.source_mode != OM_SUBJECT_GLOBAL)
		return FALSE
	if(rule.condition_path && !om_subscription_condition(rule.condition_path))
		return FALSE
	listener = new_listener
	direct_source = new_source
	if(!om_claim(listener, "om:subscriptions", src))
		listener = null
		direct_source = null
		return FALSE
	RegisterSignal(listener, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	om_subscription_registry().add_event(src)
	om_subscription_registry().add_endpoint(listener, src)
	refresh(report_initial)
	return TRUE

/datum/object_model/subscription/proc/targets()
	if(rule.source_mode == OM_SUBJECT_DIRECT)
		return list(direct_source)
	if(rule.source_mode == OM_SUBJECT_RELATED)
		return om_linked(listener, rule.relation_path)
	return list()

/datum/object_model/subscription/proc/accepts(datum/source)
	if(rule.source_mode == OM_SUBJECT_GLOBAL)
		return TRUE
	return source in bound

/datum/object_model/subscription/proc/passes(datum/source)
	if(rule.condition_expr)
		return !!om_condition_test(rule.condition_expr, listener, source)
	if(!rule.condition_path)
		return TRUE
	var/datum/object_model/subscription_condition/C = om_subscription_condition(rule.condition_path)
	return !!C.test(listener, source)

/datum/object_model/subscription/proc/refresh(report_new = TRUE)
	if(!listener || QDELETED(listener))
		return
	if(refreshing)
		refresh_pending = TRUE
		return
	refreshing = TRUE
	var/iterations = 0
	while(TRUE)
		refresh_pending = FALSE
		refresh_once(report_new)
		if(!refresh_pending || ++iterations >= 16 || QDELETED(src))
			break
	refreshing = FALSE

/datum/object_model/subscription/proc/refresh_once(report_new)
	var/list/next = targets()
	for(var/datum/source in bound.Copy())
		if(source in next)
			continue
		om_subscription_registry().remove_source(source, src)
		om_subscription_registry().remove_endpoint(source, src)
		if(source && !QDELETED(source))
			UnregisterSignal(source, COMSIG_QDELETING)
		bound -= source
		matched -= source
	for(var/datum/source in next)
		if(!source || QDELETED(source))
			continue
		if(!(source in bound))
			bound += source
			om_subscription_registry().add_source(source, src)
			om_subscription_registry().add_endpoint(source, src)
			if(source != listener)
				RegisterSignal(source, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
		var/now_matches = passes(source)
		if(now_matches && !(source in matched))
			matched += source
			if(report_new && rule.match_handler)
				call(listener, rule.match_handler)(source)
		else if(!now_matches)
			matched -= source
	var/list/next_dependencies = list()
	if(rule.condition_path || rule.condition_expr)
		for(var/datum/source in bound)
			if(rule.condition_expr)
				next_dependencies |= om_condition_dependencies(rule.condition_expr, listener, source)
			else
				var/datum/object_model/subscription_condition/C = om_subscription_condition(rule.condition_path)
				next_dependencies |= C.dependencies(listener, source)
	for(var/datum/endpoint in dependencies.Copy())
		if(endpoint in next_dependencies)
			continue
		om_subscription_registry().remove_endpoint(endpoint, src)
		if(endpoint != listener && !(endpoint in bound) && !QDELETED(endpoint))
			UnregisterSignal(endpoint, COMSIG_QDELETING)
		dependencies -= endpoint
	for(var/datum/endpoint in next_dependencies)
		if(!endpoint || QDELETED(endpoint) || endpoint == listener || (endpoint in bound) || (endpoint in dependencies))
			continue
		dependencies += endpoint
		om_subscription_registry().add_endpoint(endpoint, src)
		RegisterSignal(endpoint, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))

/datum/object_model/subscription/proc/on_endpoint_deleting(datum/source)
	SIGNAL_HANDLER
	if(source == listener || source == direct_source)
		qdel(src)
	else
		// A related target can disappear without ending the listener.
		om_subscription_registry().remove_source(source, src)
		om_subscription_registry().remove_endpoint(source, src)
		bound -= source
		dependencies -= source
		matched -= source

/datum/object_model/subscription/proc/deliver(datum/source, datum/object_model/event/E, a, b, c, d)
	if(!listener || QDELETED(listener) || !accepts(source) || !passes(source))
		return null
	return call(listener, rule.handler)(source, E, a, b, c, d)

/datum/object_model/subscription/Destroy(force = FALSE)
	var/datum/object_model/subscription_registry/registry = om_subscription_registry()
	registry.remove_event(src)
	if(listener)
		registry.remove_endpoint(listener, src)
		if(!QDELETED(listener))
			UnregisterSignal(listener, COMSIG_QDELETING)
	for(var/datum/source in bound)
		registry.remove_source(source, src)
		registry.remove_endpoint(source, src)
		if(source != listener && !QDELETED(source))
			UnregisterSignal(source, COMSIG_QDELETING)
	for(var/datum/endpoint in dependencies)
		registry.remove_endpoint(endpoint, src)
		if(endpoint != listener && !(endpoint in bound) && !QDELETED(endpoint))
			UnregisterSignal(endpoint, COMSIG_QDELETING)
	listener = null
	direct_source = null
	rule = null
	bound = null
	dependencies = null
	matched = null
	return ..()

/// Keep the token to cancel early; otherwise listener ownership cleans it up.
/proc/om_subscribe(datum/listener, rule_path, datum/source = null, report_initial = TRUE)
	var/datum/object_model/subscription/S = new
	if(!S.start(listener, rule_path, source, report_initial))
		qdel(S)
		return null
	return S

/// Install one shared behaviour/archetype plan on a listener. Direct rules
/// require an explicit source and therefore use om_subscribe() separately.
/proc/om_subscribe_plan(datum/listener, datum/object_model/subscription_plan/plan, report_initial = TRUE)
	var/list/tokens = list()
	if(!plan)
		return tokens
	for(var/datum/object_model/subscription_rule/R in plan.rules)
		if(R.source_mode == OM_SUBJECT_DIRECT)
			continue
		var/datum/object_model/subscription/S = om_subscribe(listener, R, null, report_initial)
		if(S)
			tokens += S
	return tokens

/proc/om_deliver_subscriptions(datum/source, datum/object_model/event/E, a, b, c, d)
	var/datum/object_model/subscription_registry/registry = om_subscription_registry()
	var/list/events = registry.by_source[source]
	var/list/subscriptions = events?[E.type]
	if(length(subscriptions))
		for(var/datum/object_model/subscription/S in subscriptions.Copy())
			if(QDELETED(S))
				continue
			var/result = S.deliver(source, E, a, b, c, d)
			if(E.phase == OM_EVENT_BEFORE && !isnull(result))
				return result
	var/list/global_subscriptions = registry.by_event[E.type]
	if(length(global_subscriptions))
		for(var/datum/object_model/subscription/S in global_subscriptions.Copy())
			if(QDELETED(S))
				continue
			var/result = S.deliver(source, E, a, b, c, d)
			if(E.phase == OM_EVENT_BEFORE && !isnull(result))
				return result
	return null

/// Called by checked change producers. Only subscriptions touching this datum refresh.
/proc/om_subscription_on_changed(datum/subject, channel = null)
	var/datum/object_model/subscription_registry/registry = om_subscription_registry()
	var/list/subscriptions = registry.by_endpoint[subject]
	if(!length(subscriptions))
		return
	for(var/datum/object_model/subscription/S in subscriptions.Copy())
		if(!QDELETED(S))
			S.refresh(TRUE)
