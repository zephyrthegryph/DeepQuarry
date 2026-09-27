#define COMSIG_OM_TEST_BRIDGE "om_test_bridge"

/datum/unit_test/om_ntnet_dos_target_lifetime
	needs_test_block = FALSE

/datum/unit_test/om_ntnet_dos_target_lifetime/Run()
	var/datum/computer_file/program/ntnet_dos/program = new
	var/obj/machinery/ntnet_relay/first = new
	var/obj/machinery/ntnet_relay/second = new
	var/relation = /datum/object_model/relation/ntnet_dos_target
	TEST_ASSERT(om_link(program, relation, first), "program can select a relay")
	TEST_ASSERT_EQUAL(program.selected_relay(), first, "program selects first relay")
	TEST_ASSERT_EQUAL(om_first_linked(program, relation), first, "selection has one relation")
	TEST_ASSERT(om_link(program, relation, second), "selecting a second relay replaces the first")
	TEST_ASSERT_EQUAL(program.selected_relay(), second, "program selects second relay")
	TEST_ASSERT(!om_has_link(program, relation, first), "old relay is no longer linked")
	TEST_ASSERT_EQUAL(om_first_linked(program, relation), second, "second relay is linked")
	qdel(second)
	TEST_ASSERT_NULL(program.selected_relay(), "relay deletion clears the selected target")
	TEST_ASSERT_EQUAL(program.error, "Connection to quantum relay severed", "relay deletion reports the disconnect")
	TEST_ASSERT_NULL(om_first_linked(program, relation), "relay deletion removes the relation")
	qdel(first)
	qdel(program)

/datum/object_model/event/test_bridge

/datum/object_model/test_bridge_listener
	var/hits = 0
	var/last_value

/datum/object_model/test_bridge_listener/proc/on_bridge(datum/source, datum/object_model/event/E, value)
	hits++
	last_value = value

/datum/object_model/subscription_rule/test_bridge
	event_path = /datum/object_model/event/test_bridge
	handler = TYPE_PROC_REF(/datum/object_model/test_bridge_listener, on_bridge)

/datum/object_model/behaviour/test_dynamic_grant

/datum/object_model/test_grant_listener
	var/added = 0
	var/removed = 0
	var/last_active = FALSE

/datum/object_model/test_grant_listener/proc/on_grant_changed(datum/source, datum/object_model/event/E, path, datum/grant_source, was_added, is_active)
	if(was_added)
		added++
	else
		removed++
	last_active = is_active

/datum/object_model/subscription_rule/test_grant_change
	event_path = /datum/object_model/event/grant_changed
	handler = TYPE_PROC_REF(/datum/object_model/test_grant_listener, on_grant_changed)

/datum/object_model/test_keyed_grant_listener
	var/added = 0
	var/removed = 0
	var/last_active = FALSE

/datum/object_model/test_keyed_grant_listener/proc/on_keyed_grant_changed(datum/holder, datum/object_model/event/E, key, datum/grant_source, was_added, is_active)
	if(was_added)
		added++
	else
		removed++
	last_active = is_active

/datum/object_model/subscription_rule/test_keyed_grant_change
	event_path = /datum/object_model/event/keyed_grant_changed
	handler = TYPE_PROC_REF(/datum/object_model/test_keyed_grant_listener, on_keyed_grant_changed)

/datum/unit_test/om_keyed_grant_lifetime
	needs_test_block = FALSE

/datum/unit_test/om_keyed_grant_lifetime/Run()
	var/datum/holder = new
	var/datum/source_a = new
	var/datum/source_b = new
	var/datum/object_model/test_keyed_grant_listener/listener = new
	var/datum/object_model/subscription/S = om_subscribe(listener, /datum/object_model/subscription_rule/test_keyed_grant_change, holder)
	TEST_ASSERT_NOTNULL(S, "keyed grant observer starts")
	TEST_ASSERT(om_keyed_grant(holder, "example", source_a), "first keyed grant accepted")
	TEST_ASSERT(om_keyed_grant(holder, "example", source_a), "duplicate keyed grant idempotent")
	TEST_ASSERT(om_keyed_grant(holder, "example", source_b), "second keyed grant accepted")
	TEST_ASSERT_EQUAL(listener.added, 2, "only new grants publish additions")
	TEST_ASSERT_EQUAL(length(om_keyed_sources(holder, "example")), 2, "sources query returns both grants")
	var/list/snapshot = om_keyed_sources(holder, "example")
	snapshot.Cut()
	TEST_ASSERT_EQUAL(length(om_keyed_sources(holder, "example")), 2, "sources query is a private snapshot")
	qdel(source_a)
	TEST_ASSERT(om_keyed_has(holder, "example"), "other source survives source deletion")
	TEST_ASSERT_EQUAL(listener.removed, 1, "source deletion publishes removal")
	TEST_ASSERT(listener.last_active, "remaining source keeps grant active")
	TEST_ASSERT(om_keyed_revoke(holder, "example", source_b), "explicit revoke succeeds")
	TEST_ASSERT(!om_keyed_has(holder, "example"), "last revoke clears grant")
	TEST_ASSERT_NULL(om_keyed_sources(holder, "example"), "empty source query is null")
	TEST_ASSERT_EQUAL(listener.removed, 2, "explicit revoke publishes removal")
	TEST_ASSERT(!listener.last_active, "last revoke reports inactive grant")
	qdel(source_b)
	qdel(holder)
	qdel(listener)

