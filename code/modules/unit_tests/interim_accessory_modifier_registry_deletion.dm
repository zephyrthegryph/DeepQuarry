/// Registry deletion must revert real applied stat deltas before deleting its owned modifiers.
/datum/unit_test/interim_accessory_modifier_registry_deletion/Run()
	var/turf/T = test_floor()
	var/datum/accessory_slot_registry/registry = allocate(/datum/accessory_slot_registry)
	var/obj/item/clothing/clothing = allocate(/obj/item/clothing, T)
	var/obj/item/clothing/accessory/accessory = allocate(/obj/item/clothing/accessory, T)
	var/datum/accessory_stat_modifier/modifier = allocate(/datum/accessory_stat_modifier)
	var/original_force = clothing.force
	var/original_slowdown = clothing.slowdown
	modifier.force_delta = 3
	modifier.slowdown_delta = 2
	registry.register_modifier(accessory, clothing, modifier)
	TEST_ASSERT_EQUAL(modifier.target(), clothing, "The actual registered modifier must refer to its real clothing target")
	TEST_ASSERT(modifier in registry.active_modifiers, "The actual registry must own the registered modifier")
	TEST_ASSERT_EQUAL(clothing.force, original_force + 3, "Actual registration must apply the configured force delta")
	TEST_ASSERT_EQUAL(clothing.slowdown, original_slowdown + 2, "Actual registration must apply the configured slowdown delta")
	qdel(registry)
	TEST_ASSERT(QDELETED(registry), "The actual isolated registry must be deleted")
	TEST_ASSERT(QDELETED(modifier), "The registry must delete its actual owned modifier")
	TEST_ASSERT(!QDELETED(clothing), "The independent clothing target must survive registry deletion")
	TEST_ASSERT_EQUAL(clothing.force, original_force, "Deletion must revert actual force before its owned modifiers clear")
	TEST_ASSERT_EQUAL(clothing.slowdown, original_slowdown, "Deletion must revert actual slowdown before its owned modifiers clear")
	TEST_ASSERT(!QDELETED(accessory), "The independent accessory must survive registry deletion")
