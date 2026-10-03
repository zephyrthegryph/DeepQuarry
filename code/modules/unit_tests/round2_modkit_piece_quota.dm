/// A real species refit kit supplies one helmet refit and one suit refit, in either order.
/datum/unit_test/round2_modkit_piece_quota
	parent_type = /datum/unit_test/dq_p2_engine
	var/first_type = /obj/item/clothing/head/helmet/space/void
	var/complement_type = /obj/item/clothing/suit/space/void
	var/remaining_parts = 2

/datum/unit_test/round2_modkit_piece_quota/suit_first
	first_type = /obj/item/clothing/suit/space/void
	complement_type = /obj/item/clothing/head/helmet/space/void
	remaining_parts = 1

/datum/unit_test/round2_modkit_piece_quota/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/modkit/tajaran/kit = allocate(/obj/item/modkit/tajaran, T)
	var/obj/item/clothing/first = allocate(first_type, T)
	var/obj/item/clothing/repeated = allocate(first_type, T)
	var/obj/item/clothing/complement = allocate(complement_type, T)
	TEST_ASSERT_EQUAL(first.type, first_type, "first target is the actual requested void clothing type")
	TEST_ASSERT_EQUAL(complement.type, complement_type, "complement target is the actual other void clothing type")
	TEST_ASSERT_EQUAL(kit.parts, 3, "actual kit initially carries both component quotas")
	TEST_ASSERT_EQUAL(kit.target_species, SPECIES_TAJARAN, "actual kit is a Tajaran refit kit")
	TEST_ASSERT(!(SPECIES_TAJARAN in dq_fit_bodytypes(first)), "first actual target initially excludes the kit's bodytype")
	TEST_ASSERT(!(SPECIES_TAJARAN in dq_fit_bodytypes(repeated)), "second same-kind target initially excludes the kit's bodytype")
	TEST_ASSERT(!(SPECIES_TAJARAN in dq_fit_bodytypes(complement)), "complement actual target initially excludes the kit's bodytype")
	var/list/original_fit = dq_fit_bodytypes(repeated)
	var/list/repeated_fit = original_fit.Copy()
	TEST_ASSERT(user.put_in_active_hand(kit), "actor holds original actual kit")
	user.set_use_stance(I_HELP)
	TEST_ASSERT(!user.incapacitated(), "actual actor is capable before player clicks")
	TEST_ASSERT(assert_resolves(user, first, kit, GESTURE_CLICK, "refit"), "Actual player input must select kit refitting: [explain_click(user, first, kit)]")
	user.next_click = 0
	var/datum/input_event/click/first_click = new(user, first, null, "mapwindow.map", "left=1")
	input_submit(first_click)
	test_time(1 SECOND)
	TEST_ASSERT(SPECIES_TAJARAN in dq_fit_bodytypes(first), "actual click refits the first original target; result [first_click.result?.key]/[first_click.result?.outcome]: [reason_text(first_click.result?.reason)]")
	TEST_ASSERT_EQUAL(kit.parts, remaining_parts, "first refit spends exactly its own component quota")
	TEST_ASSERT_EQUAL(first.loc, T, "refit preserves original target on its floor")
	TEST_ASSERT_EQUAL(user.get_active_hand(), kit, "complement quota preserves original kit in hand")
	user.next_click = 0
	input_submit(new /datum/input_event/click(user, repeated, null, "mapwindow.map", "left=1"))
	test_time(1 SECOND)
	var/list/after_fit = dq_fit_bodytypes(repeated)
	TEST_ASSERT_EQUAL(length(after_fit), length(repeated_fit), "exhausted component refuses without changing target fit length")
	for(var/bodytype in repeated_fit)
		TEST_ASSERT(bodytype in after_fit, "exhausted component preserves every original target bodytype")
	TEST_ASSERT(!(SPECIES_TAJARAN in after_fit), "exhausted component cannot refit a second same-kind target")
	TEST_ASSERT_EQUAL(kit.parts, remaining_parts, "same-kind refusal retains complementary quota")
	TEST_ASSERT_EQUAL(user.get_active_hand(), kit, "same-kind refusal preserves original kit in hand")
	TEST_ASSERT_EQUAL(repeated.loc, T, "same-kind refusal preserves original target containment")
	TEST_ASSERT(!QDELETED(repeated), "same-kind refusal preserves original target alive")
	user.next_click = 0
	input_submit(new /datum/input_event/click(user, complement, null, "mapwindow.map", "left=1"))
	test_time(1 SECOND)
	TEST_ASSERT(SPECIES_TAJARAN in dq_fit_bodytypes(complement), "remaining component still refits the original complementary piece")
	TEST_ASSERT_EQUAL(complement.loc, T, "complement refit preserves original target on floor")
	TEST_ASSERT(!QDELETED(first) && !QDELETED(complement), "both successful refits preserve original clothing identities")
	TEST_ASSERT(QDELETED(kit), "using both actual components consumes original kit")
	TEST_ASSERT_EQUAL(user.get_active_hand(), null, "consumed original kit clears actual hand")
