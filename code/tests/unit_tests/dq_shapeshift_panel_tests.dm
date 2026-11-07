// The shapeshift panel (code/content/mob/living/carbon/human/species/shapeshift_panel.dm): the appearance commands of a shapeshifter in one window.

/// The ids of the rows a shapeshift panel lists now, by group.
/datum/unit_test/proc/dq_shift_row_ids(datum/shapeshift_panel/panel)
	var/list/ids = list()
	for(var/list/group as anything in panel.ui_data(null)["groups"])
		for(var/list/row as anything in group["rows"])
			ids[row["id"]] = group["title"]
	return ids

/// The panel lists the commands the mob was granted under their groups, shows a preview, runs them for the mob alone, and the Abilities panel lists its Shapeshift command.
/datum/unit_test/dq_shapeshift_panel_lists_granted_commands

/datum/unit_test/dq_shapeshift_panel_lists_granted_commands/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	var/datum/shapeshift_panel/panel = new(H)
	var/datum/command_panel/abilities = new(H, "abilities", "Abilities", GLOB.ability_panel_commands)
	TEST_ASSERT(!length(dq_shift_row_ids(panel)), "a mob with no shapeshift command granted has an empty window")
	TEST_ASSERT(!dq_panel_ids(abilities)["shapeshift_panel"], "and no Shapeshift command in its abilities")
	grant(H, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_hair), H)
	grant(H, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_gender), H)
	var/list/ids = dq_shift_row_ids(panel)
	TEST_ASSERT_EQUAL(ids[SHIFT_HAIR], "Hair", "a granted command is listed under its group")
	TEST_ASSERT_EQUAL(ids[SHIFT_GENDER], "Body", "each under its own")
	TEST_ASSERT(!ids[SHIFT_TAIL] && !ids[SHIFT_FORM], "and one that was not granted is not")
	TEST_ASSERT(istext(panel.ui_data(null)["preview"]), "the window shows a preview of the mob")
	TEST_ASSERT_EQUAL(dq_panel_ids(abilities)["shapeshift_panel"], "Shapeshift", "the Abilities panel lists the Shapeshift command")
	TEST_ASSERT(!panel.run_action(other, SHIFT_GENDER), "another mob cannot press the buttons")
	TEST_ASSERT(!panel.run_action(H, SHIFT_TAIL), "a command that was not granted is refused")
	TEST_ASSERT(!panel.run_action(H, "no_such_command"), "an unknown command is refused")
	TEST_ASSERT(panel.run_action(H, SHIFT_GENDER), "the granted command runs")
	TEST_ASSERT(istype(SSrequests.open_for(H), /datum/prompt/choice), "and asks what to pick")
	request_answer(H, null, REQ_CANCELLED)
	revoke(H, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_hair), H)
	revoke(H, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_gender), H)
	TEST_ASSERT(!length(dq_shift_row_ids(panel)), "the rows go with the grants")
	qdel(abilities)
	qdel(panel)
