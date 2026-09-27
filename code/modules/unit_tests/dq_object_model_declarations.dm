/datum/object_model/test_entity
	var/enabled = TRUE
	var/hits = 0

/datum/interaction/om_declared_probe
	id = "om_declared_probe"
	name = "Declared probe"
	effect = /obj/item/proc/om_interaction_probe_effect

/datum/interaction/om_legacy_probe
	id = "om_legacy_probe"
	name = "Legacy probe"
	effect = /obj/item/proc/om_interaction_probe_effect

/obj/item/proc/om_interaction_probe_effect(mob/actor, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/item/om_interaction_probe
	name = "object-model interaction probe"

/obj/item/om_interaction_probe/declare_interactions(list/into)
	..()
	into += /datum/interaction/om_legacy_probe
	into += /datum/interaction/om_declared_probe

/obj/item/om_interaction_probe/child

/datum/object_model/declaration/om_interaction_probe
	target_type = /obj/item/om_interaction_probe

/datum/object_model/declaration/om_interaction_probe/build(datum/object_model/archetype/A)
	A.interaction(/datum/interaction/om_declared_probe)

/obj/item/om_static_interaction_probe
	name = "static object-model interaction probe"

/obj/item/om_static_interaction_probe/child

/datum/object_model/declaration/om_static_interaction_probe
	target_type = /obj/item/om_static_interaction_probe

/datum/object_model/declaration/om_static_interaction_probe/build(datum/object_model/archetype/A)
	A.interaction(/datum/interaction/om_declared_probe)

/datum/unit_test/dq_object_model_declared_interactions
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_declared_interactions/Run()
	var/turf/spawn_turf = locate(1, 1, 1)
	var/obj/item/om_interaction_probe/child/probe = new_unmaterialized(/obj/item/om_interaction_probe/child, spawn_turf)
	var/list/candidates = interaction_candidates(probe)
	var/datum/interaction/declared = INTERACTION(/datum/interaction/om_declared_probe)
	var/datum/interaction/legacy = INTERACTION(/datum/interaction/om_legacy_probe)
	var/obj/item/om_static_interaction_probe/child/static_probe = new_unmaterialized(/obj/item/om_static_interaction_probe/child, spawn_turf)
	var/list/static_candidates = interaction_candidates(static_probe)
	TEST_ASSERT(declared in static_candidates, "Static-only inherited interaction was absent before materialization")
	TEST_ASSERT(!(legacy in static_candidates), "Static-only probe inherited an unrelated legacy interaction")
	qdel(static_probe)
	TEST_ASSERT(declared in candidates, "Inherited static interaction was absent before materialization")
	TEST_ASSERT(legacy in candidates, "Legacy declare_interactions path was lost")
	var/declared_count = 0
	for(var/datum/interaction/I as anything in candidates)
		if(I == declared)
			declared_count++
	TEST_ASSERT_EQUAL(declared_count, 1, "Static and legacy paths created duplicate candidates")
	probe.materialize()
	TEST_ASSERT_EQUAL(interaction_candidates(probe), candidates, "Materialization changed per-type interaction candidates")
	qdel(probe)
	var/obj/item/om_interaction_probe/child/again = new(spawn_turf)
	TEST_ASSERT_EQUAL(interaction_candidates(again), candidates, "Deleting an instance invalidated static candidates")
	qdel(again)
	var/datum/object_model/archetype/duplicate = new
	duplicate.entity_type = /obj/item/om_interaction_probe
	duplicate.interaction(/datum/interaction/om_declared_probe)
	duplicate.interaction(/datum/interaction/om_declared_probe)
	TEST_ASSERT(!duplicate.validate(), "Duplicate interaction path was accepted")
	var/datum/object_model/archetype/invalid = new
	invalid.entity_type = /obj/item/om_interaction_probe
	invalid.interaction(/obj/item)
	TEST_ASSERT(!invalid.validate(), "Non-interaction path was accepted")

/datum/object_model/test_entity/child

/datum/object_model/requirement/test_enabled
	failure_message = "disabled"

/datum/object_model/requirement/test_enabled/check(datum/source, mob/actor, atom/target, obj/item/held)
	var/datum/object_model/test_entity/E = source
	return E.enabled

/datum/object_model/event/test_ping

/datum/object_model/behaviour/test_ping
	requires = list(/datum/object_model/requirement/test_enabled)
	events = list(/datum/object_model/event/test_ping)
	config_schema = list("increment" = 1)

/datum/object_model/behaviour/test_ping/on_event(datum/source, datum/object_model/event/E, a, b, c, d, list/config)
	var/datum/object_model/test_entity/entity = source
	entity.hits += config["increment"]

/datum/object_model/behaviour/test_granted
	events = list(/datum/object_model/event/test_ping)
	states = list("idle", "working")
	initial_state = "idle"
	transitions = list("idle" = list("working"), "working" = list("idle"))

/datum/object_model/behaviour/test_granted/on_event(datum/source, datum/object_model/event/E, a, b, c, d, list/config)
	var/datum/object_model/test_entity/entity = source
	entity.hits += 5

/datum/object_model/declaration/test_entity
	target_type = /datum/object_model/test_entity

/datum/object_model/declaration/test_entity/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/behaviour/test_ping, list("increment" = 2))
	A.slot("children", /datum/object_model/test_entity, 1, OM_SLOT_DELETE)

