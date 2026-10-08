// cap_stamp_target() (code/datums/capabilities/library/stamp_target.dm).

/obj/cap_fixture/stampable/capabilities()
	. = ..()
	. += cap_stamp_target(max_stamps = 2, noun = "form")

/datum/unit_test/dx_cap_stamp_target

/datum/unit_test/dx_cap_stamp_target/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/stampable/F = allocate(/obj/cap_fixture/stampable, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/stamp/stamp = allocate(/obj/item/stamp, T)
	var/obj/item/stamp/clown/clown_stamp = allocate(/obj/item/stamp/clown, T)
	var/obj/item/clothing/accessory/ring/seal/seal = allocate(/obj/item/clothing/accessory/ring/seal, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)

	var/datum/interaction/capability/stamp_entry = dx_cap_entry(F, "Stamp")
	TEST_ASSERT_NOTNULL(stamp_entry, "the Stamp entry")
	TEST_ASSERT(stamp_entry.is_meant(H, F, stamp), "a stamp selects it")
	TEST_ASSERT(stamp_entry.is_meant(H, F, seal), "so does a seal ring")
	TEST_ASSERT(!stamp_entry.is_meant(H, F, pen), "a pen doesn't")
	TEST_ASSERT(!length(caps_examine(F, H)), "no stamps, no examine line")

	stamp_entry.perform(H, F, clown_stamp)
	TEST_ASSERT_EQUAL(length(cap_stamps_of(F)), 0, "the clown's stamp refuses a non-clown")

	stamp_entry.perform(H, F, stamp)
	TEST_ASSERT_EQUAL(length(cap_stamps_of(F)), 1, "stamped")
	TEST_ASSERT_EQUAL(cap_stamps_of(F)[1], "This form has been stamped with the rubber stamp.", "the stamp line names the stamp")
	TEST_ASSERT_EQUAL(caps_examine(F, H)[1], span_italics("This form has been stamped with the rubber stamp."), "examine shows it")
	refresh_flush()
	TEST_ASSERT("paper_[stamp.icon_state]" in F.rx?.look_overlays, "draw shows the stamp mark")

	seal.stamptext = "Sealed by the Secretary."
	stamp_entry.perform(H, F, seal)
	TEST_ASSERT_EQUAL(cap_stamps_of(F)[2], "Sealed by the Secretary.", "a seal leaves its own text")
	TEST_ASSERT_EQUAL(stamp_entry.why_not(H, F, stamp), "there's no room left for another stamp", "max_stamps refuses a third")
	TEST_ASSERT(!cap_stamp_add(F, stamp), "and the direct add refuses too")

	var/list/data = dx_cap_ui_data(F, H, /datum/capability/stamp_target)
	TEST_ASSERT_EQUAL(length(data["stamps"]), 2, "ui_data lists the stamps")
	TEST_ASSERT_EQUAL(stamp_mark_text(stamp, "paper"), "This paper has been stamped with the rubber stamp.", "the helper paper uses")
	TEST_ASSERT(stamp_usable_by(stamp, H), "an ordinary stamp works for anyone")
	TEST_ASSERT(!stamp_usable_by(clown_stamp, H), "the clown's stamp doesn't")