/datum/unit_test/om_grant_relations
	needs_test_block = FALSE

/datum/unit_test/om_grant_relations/Run()
	var/datum/object_model/test_subscription_host/recipient = new
	var/datum/object_model/test_grant_listener/listener = new
	var/datum/object_model/subscription/watch = om_subscribe(listener, /datum/object_model/subscription_rule/test_grant_change, recipient)
	TEST_ASSERT_NOTNULL(watch, "grant observer starts")
	var/datum/source = new
	var/path = /datum/object_model/behaviour/test_dynamic_grant
	TEST_ASSERT(om_behaviour_grant(recipient, path, source), "grant accepted")
	var/datum/object_model/behaviour_runtime/R = recipient.om_state?.behaviour_runtime
	TEST_ASSERT_EQUAL(length(R.grants[path]), 1, "one grant token indexed")
	TEST_ASSERT(om_behaviour_has_grant(recipient, path, source), "grant query finds source")
	TEST_ASSERT_EQUAL(listener.added, 1, "grant addition publishes typed event")
	TEST_ASSERT(listener.last_active, "grant event reports active behaviour")
	var/datum/object_model/behaviour_grant/G = R.grants[path][1]
	TEST_ASSERT_EQUAL(om_owner(G), recipient, "recipient owns grant")
	TEST_ASSERT(om_has_link(G, /datum/object_model/relation/grant_source, source), "grant tracks source")
	TEST_ASSERT(om_behaviour_grant(recipient, path, source), "duplicate grant is idempotent")
	TEST_ASSERT_EQUAL(length(R.grants[path]), 1, "no duplicate token")
	var/datum/other_source = new
	TEST_ASSERT(om_behaviour_grant(recipient, path, other_source), "second source grants independently")
	TEST_ASSERT_EQUAL(length(R.grants[path]), 2, "both grant sources indexed")
	TEST_ASSERT_EQUAL(length(om_behaviour_grant_sources(recipient, path)), 2, "source snapshot reports both")
	qdel(source)
	TEST_ASSERT(QDELETED(G), "source deletion destroys grant")
	TEST_ASSERT_EQUAL(length(R.grants[path]), 1, "other source keeps behaviour granted")
	TEST_ASSERT_EQUAL(listener.removed, 1, "source deletion publishes revocation")
	TEST_ASSERT(listener.last_active, "second grant preserves active behaviour")
	TEST_ASSERT(om_behaviour_revoke(recipient, path, other_source), "explicit revoke succeeds")
	TEST_ASSERT(!length(R.grants[path]), "last revoke removes grant index")
	TEST_ASSERT_EQUAL(listener.removed, 2, "explicit revoke publishes revocation")
	TEST_ASSERT(!listener.last_active, "last revoke reports inactive behaviour")
	qdel(other_source)
	qdel(recipient)
	qdel(listener)

/datum/unit_test/om_signal_bridge
	needs_test_block = FALSE

/datum/unit_test/om_signal_bridge/Run()
	var/datum/source = new
	var/datum/object_model/test_bridge_listener/listener = new
	var/datum/object_model/subscription/S = om_subscribe(listener, /datum/object_model/subscription_rule/test_bridge, source)
	TEST_ASSERT_NOTNULL(S, "typed event subscription starts")
	var/datum/object_model/signal_bridge/B = om_bridge_signal(source, COMSIG_OM_TEST_BRIDGE, /datum/object_model/event/test_bridge)
	TEST_ASSERT_NOTNULL(B, "legacy signal bridge starts")
	TEST_ASSERT_EQUAL(om_bridge_signal(source, COMSIG_OM_TEST_BRIDGE, /datum/object_model/event/test_bridge), B, "bridge is idempotent")
	SEND_SIGNAL(source, COMSIG_OM_TEST_BRIDGE, 17)
	TEST_ASSERT_EQUAL(listener.hits, 1, "legacy signal reaches typed observer once")
	TEST_ASSERT_EQUAL(listener.last_value, 17, "bridge carries payload")
	qdel(source)
	TEST_ASSERT(QDELETED(B), "source owns bridge")
	qdel(listener)

#undef COMSIG_OM_TEST_BRIDGE
