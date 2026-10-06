/// A belly setting comes as "set_attribute" with the attribute's name: refused without a selected belly, and otherwise routed to that
/// attribute's sub-action, whose value goes through its schema.
/datum/unit_test/interim_vore_panel_attributes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/vore_look/panel = new(H)
	rel_clear(H, nameof(H.vore_selected))
	for(var/obj/belly/old as anything in H.vore_organs)
		old.name = "old belly"
	op_ui_act(H, panel, "set_attribute", list("attribute" = "b_name", "val" = "Gullet"))
	for(var/obj/belly/old as anything in H.vore_organs)
		TEST_ASSERT_NOTEQUAL(old.name, "Gullet", "no belly is renamed while none is selected")
	var/obj/belly/B = allocate(/obj/belly, H)
	rel_set(H, nameof(H.vore_selected), B)
	op_ui_act(H, panel, "set_attribute", list("attribute" = "b_name", "val" = "Gullet"))
	TEST_ASSERT_EQUAL(B.name, "Gullet", "the selected belly takes the new name")
	op_ui_act(H, panel, "set_attribute", list("attribute" = "no_such_attribute", "val" = "x"))
	TEST_ASSERT_EQUAL(B.name, "Gullet", "an unknown attribute changes nothing")
	qdel(panel)
