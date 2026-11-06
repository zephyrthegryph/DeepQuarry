/// Requirements instead of message-and-return refusals, and the hat_bearer capability: what a player observes stays the same.
/datum/unit_test/dq_review_leftovers
	abstract_type = /datum/unit_test/dq_review_leftovers

/datum/unit_test/dq_review_leftovers/proc/card(turf/T)
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, T)
	E.set_uses(5)
	return E

/// A spent voucher refuses the sequencer and keeps the card's use; a fresh one switches to special delivery once.
/datum/unit_test/dq_review_leftovers/pizza_voucher_refusal
/datum/unit_test/dq_review_leftovers/pizza_voucher_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pizzavoucher/V = allocate(/obj/item/pizzavoucher, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	V.set_spent(TRUE)
	test_click(H, V, E)
	test_time(1 SECOND)
	TEST_ASSERT(!V.special_delivery, "a spent voucher stays as it was")
	TEST_ASSERT_EQUAL(E.uses, 5, "and the card keeps its use")
	V.set_spent(FALSE)
	test_click(H, V, E)
	test_time(1 SECOND)
	TEST_ASSERT(V.special_delivery, "a fresh voucher goes to special delivery")
	TEST_ASSERT_EQUAL(E.uses, 4, "and the card pays one use")
	test_click(H, V, E)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(E.uses, 4, "a voucher already in special delivery takes no second use")

/// The recorder refuses a second sequencer.
/datum/unit_test/dq_review_leftovers/taperecorder_refusal
/datum/unit_test/dq_review_leftovers/taperecorder_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/taperecorder/R = allocate(/obj/item/taperecorder, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	test_click(H, R, E)
	test_time(1 SECOND)
	TEST_ASSERT(R.emagged, "the sequencer fries the recorder")
	TEST_ASSERT_EQUAL(E.uses, 4, "and the card pays one use")
	test_click(H, R, E)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(E.uses, 4, "an emagged recorder takes no second use")

/// The special operations console cannot be emagged, and the card keeps its use.
/datum/unit_test/dq_review_leftovers/specops_console_refuses
/datum/unit_test/dq_review_leftovers/specops_console_refuses/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/specops_shuttle/C = allocate(/obj/machinery/computer/specops_shuttle, T)
	var/obj/item/card/emag/E = card(T)
	H.put_in_active_hand(E)
	test_click(H, C, E)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(E.uses, 5, "the card keeps its use")
	TEST_ASSERT(!C.emagged(), "and the console is not subverted")

/// A hat goes on a slime, a second one is refused, and an empty hand in the grab stance takes it off again.
/datum/unit_test/dq_review_leftovers/hat_bearer_slime
/datum/unit_test/dq_review_leftovers/hat_bearer_slime/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/slime/S = allocate(/mob/living/simple_mob/slime, T)
	var/obj/item/clothing/head/hat_one = allocate(/obj/item/clothing/head/soft/red, T)
	var/obj/item/clothing/head/hat_two = allocate(/obj/item/clothing/head/soft/red, T)
	H.put_in_active_hand(hat_one)
	test_click(H, S, hat_one)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(S.hat, hat_one, "the hat goes on the slime")
	H.put_in_active_hand(hat_two)
	test_click(H, S, hat_two)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(S.hat, hat_one, "a second hat is refused")
	H.drop_from_inventory(hat_two, T)
	H.set_use_stance(I_GRAB)
	test_click(H, S, null)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(S.hat, "the slime's hat comes off")
	TEST_ASSERT(hat_one.loc == H, "into the taker's hands")

/// A catslug that cannot wear hats refuses one.
/datum/unit_test/dq_review_leftovers/hat_bearer_allowed
/datum/unit_test/dq_review_leftovers/hat_bearer_allowed/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/vore/alienanimals/catslug/C = allocate(/mob/living/simple_mob/vore/alienanimals/catslug, T)
	var/obj/item/clothing/head/hat = allocate(/obj/item/clothing/head/soft/red, T)
	C.set_can_wear_hat(FALSE)
	H.put_in_active_hand(hat)
	test_click(H, C, hat)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(C.hat, "a catslug with an inbuilt hat takes no other")
	C.set_can_wear_hat(TRUE)
	test_click(H, C, hat)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(C.hat, hat, "one that can takes it")

/// The dice window refuses text that is not a roll and rolls text that is.
/datum/unit_test/dq_review_leftovers/rpg_dice_custom_roll
/datum/unit_test/dq_review_leftovers/rpg_dice_custom_roll/Run()
	var/datum/board_game/rpg_dice/D = allocate(/datum/board_game/rpg_dice)
	TEST_ASSERT_NULL(D.parse_roll("hello"), "text that is not a roll parses to nothing")
	TEST_ASSERT_NULL(D.parse_roll("2d0"), "a die of no sides parses to nothing")
	var/list/roll = D.parse_roll("2d6-3")
	TEST_ASSERT_EQUAL(roll[1], 2, "the count")
	TEST_ASSERT_EQUAL(roll[2], 6, "the size")
	TEST_ASSERT_EQUAL(roll[3], -3, "the modifier")
	TEST_ASSERT_EQUAL(D.parse_roll("d20")[1], 1, "the count defaults to one")