/datum/object_model/declaration/test_entity_child
	target_type = /datum/object_model/test_entity/child

/datum/object_model/declaration/test_entity_child/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/behaviour/test_granted)

/datum/unit_test/dq_object_model_declarations
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_declarations/Run()
	var/list/failures = om_validate_declarations()
	TEST_ASSERT(!length(failures), "Static archetype declarations validate: [jointext(failures, "; ")]")
	var/datum/object_model/archetype/body_base = om_archetype_for(/datum/body)
	var/datum/object_model/archetype/body_child = om_archetype_for(/datum/body/humanoid)
	TEST_ASSERT(body_base && body_child && body_base != body_child, "body subtype has its own archetype without constructing a body")
	TEST_ASSERT(body_child.tracked_groups == body_base.tracked_groups, "body subtype did not inherit its static declaration")
	TEST_ASSERT(/datum/object_model/behaviour/body_factor_view in body_child.behaviours, "body subtype lost its inherited factor behaviour")
	var/datum/object_model/archetype/affliction_child = om_archetype_for(/datum/affliction/acute_pain)
	TEST_ASSERT(affliction_child && affliction_child.tracked_groups & OM_AFFLICTION_CHANGE_SEVERITY, "affliction subtype did not inherit its static declaration")
	TEST_ASSERT_EQUAL(length(om_declaration_lineage_for(/datum/object_model/test_entity/child)), 2, "child static declaration lineage is incomplete")
	var/datum/object_model/archetype/declared_child = om_archetype_for(/datum/object_model/test_entity/child)
	TEST_ASSERT(/datum/object_model/behaviour/test_ping in declared_child.behaviours, "child declaration lost the parent behaviour")
	TEST_ASSERT(/datum/object_model/behaviour/test_granted in declared_child.behaviours, "child declaration did not add its own behaviour")
	var/datum/object_model/test_entity/child/slot_owner = new
	var/datum/object_model/test_entity/first_child = new
	var/datum/object_model/test_entity/second_child = new
	TEST_ASSERT(om_claim(slot_owner, "children", first_child), "subtype did not accept an inherited declared slot")
	TEST_ASSERT(!om_claim(slot_owner, "children", second_child), "subtype did not enforce inherited slot capacity")
	TEST_ASSERT(!om_claim(slot_owner, "undeclared", second_child), "subtype allowed an undeclared slot")
	qdel(slot_owner)
	qdel(second_child)
	var/datum/object_model/archetype/A = om_archetype_for(/datum/object_model/test_entity)
	TEST_ASSERT_NOTNULL(A, "Static declaration builds without constructing an entity")
	var/datum/object_model/test_entity/entity = new
	om_emit(entity, /datum/object_model/event/test_ping)
	TEST_ASSERT_EQUAL(entity.hits, 2, "Static event handler uses per-type config")
	entity.enabled = FALSE
	om_emit(entity, /datum/object_model/event/test_ping)
	TEST_ASSERT_EQUAL(entity.hits, 2, "Requirement suspends event delivery")
	entity.enabled = TRUE
	var/datum/object_model/behaviour_runtime/runtime = om_behaviour_start(entity)
	TEST_ASSERT_NOTNULL(runtime, "Behaviour runtime starts sparsely")
	entity.enabled = FALSE
	om_changed(entity)
	TEST_ASSERT(!runtime.active[/datum/object_model/behaviour/test_ping], "Observable write deactivates a behaviour immediately")
	entity.enabled = TRUE
	om_changed(entity)
	TEST_ASSERT(runtime.active[/datum/object_model/behaviour/test_ping], "Observable write reactivates a behaviour immediately")
	var/datum/grant_source = new
	TEST_ASSERT(om_behaviour_grant(entity, /datum/object_model/behaviour/test_granted, grant_source), "Dynamic behaviour grant succeeds")
	TEST_ASSERT(om_behaviour_transition(entity, /datum/object_model/behaviour/test_granted, "working"), "Declared state transition succeeds")
	TEST_ASSERT(!om_behaviour_transition(entity, /datum/object_model/behaviour/test_granted, "missing"), "Undeclared state is rejected")
	om_emit(entity, /datum/object_model/event/test_ping)
	TEST_ASSERT_EQUAL(entity.hits, 9, "Static and granted handlers both run")
	om_behaviour_revoke(entity, /datum/object_model/behaviour/test_granted, grant_source)
	om_emit(entity, /datum/object_model/event/test_ping)
	TEST_ASSERT_EQUAL(entity.hits, 11, "Revoked handler no longer runs")
	qdel(grant_source)
	qdel(entity)

