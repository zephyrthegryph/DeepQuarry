/datum/object_model/test_subscription_entity
	var/powered = TRUE
	var/healthy = TRUE
	var/hits = 0
	var/matches = 0

/datum/object_model/test_subscription_entity/proc/on_test_event(datum/source, datum/object_model/event/E, a, b, c, d)
	hits++

/datum/object_model/test_subscription_entity/proc/on_test_match(datum/source)
	matches++

/datum/object_model/event/test_subscription_ping

/datum/object_model/global_observer/test_ping
	var/hits = 0

/datum/object_model/global_observer/test_ping/declare_observers(datum/object_model/subscription_plan/P)
	P.on(/datum/object_model/event/test_subscription_ping, PROC_REF(on_ping)).from_any()

/datum/object_model/global_observer/test_ping/proc/on_ping(datum/source, datum/object_model/event/E, a, b, c, d)
	hits++

/datum/unit_test/om_global_observer_singleton
	needs_test_block = FALSE

/datum/unit_test/om_global_observer_singleton/Run()
	var/datum/object_model/subscription_plan/entity_plan = new
	entity_plan.on(/datum/object_model/event/test_subscription_ping, TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_event)).from_any()
	var/list/errors = list()
	om_validate_observer_plan(entity_plan, /datum/object_model/test_subscription_entity, errors)
	TEST_ASSERT(length(errors), "entity plans should reject global fanout rules")
	var/datum/object_model/global_observer/test_ping/system = om_global_observer(/datum/object_model/global_observer/test_ping)
	TEST_ASSERT(system && om_global_observer(/datum/object_model/global_observer/test_ping) == system, "global observer should be a singleton")
	TEST_ASSERT_EQUAL(length(system.subscriptions), 1, "one global rule should allocate one subscription")
	var/datum/object_model/test_subscription_entity/first = new
	var/datum/object_model/test_subscription_entity/second = new
	om_emit(first, /datum/object_model/event/test_subscription_ping)
	om_emit(second, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(system.hits, 2, "one global listener should receive events from both sources")
	var/datum/object_model/subscription/token = system.subscriptions[1]
	qdel(system)
	TEST_ASSERT(QDELETED(token), "deleting a global observer should cancel its subscription")
	var/datum/object_model/global_observer/test_ping/restarted = om_global_observer(/datum/object_model/global_observer/test_ping)
	TEST_ASSERT(restarted && restarted != system && length(restarted.subscriptions) == 1, "global observer should restart cleanly")
	qdel(restarted)
	qdel(first)
	qdel(second)

/datum/object_model/relation/test_subscription_target
	from_type = /datum/object_model/test_subscription_entity
	to_type = /datum/object_model/test_subscription_entity
	shape = OM_REL_ONE_TO_ONE

/datum/object_model/subscription_condition/test_powered
/datum/object_model/subscription_condition/test_powered/test(datum/listener, datum/source)
	var/datum/object_model/test_subscription_entity/L = listener
	return L.powered

/datum/object_model/subscription_condition/test_healthy
/datum/object_model/subscription_condition/test_healthy/test(datum/listener, datum/source)
	var/datum/object_model/test_subscription_entity/S = source
	return S.healthy

/datum/object_model/subscription_condition/all/test_ready
	conditions = list(/datum/object_model/subscription_condition/test_powered, /datum/object_model/subscription_condition/test_healthy)

/datum/object_model/subscription_condition/not/test_unhealthy
	condition = /datum/object_model/subscription_condition/test_healthy

/datum/object_model/subscription_condition/any/test_ready_or_unhealthy
	conditions = list(/datum/object_model/subscription_condition/all/test_ready, /datum/object_model/subscription_condition/not/test_unhealthy)

/datum/object_model/subscription_rule/test_direct
	event_path = /datum/object_model/event/test_subscription_ping
	condition_path = /datum/object_model/subscription_condition/all/test_ready
	handler = TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_event)
	match_handler = TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_match)

/datum/object_model/subscription_rule/test_related
	event_path = /datum/object_model/event/test_subscription_ping
	source_mode = OM_SUBJECT_RELATED
	relation_path = /datum/object_model/relation/test_subscription_target
	handler = TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_event)
	match_handler = TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_match)

/datum/object_model/subscription_rule/test_global
	event_path = /datum/object_model/event/test_subscription_ping
	source_mode = OM_SUBJECT_GLOBAL
	condition_path = /datum/object_model/subscription_condition/any/test_ready_or_unhealthy
	handler = TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_event)

/datum/object_model/test_subscription_host
	parent_type = /datum/object_model/test_subscription_entity

/datum/object_model/behaviour/test_subscription_auto

