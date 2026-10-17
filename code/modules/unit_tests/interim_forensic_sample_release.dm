/// Refused donor release preserves both physical samples and their exact evidence.
/datum/unit_test/interim_forensic_sample_release/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/sample/fibers/recipient = allocate(/obj/item/sample/fibers, T)
	var/obj/item/sample/fibers/donor = allocate(/obj/item/sample/fibers, T)
	recipient.set_evidence(list("recipient fiber"))
	donor.set_evidence(list("donor fiber"))
	var/recipient_name = recipient.name
	var/donor_name = donor.name
	TEST_ASSERT(user.put_in_active_hand(donor), "the original donor is genuinely held")
	add_trait(donor, TRAIT_NODROP, "interim_forensic_sample_release")
	test_click(user, recipient, donor)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(donor), "refused release must not destroy the original donor")
	TEST_ASSERT_EQUAL(user.get_active_hand(), donor, "refusal preserves the exact held donor")
	TEST_ASSERT_EQUAL(donor.loc, user, "refusal preserves donor custody")
	TEST_ASSERT_EQUAL(recipient.loc, T, "refusal preserves the original recipient")
	TEST_ASSERT_EQUAL(recipient.name, recipient_name, "refusal preserves recipient labeling")
	TEST_ASSERT_EQUAL(donor.name, donor_name, "refusal preserves donor labeling")
	TEST_ASSERT_EQUAL(length(recipient.evidence), 1, "refusal cannot copy donor evidence")
	TEST_ASSERT_EQUAL(recipient.evidence[1], "recipient fiber", "original recipient evidence remains exact")
	TEST_ASSERT_EQUAL(length(donor.evidence), 1, "refusal retains the original donor evidence")
	TEST_ASSERT_EQUAL(donor.evidence[1], "donor fiber", "donor evidence remains exact")
	remove_trait(donor, TRAIT_NODROP, "interim_forensic_sample_release")
	test_click(user, recipient, donor)
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(donor), "successful release and merge consume the actual donor")
	TEST_ASSERT_NULL(user.get_active_hand(), "successful consumption clears the actual hand")
	TEST_ASSERT_EQUAL(recipient.loc, T, "successful merge retains the exact recipient")
	TEST_ASSERT_EQUAL(length(recipient.evidence), 2, "successful merge contains exactly both distinct records")
	TEST_ASSERT("recipient fiber" in recipient.evidence, "successful merge retains original evidence")
	TEST_ASSERT("donor fiber" in recipient.evidence, "successful merge transfers original donor evidence")
	TEST_ASSERT_EQUAL(recipient.name, "fiber bag (combined)", "successful merge retains the original combined label")

/// Washed-away blood glows on an item only while a UV light scans it (fluorescent 2): the look gains one overlay then, and none while it is unlit.
/datum/unit_test/dq_uv_light_shows_washed_blood

/datum/unit_test/dq_uv_light_shows_washed_blood/Run()
	var/obj/item/pen/item = allocate(/obj/item/pen, test_floor())
	dq_set_was_bloodied(item, TRUE)
	dq_set_fluorescent(item, 1)
	var/datum/look/unlit = new
	item.draw(unlit)
	var/unlit_count = length(unlit.overlays)
	dq_set_fluorescent(item, 2)
	var/datum/look/lit = new
	item.draw(lit)
	TEST_ASSERT_EQUAL(length(lit.overlays), unlit_count + 1, "a UV-lit item that was bloodied draws the blood glow")
	dq_set_fluorescent(item, 1)
	var/datum/look/after = new
	item.draw(after)
	TEST_ASSERT_EQUAL(length(after.overlays), unlit_count, "the glow goes with the light")
