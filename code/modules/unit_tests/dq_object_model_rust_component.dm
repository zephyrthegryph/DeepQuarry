/datum/object_model/rust_test_entity
	var/events_seen = 0

/datum/object_model/behaviour/rust_test_event
	events = list(/datum/object_model/event/rust/pump_target_reached)

/datum/object_model/behaviour/rust_test_event/on_event(datum/source, datum/object_model/event/E, a, b, c, d, list/config)
	var/datum/object_model/rust_test_entity/entity = source
	entity.events_seen++

/datum/object_model/declaration/rust_test_entity
	target_type = /datum/object_model/rust_test_entity

/datum/object_model/declaration/rust_test_entity/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/behaviour/rust_test_event)

/datum/unit_test/dq_object_model_rust_component
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_rust_component/Run()
	var/datum/object_model/rust_component/pump/P = om_rust_component(/datum/object_model/rust_component/pump)
	TEST_ASSERT_EQUAL(P.dm_type, /obj/machinery/atmospherics/binary/pump, "Rust pump schema retains its target type")
	var/datum/object_model/archetype/A = new
	A.entity_type = /obj/machinery/atmospherics/binary/pump
	A.add(/datum/object_model/rust_component/pump, list("target_pressure" = 120))
	TEST_ASSERT(A.validate(), "A valid pump component declaration passes")
	var/list/config = A.components[/datum/object_model/rust_component/pump]
	TEST_ASSERT_EQUAL(config["target_pressure"], 120, "Declared config is retained")
	TEST_ASSERT_EQUAL(config["power_rating"], 7500, "Missing config uses the Rust default")
	var/datum/object_model/archetype/bad = new
	bad.entity_type = /obj/machinery/atmospherics/binary/pump
	bad.add(/datum/object_model/rust_component/pump, list("target_pressure" = 20000, "typo" = 1))
	TEST_ASSERT(!bad.validate(), "Unknown and out-of-range config fails validation")
	var/datum/object_model/rust_test_entity/entity = new
	P.dispatch_event(entity, VG_PUMP_EVENT_TARGET_REACHED)
	TEST_ASSERT_EQUAL(entity.events_seen, 1, "Generated Rust event ID dispatches to object-model behaviour")
	qdel(entity)

/obj/machinery/atmospherics/binary/pump/om_mixed_rust_binding_test
	name = "mixed Rust binding test pump"

/obj/machinery/atmospherics/binary/pump/om_mixed_rust_binding_test/inherited
	name = "inherited mixed Rust binding test pump"

/datum/object_model/declaration/om_mixed_rust_binding_test
	target_type = /obj/machinery/atmospherics/binary/pump/om_mixed_rust_binding_test

/datum/object_model/declaration/om_mixed_rust_binding_test/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/rust_component/pump, list("target_pressure" = 333, "power_rating" = 7500, "on" = FALSE))

// A deliberately disagreeing declaration exercises materialization preflight.
/datum/object_model/rust_component/pump/conflicting_test
	kind = VG_GAS_GASMIX

/datum/object_model/rust_component/pump/conflicting_test/bind(atom/movable/entity, handle, list/config)
	return vg_gas_mix_bind(handle, 300, 70)

/obj/machinery/atmospherics/binary/pump/om_mixed_rust_conflict_test
	name = "conflicting Rust binding test pump"

/datum/object_model/declaration/om_mixed_rust_conflict_test
	target_type = /obj/machinery/atmospherics/binary/pump/om_mixed_rust_conflict_test

/datum/object_model/declaration/om_mixed_rust_conflict_test/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/rust_component/pump/conflicting_test)

// Forces a failure after the generated pump binder has attached its gas row.
/datum/object_model/rust_component/pump/failing_later_test
	domain = "rollback_test"
	domain_id = 2
	kind = 1

/datum/object_model/rust_component/pump/failing_later_test/bind(atom/movable/entity, handle, list/config)
	return 0

/obj/machinery/atmospherics/binary/pump/om_mixed_rust_rollback_test
	name = "Rust binding rollback test pump"

/datum/object_model/declaration/om_mixed_rust_rollback_test
	target_type = /obj/machinery/atmospherics/binary/pump/om_mixed_rust_rollback_test

/datum/object_model/declaration/om_mixed_rust_rollback_test/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/rust_component/pump)
	A.add(/datum/object_model/rust_component/pump/failing_later_test)

/datum/unit_test/dq_object_model_rust_bind_rollback
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_rust_bind_rollback/Run()
	var/turf/spawn_turf = locate(1, 1, 1)
	var/baseline = vg_entity_count()
	var/obj/machinery/atmospherics/binary/pump/om_mixed_rust_rollback_test/P = new_unmaterialized(/obj/machinery/atmospherics/binary/pump/om_mixed_rust_rollback_test, spawn_turf)
	TEST_ASSERT(!om_rust_bind(P), "Failed second component unexpectedly completed a fresh bind")
	TEST_ASSERT_EQUAL(P.vg_entity, 0, "Failed fresh bind published a handle")
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline, "Failed fresh bind leaked a Rust entity")
	var/heat_handle = vg_heat_mob_bind(0, 1000, 300, 0, FALSE, 1, 293, BODYTEMP_NORMAL, 0, 0, 1)
	TEST_ASSERT(heat_handle, "Borrowed heat entity did not bind")
	P.vg_entity = heat_handle
	TEST_ASSERT(!om_rust_bind(P), "Failed second component unexpectedly completed a borrowed bind")
	TEST_ASSERT_EQUAL(P.vg_entity, heat_handle, "Failed borrowed bind changed its handle")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(heat_handle, VG_DOMAIN_GAS), 0, "Failed borrowed bind left its newly added gas component")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(heat_handle, VG_DOMAIN_HEAT_MOB), VG_HEAT_MOB_KIND, "Rollback removed the preexisting heat component")
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline + 1, "Rollback removed or leaked the borrowed entity")
	om_rust_unbind(P)
	qdel(P)
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline, "Rollback test left a Rust entity behind")

