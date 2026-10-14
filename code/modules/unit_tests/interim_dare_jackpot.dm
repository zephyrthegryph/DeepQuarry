/// The real delayed dare-button jackpot honors source release before creating its prize.
/datum/unit_test/interim_dare_jackpot
	var/sticky = FALSE

/datum/unit_test/interim_dare_jackpot/sticky
	sticky = TRUE

/datum/unit_test/interim_dare_jackpot/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/daredevice/button = allocate(/obj/item/daredevice, T)
	TEST_ASSERT(user.put_in_active_hand(button), "actual dare button starts held")
	button.luckynumber7 = 9
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/gun/energy/sizegun/not_advanced)), 0, "real jackpot destination starts without prizes")
	if(sticky)
		add_trait(button, TRAIT_NODROP, "interim_dare_jackpot")
		TEST_ASSERT(button.loc.release_refusal(button, user), "actual sticky button refuses release")
	TEST_ASSERT(test_op_handler(button, "interaction_self", user, button), "actual dare-button activation schedules its result")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(button), 1, "actual activation schedules one result timer")
	test_time(9 SECONDS)
	TEST_ASSERT(!QDELETED(button), "actual jackpot keeps its source before the result deadline")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/gun/energy/sizegun/not_advanced)), 0, "real jackpot creates no early prize")
	test_time(1 SECOND)
	if(sticky)
		TEST_ASSERT(!QDELETED(button), "refused actual jackpot preserves the original source")
		TEST_ASSERT_EQUAL(user.get_active_hand(), button, "refused jackpot preserves its held slot")
		TEST_ASSERT_EQUAL(button.luckynumber7, 9, "refused jackpot preserves its pending result state")
		TEST_ASSERT_EQUAL(time_scheduler().timer_count(button), 0, "actual jackpot refusal does not schedule an unrelated reset")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/gun/energy/sizegun/not_advanced)), 0, "refused jackpot creates no duplicate prize")
		remove_trait(button, TRAIT_NODROP, "interim_dare_jackpot")
		TEST_ASSERT(test_op_handler(button, "interaction_self", user, button), "actual public retry schedules the same preserved jackpot")
		test_time(10 SECONDS)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(button), "successful real jackpot consumes the exact source button")
	TEST_ASSERT_NULL(user.get_active_hand(), "successful jackpot vacates the original held source slot")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(button), 0, "consumed jackpot source retains no timer")
	var/list/prizes = contents_of(T, /obj/item/gun/energy/sizegun/not_advanced)
	TEST_ASSERT_EQUAL(length(prizes), 1, "successful actual jackpot creates exactly one declared sizegun prize")
	var/obj/item/gun/energy/sizegun/not_advanced/prize = prizes[1]
	TEST_ASSERT_EQUAL(prize.type, /obj/item/gun/energy/sizegun/not_advanced, "real jackpot preserves its exact configured product identity")
	TEST_ASSERT_EQUAL(prize.loc, T, "real jackpot returns its prize at the actual owner's original location")
