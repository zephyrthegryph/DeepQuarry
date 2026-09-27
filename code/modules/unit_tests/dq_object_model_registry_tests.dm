/datum/object_model/registry/test_members
	accepts = /datum/object_model/registry_test_entity

/datum/object_model/registry_test_entity

/datum/object_model/registry_test_entity/child

/datum/object_model/declaration/registry_test_entity
	target_type = /datum/object_model/registry_test_entity

/datum/object_model/declaration/registry_test_entity/build(datum/object_model/archetype/A)
	A.registry(/datum/object_model/registry/test_members)

/datum/unit_test/dq_object_model_registry_lifecycle
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_registry_lifecycle/Run()
	var/datum/object_model/registry/test_members/service = om_registry(/datum/object_model/registry/test_members)
	TEST_ASSERT_NOTNULL(service, "Declared registry service was not created")
	TEST_ASSERT_EQUAL(om_registry(/datum/object_model/registry/test_members), service, "Registry service is not a singleton")
	var/datum/object_model/registry_test_entity/first = new
	var/datum/object_model/registry_test_entity/child/second = new
	TEST_ASSERT(!length(om_registry_members(/datum/object_model/registry/test_members)), "Registry populated before activation")
	TEST_ASSERT_NOTNULL(om_behaviour_start(first), "Declared registry did not activate")
	TEST_ASSERT_NOTNULL(om_behaviour_start(second), "Inherited registry did not activate")
	TEST_ASSERT_EQUAL(length(om_registry_members(/datum/object_model/registry/test_members)), 2, "Registry did not contain both live members")
	TEST_ASSERT(om_registry_has(/datum/object_model/registry/test_members, first), "Registry omitted first member")
	TEST_ASSERT(om_registry_has(/datum/object_model/registry/test_members, second), "Registry omitted inherited subtype member")
	TEST_ASSERT_EQUAL(length(om_registry_members(/datum/object_model/registry/test_members, /datum/object_model/registry_test_entity/child)), 1, "Registry subtype filter is wrong")
	var/list/snapshot = om_registry_members(/datum/object_model/registry/test_members)
	snapshot.Cut()
	TEST_ASSERT_EQUAL(length(om_registry_members(/datum/object_model/registry/test_members)), 2, "Mutating a snapshot changed registry membership")
	TEST_ASSERT_NOTNULL(om_behaviour_start(first), "Repeated activation lost runtime")
	TEST_ASSERT_EQUAL(length(om_registry_members(/datum/object_model/registry/test_members)), 2, "Repeated activation duplicated registry membership")
	om_behaviour_release(first)
	TEST_ASSERT(!om_registry_has(/datum/object_model/registry/test_members, first), "Runtime release left registry membership")
	TEST_ASSERT(om_registry_has(/datum/object_model/registry/test_members, second), "Runtime release removed another member")
	TEST_ASSERT_NOTNULL(om_behaviour_start(first), "Restarting released runtime failed")
	TEST_ASSERT(om_registry_has(/datum/object_model/registry/test_members, first), "Restart did not restore registry membership")
	qdel(second)
	TEST_ASSERT(!om_registry_has(/datum/object_model/registry/test_members, second), "Deleted member remains registered")
	TEST_ASSERT(!(second in service.members), "Deleted member remains in registry storage")
	TEST_ASSERT_EQUAL(length(om_registry_members(/datum/object_model/registry/test_members)), 1, "Deleted member was returned in registry snapshot")
	qdel(first)
	TEST_ASSERT(!length(om_registry_members(/datum/object_model/registry/test_members)), "Registry retained deleted members")
	TEST_ASSERT(!length(service.members), "Registry storage retained deleted members")
	qdel(service)
	TEST_ASSERT(om_registry(/datum/object_model/registry/test_members) != service, "deleted registry service should be recreated")
	var/datum/object_model/archetype/invalid = new
	invalid.entity_type = /datum
	invalid.registry(/datum/object_model/registry/test_members)
	TEST_ASSERT(!invalid.validate(), "Registry accepted an incompatible declaration type")