/datum/object_model/interface/test_contract

/datum/object_model/interface/test_contract/validate_provider(datum/object_model/behaviour/B)
	return hascall(B, "provide_value") ? null : "missing provide_value()"

/datum/object_model/behaviour/test_contract_good
	provides = list(/datum/object_model/interface/test_contract)

/datum/object_model/behaviour/test_contract_good/proc/provide_value()
	return 1

/datum/object_model/behaviour/test_contract_bad
	provides = list(/datum/object_model/interface/test_contract)

/datum/object_model/behaviour/test_contract_consumer
	needs = list(/datum/object_model/interface/test_contract)

/datum/unit_test/om_interface_contract_validation
	needs_test_block = FALSE

/datum/unit_test/om_interface_contract_validation/Run()
	var/datum/object_model/archetype/good = new
	good.entity_type = /datum/object_model/test_entity
	good.add(/datum/object_model/behaviour/test_contract_good)
	good.add(/datum/object_model/behaviour/test_contract_consumer)
	TEST_ASSERT(good.validate(), "Provider with the required proc satisfies the interface")
	var/datum/object_model/archetype/bad = new
	bad.entity_type = /datum/object_model/test_entity
	bad.add(/datum/object_model/behaviour/test_contract_bad)
	bad.add(/datum/object_model/behaviour/test_contract_consumer)
	TEST_ASSERT(!bad.validate(), "Provider missing the interface proc fails validation")
	qdel(good)
	qdel(bad)

/datum/object_model/test_reentrant_refresh
	var/enabled = TRUE
	var/activations = 0
	var/deactivations = 0

/datum/object_model/test_reentrant_refresh/om_declare(datum/object_model/archetype/A)
	..()
	A.add(/datum/object_model/behaviour/test_reentrant_refresh)

/datum/object_model/requirement/test_reentrant_refresh_enabled

/datum/object_model/requirement/test_reentrant_refresh_enabled/check(datum/source, mob/actor, atom/target, obj/item/held)
	var/datum/object_model/test_reentrant_refresh/entity = source
	return entity.enabled

/datum/object_model/behaviour/test_reentrant_refresh
	requires = list(/datum/object_model/requirement/test_reentrant_refresh_enabled)
	period = 1 SECOND

/datum/object_model/behaviour/test_reentrant_refresh/on_activate(datum/source, list/config)
	var/datum/object_model/test_reentrant_refresh/entity = source
	entity.activations++
	entity.enabled = FALSE
	om_changed(entity)

/datum/object_model/behaviour/test_reentrant_refresh/on_deactivate(datum/source, list/config, reason)
	var/datum/object_model/test_reentrant_refresh/entity = source
	entity.deactivations++

/datum/unit_test/om_reentrant_behaviour_refresh
	needs_test_block = FALSE

/datum/unit_test/om_reentrant_behaviour_refresh/Run()
	var/datum/object_model/test_reentrant_refresh/entity = new
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(entity)
	var/path = /datum/object_model/behaviour/test_reentrant_refresh
	TEST_ASSERT_NOTNULL(R, "Reentrant behaviour runtime starts")
	TEST_ASSERT_EQUAL(entity.activations, 1, "Initial activation ran once")
	TEST_ASSERT_EQUAL(entity.deactivations, 1, "Nested change deactivated after activation")
	TEST_ASSERT(!R.active[path], "Nested change left behaviour dormant")
	TEST_ASSERT(!R.periodic_entries[path], "Nested change cleaned periodic work")
	entity.enabled = TRUE
	om_changed(entity)
	TEST_ASSERT_EQUAL(entity.activations, 2, "Observable write activated once")
	TEST_ASSERT_EQUAL(entity.deactivations, 2, "Nested change deactivated once")
	TEST_ASSERT(!R.periodic_entries[path], "Second refresh left no periodic work")
	qdel(entity)
