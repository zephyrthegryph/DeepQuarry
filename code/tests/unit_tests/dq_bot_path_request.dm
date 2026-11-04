/// A bot's route is a path request: asking for one leaves the bot waiting (no stepping a stale path), and the answer becomes its route.
/datum/unit_test/dq_bot_path_request

/datum/unit_test/dq_bot_path_request/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/goal = locate(start.x + 3, start.y, start.z)
	TEST_ASSERT(isturf(goal), "the test block is wide enough")
	var/mob/living/bot/cleanbot/B = allocate(/mob/living/bot/cleanbot, start)
	var/obj/item/pen/marker = allocate(/obj/item/pen, goal)
	rel_set(B, nameof(B.target), marker)
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
