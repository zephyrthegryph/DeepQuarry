// The progress bar of an op's wait: shown by default, opted out by silent_wait(), and the wait is cancelled when the actor walks away.

/datum/unit_test/dq_eg2_wait
	abstract_type = /datum/unit_test/dq_eg2_wait

/datum/unit_test/dq_eg2_wait/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_eg2_wait/proc/run_gate()
	return

/datum/unit_test/dq_eg2_wait/a_timed_wait_draws_a_progress_bar
/datum/unit_test/dq_eg2_wait/a_timed_wait_draws_a_progress_bar/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/eg2_waiter/W = allocate(/obj/eg2_waiter, run_loc_floor_bottom_left)
	test_menu(H, W, "slow")
	var/datum/pending_op/P = op_pending_of(H)
	TEST_ASSERT_NOTNULL(P, "the op is waiting")
	TEST_ASSERT(P.progress_planned, "its wait draws a progress bar by default")
	TEST_ASSERT_NOTNULL(P.cog, "and onlookers see a cog for a wait of a second or more")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(W.done, 1, "the op ran when the wait ended")
	TEST_ASSERT_NULL(P.cog, "and the cog went")

/datum/unit_test/dq_eg2_wait/silent_wait_draws_nothing
/datum/unit_test/dq_eg2_wait/silent_wait_draws_nothing/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/eg2_waiter/W = allocate(/obj/eg2_waiter, run_loc_floor_bottom_left)
	test_menu(H, W, "hush")
	var/datum/pending_op/P = op_pending_of(H)
	TEST_ASSERT_NOTNULL(P, "the op is waiting")
	TEST_ASSERT(!P.progress_planned && isnull(P.cog), "a silent wait draws no bar and no cog")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(W.done, 1, "and still runs")

/datum/unit_test/dq_eg2_wait/walking_away_cancels_the_wait
/datum/unit_test/dq_eg2_wait/walking_away_cancels_the_wait/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/eg2_waiter/W = allocate(/obj/eg2_waiter, run_loc_floor_bottom_left)
	test_menu(H, W, "slow")
	test_time(1 SECONDS)
	H.forceMove(get_step(H, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(W.done, 0, "the actor moved, so the timed action was cancelled")
	TEST_ASSERT_NULL(op_pending_of(H), "and nothing is pending")