/datum/object_model/behaviour/test_subscription_auto/declare_observers(datum/object_model/subscription_plan/P)
	var/datum/object_model/subscription_rule/R = P.on(/datum/object_model/event/test_subscription_ping, TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_event))
	R.from_related(/datum/object_model/relation/test_subscription_target)
	R.when_all(list(/datum/object_model/subscription_condition/test_powered, /datum/object_model/subscription_condition/test_healthy))
	R.on_match(TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_match))

/datum/object_model/declaration/test_subscription_host
	target_type = /datum/object_model/test_subscription_host

/datum/object_model/declaration/test_subscription_host/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/behaviour/test_subscription_auto)

/datum/unit_test/om_subscriptions
	needs_test_block = FALSE

/datum/unit_test/om_subscriptions/Run()
	var/datum/object_model/test_subscription_entity/listener = new
	var/datum/object_model/test_subscription_entity/first = new
	var/datum/object_model/test_subscription_entity/second = new
	var/datum/object_model/subscription/direct = om_subscribe(listener, /datum/object_model/subscription_rule/test_direct, first)
	TEST_ASSERT_NOTNULL(direct, "direct subscription starts")
	TEST_ASSERT_EQUAL(listener.matches, 1, "initial match refreshes")
	om_emit(first, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(listener.hits, 1, "direct rule receives event without archetype")
	listener.powered = FALSE
	om_changed(listener)
	om_emit(first, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(listener.hits, 1, "condition gates event")
	listener.powered = TRUE
	om_changed(listener)
	TEST_ASSERT_EQUAL(listener.matches, 2, "condition becoming true refreshes snapshot")
	var/datum/object_model/subscription/related = om_subscribe(listener, /datum/object_model/subscription_rule/test_related)
	TEST_ASSERT_NOTNULL(related, "related subscription starts")
	TEST_ASSERT(om_link(listener, /datum/object_model/relation/test_subscription_target, first), "first target links")
	om_emit(first, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(listener.hits, 3, "direct and related rules receive first target")
	TEST_ASSERT(om_link(listener, /datum/object_model/relation/test_subscription_target, second), "target replacement links")
	om_emit(first, /datum/object_model/event/test_subscription_ping)
	om_emit(second, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(listener.hits, 5, "related rule follows replacement only")
	var/datum/object_model/subscription/global_subscription = om_subscribe(listener, /datum/object_model/subscription_rule/test_global)
	TEST_ASSERT_NOTNULL(global_subscription, "global rule starts")
	om_emit(second, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(listener.hits, 7, "global rule receives event")
	var/datum/object_model/test_subscription_entity/built_listener = new
	var/datum/object_model/subscription_plan/P = new
	var/datum/object_model/subscription_rule/R = P.on(/datum/object_model/event/test_subscription_ping, TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_event))
	R.from_related(/datum/object_model/relation/test_subscription_target)
	R.when_all(list(/datum/object_model/subscription_condition/test_powered, om_condition_not(/datum/object_model/subscription_condition/test_healthy)))
	R.on_match(TYPE_PROC_REF(/datum/object_model/test_subscription_entity, on_test_match))
	var/list/built_tokens = om_subscribe_plan(built_listener, P)
	TEST_ASSERT_EQUAL(length(built_tokens), 1, "builder plan installs one related token")
	om_link(built_listener, /datum/object_model/relation/test_subscription_target, second)
	om_emit(second, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(built_listener.hits, 0, "composed rule gates healthy target")
	second.healthy = FALSE
	om_changed(second)
	TEST_ASSERT_EQUAL(built_listener.matches, 1, "composed rule refreshes when target matches")
	om_emit(second, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(built_listener.hits, 1, "composed rule receives matching target event")
	qdel(built_listener)
	var/datum/object_model/test_subscription_host/auto_host = new
	TEST_ASSERT_NOTNULL(om_behaviour_start(auto_host), "behaviour starts with declared observer plan")
	var/datum/object_model/test_subscription_entity/auto_target = new
	om_link(auto_host, /datum/object_model/relation/test_subscription_target, auto_target)
	TEST_ASSERT_EQUAL(auto_host.matches, 1, "activated behaviour observes related target")
	om_emit(auto_target, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(auto_host.hits, 1, "activated behaviour receives event")
	om_behaviour_release(auto_host)
	om_emit(auto_target, /datum/object_model/event/test_subscription_ping)
	TEST_ASSERT_EQUAL(auto_host.hits, 1, "deactivation cancels declared observer")
	qdel(auto_host)
	qdel(auto_target)
	qdel(listener)
	TEST_ASSERT(QDELETED(direct) && QDELETED(related) && QDELETED(global_subscription), "listener deletion cancels subscriptions")
	qdel(first)
	qdel(second)
