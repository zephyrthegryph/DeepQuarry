/// A bot's route is a path request: asking for one leaves the bot waiting (no stepping a stale path), and the answer becomes its route.
/datum/unit_test/dq_bot_path_request

/datum/unit_test/dq_bot_path_request/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/goal = locate(start.x + 3, start.y, start.z)
	TEST_ASSERT(isturf(goal), "the test block is wide enough")
	var/mob/living/bot/cleanbot/B = allocate(/mob/living/bot/cleanbot, start)
	var/obj/item/pen/marker = allocate(/obj/item/pen, goal)
	rel_set(B, nameof(B.target), marker)
	var/jps_before = LAZYACCESS(SSpathing.searched_by_algorithm, "[PATH_ALGORITHM_JPS]")
	var/astar_before = LAZYACCESS(SSpathing.searched_by_algorithm, "[PATH_ALGORITHM_ASTAR]")
	B.calcTargetPath()
	TEST_ASSERT(B.path_pending, "the route is asked for, not computed on the spot")
	TEST_ASSERT_EQUAL(length(B.target_path), 0, "and the bot has no route yet")
	for(var/waited in 1 to 100)
		if(!B.path_pending)
			break
		wait_ticks(1)
	TEST_ASSERT(!B.path_pending, "the path system answered")
	TEST_ASSERT(length(B.target_path) >= 1, "the answer is the bot's route")
	TEST_ASSERT_EQUAL(B.target_path[length(B.target_path)], goal, "which ends at the target")
	TEST_ASSERT_EQUAL(LAZYACCESS(SSpathing.searched_by_algorithm, "[PATH_ALGORITHM_JPS]"), jps_before + 1, "a bot's request is searched with JPS")
	TEST_ASSERT_EQUAL(LAZYACCESS(SSpathing.searched_by_algorithm, "[PATH_ALGORITHM_ASTAR]"), astar_before, "and not with A*")
	for(var/turf/step_turf as anything in B.target_path)
		TEST_ASSERT(isturf(step_turf), "the JPS jump points are expanded into walkable turfs")
