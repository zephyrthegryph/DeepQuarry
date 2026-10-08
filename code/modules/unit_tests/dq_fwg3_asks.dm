// fw-gaps3 content pins for the questions that re-asked themselves (rerun_ask), on the types the asks() codemod left because the question did not
// stand first: written on the legacy handlers first (their re-run answered through p2cl_answer()), kept through the conversion to ops with asks() steps.

/datum/unit_test/dq_fwg3_ask
	abstract_type = /datum/unit_test/dq_fwg3_ask

/datum/unit_test/dq_fwg3_ask/Run()
	set_global(nameof(GLOB.test_prompts), list())
	test_driver_begin()
	p2cl_capture_prompts()
	run_fwg3()
	test_driver_end()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		for(var/obj/item/I in T.contents.Copy())
			qdel(I)

/datum/unit_test/dq_fwg3_ask/proc/run_fwg3()
	return

/datum/unit_test/dq_fwg3_ask/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/datum/unit_test/dq_fwg3_ask/proc/answer(mob/user, value)
	p2cl_answer(user, value)
	test_time(1)

/// Bookcase: a book is shelved; a pen names the shelf (a question); the hand asks which book to take.
/datum/unit_test/dq_fwg3_ask/bookcase
/datum/unit_test/dq_fwg3_ask/bookcase/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/structure/bookcase/C = allocate(/obj/structure/bookcase, T)
	var/obj/item/book/B = allocate(/obj/item/book, T)
	H.put_in_active_hand(B)
	test_click(H, C, B)
	TEST_ASSERT_EQUAL(B.loc, C, "the book is shelved")
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	H.put_in_active_hand(P)
	test_click(H, C, P)
	answer(H, "Fiction")
	TEST_ASSERT_EQUAL(C.name, "bookcase (Fiction)", "the pen names the shelf")
	H.drop_item()
	test_click(H, C, null)
	answer(H, B)
	TEST_ASSERT_EQUAL(B.loc, H, "the picked book is taken into the hand")

/// Ladder assembly: a pen names the ladder.
/datum/unit_test/dq_fwg3_ask/ladder_assembly
/datum/unit_test/dq_fwg3_ask/ladder_assembly/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/structure/ladder_assembly/L = allocate(/obj/structure/ladder_assembly, T)
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	H.put_in_active_hand(P)
	test_click(H, L, P)
	answer(H, "Up")
	TEST_ASSERT_EQUAL(L.created_name, "Up", "the answered name")

/// Chameleon stamp: used in hand it asks which stamp to look like.
/datum/unit_test/dq_fwg3_ask/chameleon_stamp
/datum/unit_test/dq_fwg3_ask/chameleon_stamp/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/item/stamp/chameleon/S = allocate(/obj/item/stamp/chameleon, T)
	H.put_in_active_hand(S)
	var/list/choices = S.stamp_choice_types()
	TEST_ASSERT(length(choices), "there are stamps to look like")
	var/pick = choices[1]
	var/obj/item/stamp/as_type = choices[pick]
	test_click(H, S, S, GESTURE_SELF)
	answer(H, pick)
	TEST_ASSERT_EQUAL(S.name, initial(as_type.name), "it takes the picked stamp's name")

/// Alien cable coil: touched while in the other hand, it asks how much wire to take.
/datum/unit_test/dq_fwg3_ask/alien_coil
/datum/unit_test/dq_fwg3_ask/alien_coil/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/item/stack/cable_coil/alien/C = allocate(/obj/item/stack/cable_coil/alien, T)
	H.put_in_inactive_hand(C)
	test_click(H, C, null)
	answer(H, 5)
	var/obj/item/stack/cable_coil/taken = H.get_active_hand()
	TEST_ASSERT(istype(taken, /obj/item/stack/cable_coil), "a coil is taken into the hand")
	TEST_ASSERT_EQUAL(taken?.get_amount(), 5, "of the answered length")

/// Paper bin: with no custom paper it asks which paper; regular paper comes out into the hand.
/datum/unit_test/dq_fwg3_ask/paper_bin
/datum/unit_test/dq_fwg3_ask/paper_bin/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/item/paper_bin/B = allocate(/obj/item/paper_bin, T)
	var/start = B.amount
	test_click(H, B, null)
	answer(H, "Carbon-Copy")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/paper/carbon), "a carbon copy paper is taken")
	TEST_ASSERT_EQUAL(B.amount, start - 1, "the bin has one fewer")
	H.drop_item()
	test_click(H, B, null)
	answer(H, "Cancel")
	TEST_ASSERT_NULL(H.get_active_hand(), "cancel takes nothing")
	TEST_ASSERT_EQUAL(B.amount, start - 1, "and leaves the count")

/// Trolley tank: a multitool repaints it (a colour question); a pen relabels it (a text question).
/datum/unit_test/dq_fwg3_ask/trolley_tank
/datum/unit_test/dq_fwg3_ask/trolley_tank/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/vehicle/train/trolley_tank/V = allocate(/obj/vehicle/train/trolley_tank, T)
	var/obj/item/multitool/M = allocate(/obj/item/multitool, T)
	H.put_in_active_hand(M)
	test_click(H, V, M)
	answer(H, "#ff0000")
	TEST_ASSERT_EQUAL(V.paint_color, "#ff0000", "the multitool repaints it")
	H.drop_item()
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	H.put_in_active_hand(P)
	test_click(H, V, P)
	answer(H, "Fuel")
	TEST_ASSERT_EQUAL(V.name, "[initial(V.name)] - 'Fuel'", "the pen relabels it")
