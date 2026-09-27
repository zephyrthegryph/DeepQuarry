/datum/object_model/test_persistent_entity
	var/value = 0
	var/list/labels

/datum/object_model/declaration/test_persistent_entity
	target_type = /datum/object_model/test_persistent_entity

/datum/object_model/declaration/test_persistent_entity/build(datum/object_model/archetype/A)
	A.slot("parts", /datum/object_model/test_persistent_entity, 3, OM_SLOT_DELETE)

/datum/unit_test/om_persistence_round_trip
	needs_test_block = FALSE

/datum/unit_test/om_persistence_round_trip/Run()
	var/datum/object_model/test_persistent_entity/root = new
	root.value = 17
	root.labels = list("blue", "green")
	var/datum/object_model/test_persistent_entity/child = new
	child.value = 42
	TEST_ASSERT(om_claim(root, "parts", child), "declared child is owned")
	var/list/errors = list()
	var/list/blob = om_persist_serialize(root, errors)
	TEST_ASSERT(blob && !length(errors), "declared tree serializes")
	var/list/decoded = json_decode(json_encode(blob))
	var/datum/object_model/test_persistent_entity/copy = om_persist_materialize(decoded, errors)
	TEST_ASSERT(copy && !length(errors), "JSON round trip restores tree")
	TEST_ASSERT_EQUAL(copy.value, 17, "saved scalar restored")
	TEST_ASSERT_EQUAL(copy.labels[2], "green", "saved list restored")
	var/list/parts = om_children(copy, "parts")
	TEST_ASSERT_EQUAL(length(parts), 1, "owned slot restored")
	var/datum/object_model/test_persistent_entity/copy_child = parts[1]
	TEST_ASSERT_EQUAL(copy_child.value, 42, "child state restored")
	TEST_ASSERT_EQUAL(om_owner(copy_child), copy, "child ownership restored")
	qdel(root)
	qdel(copy)

/datum/unit_test/om_persistence_refusals
	needs_test_block = FALSE

/datum/unit_test/om_persistence_refusals/Run()
	var/datum/object_model/test_persistent_entity/root = new
	var/datum/object_model/test_persistent_entity/child = new
	var/list/errors = list()
	TEST_ASSERT(om_claim(root, "om:internal", child), "reserved runtime slot can exist")
	TEST_ASSERT_NULL(om_persist_serialize(root, errors), "undeclared runtime slot refuses snapshot")
	TEST_ASSERT(length(errors), "refusal gives a reason")
	om_release(child)
	errors.Cut()
	var/list/blob = om_persist_serialize(root, errors)
	blob["version"] = 999
	TEST_ASSERT_NULL(om_persist_materialize(blob, errors), "unknown snapshot version refuses restore")
	TEST_ASSERT(length(errors), "version refusal gives a reason")
	qdel(root)
	qdel(child)
