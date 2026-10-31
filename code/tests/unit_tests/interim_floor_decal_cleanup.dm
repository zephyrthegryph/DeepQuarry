/// Actual ash sifting consumes the original decal and adds its real dirt amount.
/datum/unit_test/interim_ash_sifting/Run()
	var/turf/simulated/floor/T = run_loc_floor_bottom_left
	TEST_ASSERT(istype(T), "the actual ash fixture uses a simulated floor")
	var/original_dirt = T.dirt
	set_var(T, nameof(T.dirt), original_dirt)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/effect/decal/cleanable/ash/ash = allocate(/obj/effect/decal/cleanable/ash, T)
	var/obj/item/pen/unrelated = allocate(/obj/item/pen, T)
	TEST_ASSERT(!QDELETED(ash), "the actual ash decal initializes alive")
	TEST_ASSERT(test_op_committed(perform_op(user, ash, "sift_ash")), "actual ash sifting commits")
	TEST_ASSERT(QDELETED(ash), "actual ash sifting consumes the original decal")
	TEST_ASSERT_EQUAL(T.dirt, original_dirt + 4, "actual ash sifting adds exactly four units of floor dirt")
	T.dirt = original_dirt
	TEST_ASSERT(!QDELETED(unrelated), "actual ash sifting preserves an unrelated floor item")
	TEST_ASSERT_EQUAL(unrelated.loc, T, "the unrelated floor item retains its original location")

/// Actual confetti cleanup waits for its task and preserves the decal when the actor moves away.
/datum/unit_test/interim_confetti_cleanup
	var/interrupted = FALSE

/datum/unit_test/interim_confetti_cleanup/interrupted
	interrupted = TRUE

/datum/unit_test/interim_confetti_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/effect/decal/cleanable/confetti/confetti = allocate(/obj/effect/decal/cleanable/confetti, T)
	TEST_ASSERT(!QDELETED(confetti), "the actual confetti decal initializes alive")
	perform_op(user, confetti, "pick_confetti")
	TEST_ASSERT(length(op_pendings_of(user)) > 0, "actual confetti picking starts its real timed task")
	TEST_ASSERT(!QDELETED(confetti), "starting actual confetti picking does not remove the decal immediately")
	if(interrupted)
		var/turf/away = get_step(get_step(T, EAST), EAST)
		TEST_ASSERT(away, "the actual cancellation fixture has a floor outside reach")
		user.forceMove(away)
	test_time(5 SECONDS)
	TEST_ASSERT(!QDELETED(confetti), "the actual confetti decal survives before the six-second deadline")
	test_time(1 SECOND)
	if(interrupted)
		TEST_ASSERT(!QDELETED(confetti), "moving the actual actor out of reach cancels cleanup without consuming confetti")
		TEST_ASSERT_EQUAL(confetti.loc, T, "cancelled actual cleanup preserves the decal's original floor")
	else
		TEST_ASSERT(QDELETED(confetti), "the actual six-second task consumes the original confetti")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/decal/cleanable/confetti)), 0, "actual completed cleanup leaves no confetti decal")
	TEST_ASSERT(!QDELETED(user), "actual confetti cleanup preserves its actor")
