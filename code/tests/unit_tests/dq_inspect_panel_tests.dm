// The Inspect panel (code/content/examine/inspect_panel.dm): what examining yields as panel data, and that the chat
// preference decides where examine text goes. Written against data and routing, not a connected client's window.

/datum/unit_test/dq_inspect_panel
	abstract_type = /datum/unit_test/dq_inspect_panel

/datum/unit_test/dq_inspect_panel/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_inspect_panel/proc/run_gate()
	return

/datum/unit_test/dq_inspect_panel/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// A human's panel data lists the worn item under its slot, with a handle that resolves back to the item.
/datum/unit_test/dq_inspect_panel/human_worn_items

/datum/unit_test/dq_inspect_panel/human_worn_items/run_gate()
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, tile(1, 1))
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human, tile(2, 1))
	var/obj/item/clothing/under/uniform = allocate(/obj/item/clothing/under/color/grey)
	TEST_ASSERT(subject.equip_to_slot_if_possible(uniform, SLOT_ID_UNIFORM, quiet = TRUE), "the subject can wear a uniform")
	var/list/data = inspect_panel_data(viewer, subject, list("a line"), list())
	TEST_ASSERT_EQUAL(data["target"], capitalize(subject.name), "the panel is headed by the target's name")
	TEST_ASSERT(istext(data["kind"]) && length(data["kind"]), "a human has a kind for the subtitle")
	TEST_ASSERT(istext(data["distance"]) && length(data["distance"]), "and a distance")
	var/found = FALSE
	for(var/list/row as anything in data["worn"])
		if(row["slot"] == "uniform")
			found = TRUE
			TEST_ASSERT_EQUAL(row["name"], uniform.name, "the row names the item")
			TEST_ASSERT_EQUAL(handle_get(row["ref"]), uniform, "the row's handle resolves to the item")
	TEST_ASSERT(found, "the worn uniform is listed")
	TEST_ASSERT_EQUAL(length(data["description"]), 1, "the description lines it was given are kept")
	TEST_ASSERT(islist(data["body"]), "a human has a body section")

/// A limb that is gone shows as a MISSING chip.
/datum/unit_test/dq_inspect_panel/human_missing_limb

/datum/unit_test/dq_inspect_panel/human_missing_limb/run_gate()
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, tile(1, 1))
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human, tile(2, 1))
	var/obj/item/organ/external/arm = subject.get_organ(BP_L_ARM)
	arm.droplimb(FALSE, DROPLIMB_EDGE)
	qdel(arm)
	var/list/data = inspect_panel_data(viewer, subject, list(), list())
	var/missing = FALSE
	for(var/list/chip as anything in data["body"])
		if(chip["state"] == "MISSING")
			missing = TRUE
			TEST_ASSERT_EQUAL(chip["tone"], "danger", "a missing limb is a danger chip")
	TEST_ASSERT(missing, "the lost arm shows as a missing chip")

/// An item or a door has no worn or body sections but still yields a name, a kind and its description.
/datum/unit_test/dq_inspect_panel/object_falls_back_to_text

/datum/unit_test/dq_inspect_panel/object_falls_back_to_text/run_gate()
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, tile(1, 1))
	var/obj/item/thing = allocate(/obj/item/pen, tile(2, 1))
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, tile(1, 2))
	for(var/atom/subject in list(thing, door))
		var/list/lines = subject.inspect_describe(viewer)
		TEST_ASSERT(length(lines), "[subject.type] describes itself with examine's lines")
		var/list/data = inspect_panel_data(viewer, subject, lines, list())
		TEST_ASSERT_EQUAL(data["target"], capitalize(subject.name), "[subject.type] is headed by its name")
		TEST_ASSERT_EQUAL(length(data["worn"]), 0, "[subject.type] has no worn items")
		TEST_ASSERT_EQUAL(length(data["body"]), 0, "[subject.type] has no body chips")
		TEST_ASSERT_EQUAL(length(data["description"]), length(lines), "[subject.type] keeps its description")

/// Icons and links are dropped from panel text; a line that held a link is handed back for chat.
/datum/unit_test/dq_inspect_panel/lines_are_made_panel_safe

/datum/unit_test/dq_inspect_panel/lines_are_made_panel_safe/run_gate()
	var/list/split = inspect_split_lines(list("plain", "<img class='icon' src='x'> pic", "see <a href='byond://?src=x;y=1'>this</a>"))
	var/list/panel_lines = split[1]
	var/list/chat_lines = split[2]
	TEST_ASSERT_EQUAL(length(panel_lines), 3, "every line reaches the panel")
	for(var/line in panel_lines)
		TEST_ASSERT(!findtext(line, "<img") && !findtext(line, "<a "), "no picture or link is left in '[line]'")
	TEST_ASSERT_EQUAL(length(chat_lines), 1, "only the line with a link is kept for chat")
	TEST_ASSERT(findtext(chat_lines[1], "byond://"), "and it keeps its link")

/// The chat preference is off by default (the panel is the default); a mob without a client never uses the panel, so its
/// examine text stays in chat.
/datum/unit_test/dq_inspect_panel/chat_preference_and_routing

/datum/unit_test/dq_inspect_panel/chat_preference_and_routing/run_gate()
	var/datum/preference/toggle/examine_in_chat/pref = GLOB.preference_entries[/datum/preference/toggle/examine_in_chat]
	TEST_ASSERT(pref, "the examine-in-chat preference exists")
	TEST_ASSERT(!pref.create_default_value(), "examining opens the panel unless the player asks for chat")
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, tile(1, 1))
	TEST_ASSERT(!viewer.examine_to_panel(), "a mob with no client keeps its examine text in chat")
