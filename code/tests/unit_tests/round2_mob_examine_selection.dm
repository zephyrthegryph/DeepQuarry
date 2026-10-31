/// Real mob-examine verb selection and current-candidate replay; no connected panel rendering claim.
/datum/unit_test/round2_mob_examine_selection
	var/examine_case = "selected"

/datum/unit_test/round2_mob_examine_selection/Run()
	test_driver_begin()
	exercise_examine()
	test_driver_end()

/datum/unit_test/round2_mob_examine_selection/proc/exercise_examine()
	var/turf/simulated/floor/surface
	for(var/turf/simulated/floor/candidate in world)
		if(!istype(get_step(candidate, EAST), /turf/simulated/floor) || !istype(get_step(candidate, NORTH), /turf/simulated/floor))
			continue
		var/clear_view = TRUE
		for(var/atom/visible in view(world.view, candidate))
			if(isopenspace(visible) || (ismob(visible) && !istype(visible, /mob/observer) && !visible.invisibility))
				clear_view = FALSE
				break
		if(clear_view)
			surface = candidate
			break
	TEST_ASSERT(surface, "Actual map supplies a normal floor with two real neighboring floors and no preexisting visible examine candidates or openspace")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/mob/living/carbon/human/east = allocate(/mob/living/carbon/human, get_step(surface, EAST))
	var/mob/living/carbon/human/north = allocate(/mob/living/carbon/human, get_step(surface, NORTH))
	TEST_ASSERT_NULL(user.client, "Actual test human is clientless, without a synthetic connection")
	TEST_ASSERT(!user.stat && !is_blind(user) && !user.is_paralyzed(), "Actual living human satisfies normal perception and facing gates")
	var/original_direction = user.dir
	TEST_ASSERT(original_direction != EAST && original_direction != NORTH, "Actual original facing differs from both target directions")
	user.mob_examine()
	var/datum/prompt/choice/mob_examine_selection/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.owner == user && question.answerer == user, "Actual public verb opens a native request on its original actor")
	TEST_ASSERT_EQUAL(length(question.choices), 2, "Actual production view/category/openspace filtering offers exactly the two real neighboring humans")
	TEST_ASSERT((east in question.choices) && (north in question.choices), "Actual request contains both real visible humans")
	TEST_ASSERT_EQUAL(user.dir, original_direction, "Opening the actual selection leaves real facing unchanged")
	if(examine_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
		TEST_ASSERT_EQUAL(user.dir, original_direction, "Actual close keeps original facing unchanged")
	else if(examine_case == "current_unique")
		var/turf/remote
		for(var/turf/candidate in world)
			if(candidate.z != surface.z)
				remote = candidate
				break
		TEST_ASSERT(remote, "Actual map supplies a different z-level for a genuinely removed view candidate")
		TEST_ASSERT(east.forceMove(remote), "Actual movement removes the originally selected human from the actor's current view")
		TEST_ASSERT_EQUAL(east.loc, remote, "Original candidate really leaves the current z-level")
		test_answer(user, east)
		TEST_ASSERT_EQUAL(user.dir, NORTH, "Actual replay supersedes the old answer with the sole currently visible human")
	else
		test_answer(user, east)
		TEST_ASSERT_EQUAL(user.dir, EAST, "Actual chosen human causes the production face_atom tail to turn the real actor east")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual selection or close retires its request without opening another")

/datum/unit_test/round2_mob_examine_selection/current_unique
	examine_case = "current_unique"

/datum/unit_test/round2_mob_examine_selection/cancelled
	examine_case = "cancelled"
