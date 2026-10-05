/// Data-effect coverage only: does not exercise requests, UI identity, or permissions.
/datum/unit_test/round2_shock_collar_tag_effect/Run()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	user.enable_godmode()
	var/obj/item/clothing/accessory/collar/shock/collar = allocate(/obj/item/clothing/accessory/collar/shock, surface)
	var/original_name = collar.name
	var/original_description = collar.desc
	TEST_ASSERT(collar.apply_ui_tag(user, "Unit test tag"), "actual accepted tag effect returns the truthy UI-refresh result")
	TEST_ASSERT_EQUAL(collar.name, "[original_name] (Unit test tag)", "actual collar name includes the accepted server text")
	TEST_ASSERT_EQUAL(collar.desc, original_description + " The tag says \"Unit test tag\".", "actual collar description includes the accepted server text")
	TEST_ASSERT(collar.apply_ui_tag(user, ""), "actual accepted blank effect returns the truthy UI-refresh result")
	TEST_ASSERT_EQUAL(collar.name, original_name, "accepted blank resets the actual collar name")
	TEST_ASSERT_EQUAL(collar.desc, original_description, "accepted blank resets the actual collar description")
