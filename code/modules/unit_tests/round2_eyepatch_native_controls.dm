/// Real inventory menu choices switch all three original eyepatch appearances and back.
/datum/unit_test/round2_eyepatch_native_controls
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_eyepatch_native_controls/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/completed = 0
	for(var/patch_type in list(/obj/item/clothing/glasses/hud/security/eyepatch, /obj/item/clothing/glasses/hud/security/eyepatch2, /obj/item/clothing/glasses/hud/health/eyepatch))
		var/obj/item/clothing/glasses/hud/patch = allocate(patch_type, T)
		TEST_ASSERT(user.put_in_active_hand(patch), "actual actor carries the original eyepatch")
		var/original_icon = patch.icon_state
		test_menu(user, patch, "switch_eye")
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(patch.icon_state, "[original_icon]_1", "actual native menu choice switches original eyepatch appearance")
		test_menu(user, patch, "switch_eye")
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(patch.icon_state, original_icon, "actual second menu choice restores original appearance")
		TEST_ASSERT_EQUAL(user.get_active_hand(), patch, "both real menu choices preserve original source hand")
		TEST_ASSERT(user.unEquip(patch), "actor releases the tested original patch")
		completed++
	TEST_ASSERT_EQUAL(completed, 3, "all three actual eyepatch constructors switched twice")
