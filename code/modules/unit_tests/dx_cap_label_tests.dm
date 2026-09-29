// label() / rename() (code/datums/capabilities/library/label.dm).

/obj/cap_fixture/labelled/capabilities()
	. = ..()
	. += cap_label(max_length = 8)
	. += cap_rename()

/datum/unit_test/dx_cap_label

/datum/unit_test/dx_cap_label/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/labelled/F = allocate(/obj/cap_fixture/labelled, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/hand_labeler/labeller = allocate(/obj/item/hand_labeler, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)

	var/datum/interaction/capability/apply = dx_cap_entry(F, "Label")
	var/datum/interaction/capability/pen_entry = dx_cap_entry(F, "Rename")
	TEST_ASSERT_NOTNULL(apply, "the Label entry")
	TEST_ASSERT_NOTNULL(pen_entry, "the Rename entry")
	TEST_ASSERT(pen_entry.is_meant(H, F, pen), "a pen selects Rename")
	TEST_ASSERT(!apply.is_meant(H, F, pen), "a pen doesn't select Label")

	var/datum/interaction/capability/remove
	for(var/datum/interaction/capability/E as anything in cap_interactions(F))
		if(E.name == "Remove label")
			remove = E
			break
	TEST_ASSERT_NULL(remove.default_action, "Remove label is Menu only")
	TEST_ASSERT_EQUAL(remove.why_not(H, F, null), "it has no label", "nothing to remove yet")

	labeller.mode = FALSE
	labeller.label = "Sugar"
	apply.perform(H, F, labeller)
	TEST_ASSERT_EQUAL(F.name, "fixture", "an unlit labeller labels nothing")

	labeller.mode = TRUE
	var/left = labeller.labels_left
	TEST_ASSERT(apply.perform(H, F, labeller), "the labeller labels")
	TEST_ASSERT_EQUAL(F.name, "fixture (Sugar)", "the label is in the name")
	TEST_ASSERT_EQUAL(labeller.labels_left, left - 1, "one label used")
	TEST_ASSERT(("It has a label reading \"Sugar\"." in F.caps_examine(H)), "examine reads the label")
	TEST_ASSERT_EQUAL(length(F.caps_examine(H)), 1, "said once although both label capabilities are declared")

	labeller.label = "Sugarcane syrup"
	TEST_ASSERT(apply.perform(H, F, labeller), "relabels")
	TEST_ASSERT_EQUAL(F.name, "fixture (Sugarcan)", "cut to max_length, on the original name")

	cap_label_set(F, "Salt")
	TEST_ASSERT_EQUAL(F.name, "fixture (Salt)", "a rename replaces the label")
	TEST_ASSERT(remove.perform(H, F, null), "Remove label performs")
	TEST_ASSERT_EQUAL(F.name, "fixture", "the name is restored")
	TEST_ASSERT_NULL(cap_label_of(F), "no label left")
	TEST_ASSERT(!length(F.caps_examine(H)), "no examine line")
