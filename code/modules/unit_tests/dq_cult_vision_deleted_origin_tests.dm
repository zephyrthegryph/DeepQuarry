// The timer must run live-holder cleanup even after its old container has died.
/datum/visualnet/cult/dq_cult_timer_probe
	var/current_updates = 0
	var/atom/expected_location

/datum/visualnet/cult/dq_cult_timer_probe/updateVisibility(atom/A, opacity_check = 1)
	if(A && A == expected_location)
		current_updates++
	return ..()

/datum/unit_test/dq_cult_vision_deleted_origin

/datum/unit_test/dq_cult_vision_deleted_origin/proc/dispose_net(datum/visualnet/cult/net, mob/living/actor, obj/container, datum/visualnet/cult/original_net)
	qdel(actor)
	qdel(container)
	set_global(nameof(GLOB.cultnet), original_net)
	qdel(net, TRUE)

/datum/unit_test/dq_cult_vision_deleted_origin/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	set_global(nameof(GLOB.om_resolve_nulled), GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/turf/next = get_step(T, NORTH)
	TEST_ASSERT(next && !next.density, "the fixture supplies a real adjacent destination")
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture, T)
	var/obj/container = allocate(/obj, T)
	M.forceMove(container)
	cancel_after(M, TIMER_CULT_VISION_SETTLE)
	var/datum/visualnet/cult/original_net = GLOB.cultnet
	var/datum/visualnet/cult/dq_cult_timer_probe/N = new
	defer_cleanup(src, PROC_REF(dispose_net), N, M, container, original_net)
	set_global(nameof(GLOB.cultnet), N)
	N.expected_location = T
	M.forceMove(T)
	TEST_ASSERT(after_pending(M, TIMER_CULT_VISION_SETTLE), "real movement re-arms after actual timer cancellation")
	qdel(container)
	TEST_ASSERT(QDELETED(container), "the continuation's real non-owner argument is deleted")
	test_time(1 SECOND)
	M.forceMove(next)
	M.forceMove(T)
	var/left = after_left(M, TIMER_CULT_VISION_SETTLE)
	TEST_ASSERT(left > 1.9 SECONDS && left < 2.1 SECONDS, "repeated real moves coalesce at the original deadline instead of restarting it")
	test_time(1.9 SECONDS)
	TEST_ASSERT(after_pending(M, TIMER_CULT_VISION_SETTLE) && N.current_updates == 0, "the original three-second buffer has not elapsed early")
	test_time(0.2 SECONDS)
	TEST_ASSERT(!after_pending(M, TIMER_CULT_VISION_SETTLE), "delivery releases the real native continuation")
	TEST_ASSERT_EQUAL(N.current_updates, 1, "the actual visualnet refreshes the live current location exactly once despite the deleted origin")
	M.forceMove(next)
	TEST_ASSERT(after_pending(M, TIMER_CULT_VISION_SETTLE), "subsequent movement schedules a new continuation")
	qdel(M)
	test_time(3.1 SECONDS)
	TEST_ASSERT(!after_pending(M, TIMER_CULT_VISION_SETTLE), "destroying the holder cancels its continuation")
