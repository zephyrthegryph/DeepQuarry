// The zone-select doll's hit areas are one table (GLOB.zone_sel_regions) read by the HUD click and sent to the Looks tab.

/datum/unit_test/dq_zone_sel_regions_pick_the_hud_zones/Run()
	TEST_ASSERT_EQUAL(zone_sel_zone_at(16, 18), BP_TORSO, "chest")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(16, 12), BP_GROIN, "groin")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(9, 12), BP_R_HAND, "right hand")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(22, 16), BP_L_ARM, "left arm")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(12, 6), BP_R_LEG, "right leg")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(18, 2), BP_L_FOOT, "left foot")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(13, 28), BP_HEAD, "head")

/datum/unit_test/dq_zone_sel_regions_eyes_and_mouth_sit_on_the_head/Run()
	TEST_ASSERT_EQUAL(zone_sel_zone_at(16, 23), O_MOUTH, "mouth")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(14, 26), O_EYES, "eyeline")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(16, 27), O_EYES, "eyes")
	TEST_ASSERT_EQUAL(zone_sel_zone_at(14, 25), BP_HEAD, "beside the eyes is still head")

/datum/unit_test/dq_zone_sel_regions_miss_outside_the_doll/Run()
	TEST_ASSERT_NULL(zone_sel_zone_at(1, 1), "empty corner")
	TEST_ASSERT_NULL(zone_sel_zone_at(16, 31), "above the head")
	TEST_ASSERT_NULL(zone_sel_zone_at(16, 3), "between the feet")

/datum/unit_test/dq_zone_sel_regions_have_art/Run()
	var/list/states = icon_states('icons/mob/zone_sel.dmi')
	for(var/list/region as anything in GLOB.zone_sel_regions)
		TEST_ASSERT(region[1] in states, "zone_sel.dmi has no overlay for [region[1]]")
	TEST_ASSERT(("zone_sel" in icon_states('icons/mob/screen/midnight.dmi')), "the doll base art")