/datum/unit_test/dq_object_model_rust_mixed_binding
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_rust_mixed_binding/Run()
	var/turf/spawn_turf = locate(1, 1, 1)
	var/baseline = vg_entity_count()
	var/obj/machinery/atmospherics/binary/pump/om_mixed_rust_binding_test/P = new(spawn_turf)
	var/handle = P.vg_entity
	TEST_ASSERT(handle, "Converted pump did not bind")
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline + 1, "Mixed declaration created more than one entity")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(handle, VG_DOMAIN_GAS), VG_GAS_PUMP, "Declared pump component was not installed")
	TEST_ASSERT_EQUAL(P.get_target_pressure(), 333, "Legacy bind replaced the declared component config")
	TEST_ASSERT_EQUAL(P.vg_bind(), handle, "Repeated legacy bind did not adopt the same handle")
	TEST_ASSERT_EQUAL(om_rust_bind(P), handle, "Repeated declaration bind did not adopt the same handle")
	TEST_ASSERT_EQUAL(P.get_target_pressure(), 333, "Repeated bind replaced declared component state")

	om_rust_unbind(P)
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline, "Initial unbind leaked the converted entity")
	var/legacy_handle = P.vg_bind()
	TEST_ASSERT(legacy_handle, "Legacy-first bind did not create a handle")
	TEST_ASSERT_EQUAL(om_rust_bind(P), legacy_handle, "Declaration did not adopt legacy component")
	TEST_ASSERT_EQUAL(P.vg_entity, legacy_handle, "Declaration changed legacy handle")
	TEST_ASSERT_EQUAL(P.get_target_pressure(), ONE_ATMOSPHERE, "Declaration replaced a matching legacy component")
	om_rust_unbind(P)

	var/heat_handle = vg_heat_mob_bind(0, 1000, 300, 0, FALSE, 1, 293, BODYTEMP_NORMAL, 0, 0, 1)
	TEST_ASSERT(heat_handle, "Heat component did not establish an existing handle")
	P.vg_entity = heat_handle
	TEST_ASSERT_EQUAL(vg_entity_component_kind(heat_handle, VG_DOMAIN_HEAT_MOB), VG_HEAT_MOB_KIND, "Heat component was missing before declaration bind")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(heat_handle, VG_DOMAIN_GAS), 0, "Heat-only entity unexpectedly had a gas component")
	TEST_ASSERT_EQUAL(om_rust_bind(P), heat_handle, "Declaration did not install onto an existing handle")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(heat_handle, VG_DOMAIN_GAS), VG_GAS_PUMP, "Declared gas component was not installed beside heat")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(heat_handle, VG_DOMAIN_HEAT_MOB), VG_HEAT_MOB_KIND, "Gas install disturbed existing heat component")
	TEST_ASSERT_EQUAL(P.vg_bind(), heat_handle, "Legacy bind did not preserve the mixed-domain entity")
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline + 1, "Mixed-domain install created a second entity")
	om_rust_unbind(P)

	var/conflict_handle = vg_gas_mix_bind(0, 300, 70)
	TEST_ASSERT(conflict_handle, "Conflicting gas component did not bind")
	P.vg_entity = conflict_handle
	TEST_ASSERT(!om_rust_bind(P), "Declaration silently replaced a different gas kind")
	TEST_ASSERT(!P.vg_bind(), "Legacy bind silently replaced a different gas kind")
	TEST_ASSERT_EQUAL(P.vg_entity, conflict_handle, "Conflict changed the existing entity handle")
	TEST_ASSERT_EQUAL(vg_entity_component_kind(conflict_handle, VG_DOMAIN_GAS), VG_GAS_GASMIX, "Conflict replaced the existing gas component")
	TEST_ASSERT(!P.vg_bind_for_materialization(), "Materialization accepted an incompatible entity")
	TEST_ASSERT(!(P in SSvg.bound), "Failed mixed bind registered an incompatible entity")
	TEST_ASSERT_EQUAL(P.vg_entity, conflict_handle, "Failed materialization discarded the existing handle")
	om_rust_unbind(P)
	qdel(P)
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline, "Mixed binding left a Rust entity behind")
	var/obj/machinery/atmospherics/binary/pump/om_mixed_rust_binding_test/inherited/inherited = new(spawn_turf)
	TEST_ASSERT(inherited.vg_entity, "Inherited declaration did not auto-bind")
	TEST_ASSERT_EQUAL(inherited.get_target_pressure(), 333, "Inherited declaration config was not installed")
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline + 1, "Inherited declaration created more than one entity")
	qdel(inherited)
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline, "Inherited declaration leaked a Rust entity")

	var/obj/machinery/atmospherics/binary/pump/om_mixed_rust_conflict_test/conflicting = new_unmaterialized(/obj/machinery/atmospherics/binary/pump/om_mixed_rust_conflict_test, spawn_turf)
	TEST_ASSERT(!conflicting.vg_bind_for_materialization(), "Conflicting declaration and legacy gas kinds were accepted")
	TEST_ASSERT_EQUAL(conflicting.vg_entity, 0, "Conflict preflight created a Rust entity")
	TEST_ASSERT(!(conflicting in SSvg.bound), "Conflict preflight registered an incompatible atom")
	qdel(conflicting)
	TEST_ASSERT_EQUAL(vg_entity_count(), baseline, "Conflict preflight leaked a Rust entity")
