// cap_writable() (code/datums/capabilities/library/writable.dm), and how it sits with cap_stamp_target(),
// cap_label() and cap_rename() on one type.

/obj/cap_fixture/writable/capabilities()
	. = ..()
	. += cap_writable(max_length = 12, written_state = "words")

/// The paperwork mix: a pen writes by default, Rename stays in the Menu, a labeller labels.
/obj/cap_fixture/paperwork/capabilities()
	. = ..()
	. += cap_writable()
	. += cap_stamp_target()
	. += cap_label()
	. += cap_rename()

/// Paper declaring cap_writable() keeps its own window.
/obj/item/paper/cap_fixture/capabilities()
	. = ..()
	. += cap_writable()

/datum/unit_test/dx_cap_writable

/datum/unit_test/dx_cap_writable/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/writable/F = allocate(/obj/cap_fixture/writable, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/item/pen/crayon/crayon = allocate(/obj/item/pen/crayon, T)
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)

	var/datum/interaction/capability/write = dx_cap_entry(F, "Write")
	TEST_ASSERT_NOTNULL(write, "the Write entry")
	TEST_ASSERT(write.is_meant(H, F, pen), "a pen selects Write")
	TEST_ASSERT(write.is_meant(H, F, crayon), "so does a crayon")
	TEST_ASSERT(!write.is_meant(H, F, paper), "paper doesn't")
	TEST_ASSERT_NULL(write.why_not(H, F, pen), "there is room to write")
	TEST_ASSERT_NULL(cap_writable_text(F), "nothing written yet")
	TEST_ASSERT(!length(F.caps_examine(H)), "no examine line yet")
	refresh_flush()
	TEST_ASSERT(!dx_look_shows(F, "words"), "no writing overlay yet")

	var/html = cap_writable_add(F, "\[b\]Hi\[/b\]", pen, H)
	TEST_ASSERT_NOTNULL(html, "the pencode was written")
	TEST_ASSERT(findtext(cap_writable_text(F), "<B>Hi</B>"), "pencode is rendered by the paper parser")
	TEST_ASSERT(findtext(cap_writable_text(F), "color=black"), "in the pen's colour")
	TEST_ASSERT_EQUAL(cap_writable_space(F), 10, "two visible characters used")
	TEST_ASSERT_EQUAL(F.caps_examine(H)[1], "It reads: [cap_writable_text(F)]", "examine reads it up close")
	refresh_flush()
	TEST_ASSERT(dx_look_shows(F, "words"), "draw shows the writing overlay")

	cap_writable_add(F, "abcdefghijklmnop", crayon, H)
	TEST_ASSERT(findtext(cap_writable_text(F), "Comic Sans MS"), "a crayon writes in crayon")
	TEST_ASSERT(findtext(cap_writable_text(F), "abcdefghij"), "cut to the space left")
	TEST_ASSERT(!findtext(cap_writable_text(F), "abcdefghijk"), "and no further")
	TEST_ASSERT_EQUAL(cap_writable_space(F), 0, "full")
	TEST_ASSERT_EQUAL(write.why_not(H, F, pen), "there's no room left to write on it", "a full holder refuses the pen")
	TEST_ASSERT_NULL(cap_writable_add(F, "more", pen, H), "nothing more fits")

	cap_writable_clear(F)
	TEST_ASSERT_NULL(cap_writable_text(F), "cleared")
	TEST_ASSERT_EQUAL(cap_writable_space(F), 12, "all the space is back")

	// Paper keeps its own write window.
	var/obj/item/paper/cap_fixture/P = allocate(/obj/item/paper/cap_fixture, T)
	var/datum/interaction/capability/paper_write = dx_cap_entry(P, "Write")
	TEST_ASSERT_NOTNULL(paper_write, "paper offers Write")
	P.tgui_view = "read"
	paper_write.perform(H, P, pen)
	TEST_ASSERT_EQUAL(P.tgui_view, "write", "the pen opened the paper window in its write view")
	TEST_ASSERT_NULL(cap_writable_text(P), "the paper's own info holds its text, not the capability")

/// writable + stamp_target + label + rename on one type.
/datum/unit_test/dx_cap_writable_paperwork

/datum/unit_test/dx_cap_writable_paperwork/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/paperwork/F = allocate(/obj/cap_fixture/paperwork, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/item/stamp/stamp = allocate(/obj/item/stamp, T)
	var/obj/item/hand_labeler/labeller = allocate(/obj/item/hand_labeler, T)

	var/datum/interaction/capability/write = dx_cap_entry(F, "Write")
	var/datum/interaction/capability/rename_entry = dx_cap_entry(F, "Rename")
	TEST_ASSERT(write.is_meant(H, F, pen) && rename_entry.is_meant(H, F, pen), "a pen selects both")
	var/datum/interaction_resolution/resolution = interactions_for(H, F, pen, action = INPUT_ACTION_USE)
	TEST_ASSERT(rename_entry in resolution.available, "Rename is available in the Menu")
	var/list/best = resolution.best_of(resolution.available, INPUT_ACTION_USE, null)
	TEST_ASSERT_EQUAL(length(best), 1, "a pen click has one answer, not a Menu")
	TEST_ASSERT_EQUAL(best[1], write, "and it is Write")

	labeller.mode = TRUE
	labeller.label = "Form 12"
	dx_cap_entry(F, "Label").perform(H, F, labeller)
	TEST_ASSERT_EQUAL(F.name, "fixture (Form 12)", "the labeller labels")
	cap_writable_add(F, "Approved", pen, H)
	dx_cap_entry(F, "Stamp").perform(H, F, stamp)
	TEST_ASSERT_EQUAL(F.name, "fixture (Form 12)", "writing and stamping leave the name alone")

	var/list/lines = F.caps_examine(H)
	TEST_ASSERT_EQUAL(length(lines), 3, "writing, stamp and label each say one line")
	TEST_ASSERT(findtext(lines[1], "It reads:"), "writing first (declaration order)")
	TEST_ASSERT(findtext(lines[2], "This document has been stamped with the rubber stamp."), "then the stamp")
	TEST_ASSERT_EQUAL(lines[3], "It has a label reading \"Form 12\".", "then the label")

	cap_label_set(F, null)
	TEST_ASSERT_EQUAL(F.name, "fixture", "the label comes off")
	TEST_ASSERT(findtext(cap_writable_text(F), "Approved"), "the writing stays")
	TEST_ASSERT_EQUAL(length(cap_stamps_of(F)), 1, "so does the stamp")
