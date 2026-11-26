/// Picking a spontaneous-vore belly writes the lazy spont_belly state, and "Current Selected" clears the field through STATE_SET,
/// which drops the state once no field differs from its default.
/datum/unit_test/dq_vore_spont_belly_select/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/vore_look/panel = new(H)
	op_ui_act(H, panel, "set_spont_belly", list("attribute" = "rear", "val" = "Gullet"))
	TEST_ASSERT_EQUAL(STATE_GET(H, spont_belly, spont_belly_rear), "Gullet", "the named belly is stored")
	TEST_ASSERT_NOTNULL(H.spont_belly, "a non-default field makes the lazy state")
	op_ui_act(H, panel, "set_spont_belly", list("attribute" = "rear", "val" = "Current Selected"))
	TEST_ASSERT_NULL(STATE_GET(H, spont_belly, spont_belly_rear), "Current Selected clears the field")
	TEST_ASSERT_NULL(H.spont_belly, "the state goes when its last field returns to the default")
	op_ui_act(H, panel, "set_spont_belly", list("attribute" = "left", "val" = "Current Selected"))
	TEST_ASSERT_NULL(H.spont_belly, "clearing with no state makes none")
	qdel(panel)
