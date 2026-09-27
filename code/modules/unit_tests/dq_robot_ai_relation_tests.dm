/mob/living/silicon/robot/dq_ai_link_test
	var/sync_calls = 0

/mob/living/silicon/robot/dq_ai_link_test/sync()
	sync_calls++

/datum/unit_test/dq_robot_ai_relation_lifecycle

/datum/unit_test/dq_robot_ai_relation_lifecycle/Run()
	var/turf/test_turf = run_loc_floor_bottom_left
	var/mob/living/silicon/robot/dq_ai_link_test/R = new(test_turf)
	R.set_master_ai(null, TRUE)
	R.lawupdate = TRUE
	R.sync_calls = 0
	var/mob/living/silicon/ai/first = new(test_turf, null, null, null, TRUE)
	var/mob/living/silicon/ai/second = new(test_turf, null, null, null, TRUE)
	TEST_ASSERT(R.set_master_ai(first, TRUE), "robot could not connect to first AI")
	TEST_ASSERT(R.connected_ai == first, "robot did not point to first AI")
	TEST_ASSERT(R in first.connected_robots, "first AI did not index the robot")
	TEST_ASSERT(om_has_link(R, /datum/object_model/relation/robot_master_ai, first), "robot to AI relationship was not created")
	TEST_ASSERT(R.Observed(first, COMSIG_SILICON_LAWS_CHANGED, TYPE_PROC_REF(/mob/living/silicon/robot, on_master_laws_changed)), "law-change subscription was not installed")
	TEST_ASSERT(R.set_master_ai(second, TRUE), "robot could not reassign to second AI")
	TEST_ASSERT(R.connected_ai == second, "robot did not point to second AI")
	TEST_ASSERT(R in second.connected_robots, "second AI did not index the robot")
	TEST_ASSERT(!(R in first.connected_robots), "first AI retained the robot after reassignment")
	TEST_ASSERT(!om_has_link(R, /datum/object_model/relation/robot_master_ai, first) && om_has_link(R, /datum/object_model/relation/robot_master_ai, second), "AI reassignment left a stale relationship")
	TEST_ASSERT(!R.Observed(first, COMSIG_SILICON_LAWS_CHANGED, TYPE_PROC_REF(/mob/living/silicon/robot, on_master_laws_changed)) && R.Observed(second, COMSIG_SILICON_LAWS_CHANGED, TYPE_PROC_REF(/mob/living/silicon/robot, on_master_laws_changed)), "AI reassignment left a stale law subscription")
	SEND_SIGNAL(second, COMSIG_SILICON_LAWS_CHANGED)
	sleep(2 * world.tick_lag)
	TEST_ASSERT_EQUAL(R.sync_calls, 1, "law-change signal did not sync the linked robot once")
	qdel(second)
	TEST_ASSERT_NULL(R.connected_ai, "AI deletion left the robot linked")
	TEST_ASSERT(!om_has_link(R, /datum/object_model/relation/robot_master_ai, second), "AI deletion left the relationship installed")
	TEST_ASSERT(!R.Observed(second, COMSIG_SILICON_LAWS_CHANGED, TYPE_PROC_REF(/mob/living/silicon/robot, on_master_laws_changed)), "AI deletion left the law subscription installed")
	qdel(first)
	var/mob/living/silicon/ai/third = new(test_turf, null, null, null, TRUE)
	TEST_ASSERT(R.set_master_ai(third, TRUE), "robot could not connect to third AI")
	qdel(R)
	TEST_ASSERT(!(R in third.connected_robots), "robot deletion left a stale AI connected-robots index")
	qdel(third)
