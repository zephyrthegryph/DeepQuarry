/// A screwdriver on a bot with locked controls is refused by its requirement (the reason, no panel change); unlocked, it opens the panel.
/datum/unit_test/dq_bot_panel_locked/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/bot/cleanbot/bot = allocate(/mob/living/bot/cleanbot, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	TEST_ASSERT(user.put_in_active_hand(screwdriver), "the user holds the screwdriver")
	bot.set_locked(TRUE)
	var/was_open = bot.open
	var/datum/op_result/R = test_click(user, bot, screwdriver)
	TEST_ASSERT(!test_op_committed(R), "a locked bot refuses the screwdriver")
	TEST_ASSERT(findtext(reason_text(R?.reason), "unlock the controls"), "the refusal says the controls are locked, got [reason_text(R?.reason)]")
	TEST_ASSERT_EQUAL(bot.open, was_open, "a refused screwdriver leaves the panel as it was")
	bot.set_locked(FALSE)
	R = test_click(user, bot, screwdriver)
	test_time(1)
	TEST_ASSERT_EQUAL(bot.open, !was_open, "an unlocked bot's panel toggles under the screwdriver")
	test_driver_end()
