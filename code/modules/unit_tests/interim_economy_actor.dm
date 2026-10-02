/// Reset reads the supplied operator's ID, even outside a UI's ambient usr context.
/datum/unit_test/interim_eftpos_reset_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/operator = allocate(/mob/living/carbon/human, T)
	var/obj/item/eftpos/terminal = allocate(/obj/item/eftpos, T)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	terminal.access_code = 1234
	card.access = list(ACCESS_RESEARCH)
	TEST_ASSERT(operator.put_in_active_hand(card), "the operator holds the ID being checked")
	TEST_ASSERT(terminal.ui_act_reset(operator, list(), null, null, "reset"), "reset action is handled")
	TEST_ASSERT_EQUAL(terminal.access_code, 1234, "an unauthorized ID preserves the code")
	card.access = list(ACCESS_HOP)
	TEST_ASSERT(terminal.ui_act_reset(operator, list(), null, null, "reset"), "authorized reset is handled")
	TEST_ASSERT_EQUAL(terminal.access_code, 0, "the supplied operator's authorized ID resets the code")
	TEST_ASSERT_EQUAL(card.loc, operator, "reset does not consume or eject the ID")

/// The physical card swipe threads its operator to the same transaction helper.
/datum/unit_test/interim_eftpos_emag_swipe_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/operator = allocate(/mob/living/carbon/human, T)
	var/obj/item/eftpos/terminal = allocate(/obj/item/eftpos, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	terminal.transaction_locked = TRUE
	terminal.transaction_paid = FALSE
	terminal.scan_card(card, card, operator)
	TEST_ASSERT(terminal.transaction_paid, "an emag swipe marks the locked transaction paid")
	TEST_ASSERT(terminal.transaction_locked, "the first swipe preserves the transaction lock")
	terminal.scan_card(card, card, operator)
	TEST_ASSERT(!terminal.transaction_locked, "a second swipe unlocks the paid transaction")
	TEST_ASSERT(!terminal.transaction_paid, "unlocking clears the transaction's paid state")
	TEST_ASSERT(!QDELETED(card), "swiping does not consume the card")
