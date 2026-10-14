/// Item emags as the library's emag op (code/library/access/emag.dm): a sequencer click runs the item's own effect, a card use is spent
/// only when the effect did something, and a choice asked first is the op's step. Pinned on the converted items (items/structures wave).
/datum/unit_test/dq_items_emag_ops
	abstract_type = /datum/unit_test/dq_items_emag_ops

/datum/unit_test/dq_items_emag_ops/proc/card(turf/T)
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, T)
	E.uses = 5
	return E

/// The megaphone's voice synthesizer is overloaded once; the card pays one use.
/datum/unit_test/dq_items_emag_ops/megaphone
/datum/unit_test/dq_items_emag_ops/megaphone/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/megaphone/M = allocate(/obj/item/megaphone, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	test_click(H, M, E)
	test_time(2 SECONDS)
	TEST_ASSERT(M.emagged, "the sequencer overloads the megaphone")
	TEST_ASSERT_EQUAL(E.uses, 4, "and the card pays one use")
	test_click(H, M, E)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(E.uses, 4, "a subverted megaphone takes no second use")

/// The paddles' safety toggles each time (a repeatable emag).
/datum/unit_test/dq_items_emag_ops/paddles
/datum/unit_test/dq_items_emag_ops/paddles/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/shockpaddles/standalone/P = allocate(/obj/item/shockpaddles/standalone, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	var/was = P.safety
	test_click(H, P, E)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(P.safety, !was, "the sequencer flips the safety")
	test_click(H, P, E)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(P.safety, was, "and flips it back: the emag is repeatable")

/// The sleevemate asks what to become; the answer replaces it, a cancel leaves it and spends nothing.
/datum/unit_test/dq_items_emag_ops/sleevemate
/datum/unit_test/dq_items_emag_ops/sleevemate/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/sleevemate/S = allocate(/obj/item/sleevemate, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	test_click(H, S, E)
	test_time(1 SECOND)
	test_answer(H, "Cancel", REQ_CANCELLED)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(S), "a cancelled choice leaves the sleevemate")
	TEST_ASSERT_EQUAL(E.uses, 5, "and spends nothing")
	test_click(H, S, E)
	test_time(1 SECOND)
	test_answer(H, "Body Snatcher")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(S), "the chosen hack replaces the sleevemate")
	TEST_ASSERT_NOTNULL(locate(/obj/item/bodysnatcher) in T, "with a body snatcher")
	TEST_ASSERT_EQUAL(E.uses, 4, "and the card pays one use")
	qdel(locate(/obj/item/bodysnatcher) in T)
	test_time(10 SECONDS) // the sparks of the hack burn out

/// A locked cyborg's cover opens to the sequencer (a failed attempt still pays a use); an unlocked cover declines and spends nothing.
/datum/unit_test/dq_items_emag_ops/robot_cover
/datum/unit_test/dq_items_emag_ops/robot_cover/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	R.locked = FALSE
	TEST_ASSERT_EQUAL(emag_target(R, 1, H, E), EMAG_DECLINED, "an unlocked cover declines the emag")
	TEST_ASSERT_EQUAL(E.uses, 5, "and spends nothing")
	R.locked = TRUE
	for(var/attempt in 1 to 30)
		if(!R.locked)
			break
		test_click(H, R, E)
		test_time(1 SECOND)
	TEST_ASSERT(!R.locked, "the sequencer unlocks the cover within a few swipes")
	TEST_ASSERT(E.uses < 5, "and the card paid")

/// A sequencer on a human whose selected limb is natural declines and spends nothing.
/datum/unit_test/dq_items_emag_ops/human_limb
/datum/unit_test/dq_items_emag_ops/human_limb/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/obj/item/card/emag/E = card(T)
	user.put_in_active_hand(E)
	TEST_ASSERT_EQUAL(emag_target(target, 1, user, E), EMAG_DECLINED, "a natural limb declines")
	TEST_ASSERT_EQUAL(E.uses, 5, "and spends nothing")
