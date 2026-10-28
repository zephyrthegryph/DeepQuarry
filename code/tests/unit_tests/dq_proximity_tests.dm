// Client proximity relevance (code/controllers/subsystems/proximity.dm): a tracked thing holds STAT_RELEVANCE while a client eye is in its cell or
// the eight around it, and an every(when = STAT_RELEVANCE) parks while it is none. Eyes are /datum/proximity_eye records, so the tests need no client.
// Cells are 8 turfs a side: x = 30 and x = 34 are neighbours, x = 60 is far.

/datum/unit_test/dq_proximity
	abstract_type = /datum/unit_test/dq_proximity
	var/turf/near_turf
	var/turf/neighbour_turf
	var/turf/far_turf
	var/datum/proximity_eye/eye

/datum/unit_test/dq_proximity/Run()
	test_driver_begin()
	var/z = run_loc_floor_bottom_left.z
	near_turf = locate(30, 30, z)
	neighbour_turf = locate(34, 30, z)
	far_turf = locate(60, 30, z)
	eye = new
	run_proximity()
	SSproximity.eye_place(eye, null)
	qdel(eye)
	test_driver_end()

/datum/unit_test/dq_proximity/proc/run_proximity()
	return

/datum/unit_test/dq_proximity/proc/relevance(atom/A)
	return stat_value(A, STAT_RELEVANCE)

/// An eye in a cell makes its cell and the neighbours relevant, not a far one; leaving, or the client logging out, takes it back.
/datum/unit_test/dq_proximity/enter_and_leave_cell
/datum/unit_test/dq_proximity/enter_and_leave_cell/run_proximity()
	var/obj/prox_probe/same = allocate(/obj/prox_probe, near_turf)
	var/obj/prox_probe/next = allocate(/obj/prox_probe, neighbour_turf)
	var/obj/prox_probe/far = allocate(/obj/prox_probe, far_turf)
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NONE, "nobody near: not relevant")
	SSproximity.eye_place(eye, near_turf)
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NEAR, "same cell")
	TEST_ASSERT_EQUAL(relevance(next), RELEVANCE_NEAR, "neighbour cell")
	TEST_ASSERT_EQUAL(relevance(far), RELEVANCE_NONE, "far cell")
	SSproximity.eye_place(eye, far_turf)
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NONE, "the eye left: released")
	TEST_ASSERT_EQUAL(relevance(far), RELEVANCE_NEAR, "and the far one gained it")
	SSproximity.eye_place(eye, null)
	TEST_ASSERT_EQUAL(relevance(far), RELEVANCE_NONE, "logout: released")

/// Two eyes in one cell: the cell stays near until the last one leaves.
/datum/unit_test/dq_proximity/two_eyes_share_a_cell
/datum/unit_test/dq_proximity/two_eyes_share_a_cell/run_proximity()
	var/obj/prox_probe/same = allocate(/obj/prox_probe, near_turf)
	var/datum/proximity_eye/other = new
	SSproximity.eye_place(eye, near_turf)
	SSproximity.eye_place(other, near_turf)
	SSproximity.eye_place(eye, null)
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NEAR, "one eye is still there")
	SSproximity.eye_place(other, null)
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NONE, "the last one left")
	qdel(other)

/// A z-level change moves the eye to a cell on the other level.
/datum/unit_test/dq_proximity/z_change
/datum/unit_test/dq_proximity/z_change/run_proximity()
	if(world.maxz < 2)
		return
	var/obj/prox_probe/same = allocate(/obj/prox_probe, near_turf)
	SSproximity.eye_place(eye, near_turf)
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NEAR, "same level")
	SSproximity.eye_place(eye, locate(30, 30, near_turf.z == 1 ? 2 : 1))
	TEST_ASSERT_EQUAL(relevance(same), RELEVANCE_NONE, "the eye changed level: this level is no longer near")

/// A tracked thing moved into an occupied cell gains relevance, out of it loses it; carried, it stays relevant.
/datum/unit_test/dq_proximity/object_moves
/datum/unit_test/dq_proximity/object_moves/run_proximity()
	var/obj/prox_probe/probe = allocate(/obj/prox_probe, far_turf)
	SSproximity.eye_place(eye, near_turf)
	TEST_ASSERT_EQUAL(relevance(probe), RELEVANCE_NONE, "far from the eye")
	probe.forceMove(neighbour_turf)
	TEST_ASSERT_EQUAL(relevance(probe), RELEVANCE_NEAR, "moved into a near cell")
	probe.forceMove(far_turf)
	TEST_ASSERT_EQUAL(relevance(probe), RELEVANCE_NONE, "moved out of it")
	var/obj/item/storage/box/carrier = allocate(/obj/item/storage/box, far_turf)
	probe.forceMove(carrier)
	TEST_ASSERT_EQUAL(relevance(probe), RELEVANCE_NEAR, "carried: relevant wherever the carrier goes")
	probe.forceMove(far_turf)
	TEST_ASSERT_EQUAL(relevance(probe), RELEVANCE_NONE, "put down far away: not")

/// A tracked thing initialised inside a container before the proximity system's init stage (a mouse nest in a trash pile at map load) is carried at
/// once: the source of its hold must exist from New(), not from initialize(). A fresh system instance has only had New().
/datum/unit_test/dq_proximity/carried_before_init
/datum/unit_test/dq_proximity/carried_before_init/run_proximity()
	var/datum/system/proximity/fresh = new
	TEST_ASSERT(fresh.carried, "a new proximity system already has its carried source")
	var/obj/item/storage/box/carrier = allocate(/obj/item/storage/box, far_turf)
	var/obj/prox_probe/probe = allocate(/obj/prox_probe, carrier)
	fresh.member_update(probe)
	TEST_ASSERT_EQUAL(relevance(probe), RELEVANCE_NEAR, "carried: held under the new system's source")
	fresh.member_leave(probe)

/// An every() parks while nobody is near, runs while somebody is, and parks again.
/datum/unit_test/dq_proximity/every_parks_and_wakes
/datum/unit_test/dq_proximity/every_parks_and_wakes/run_proximity()
	var/obj/prox_probe/probe = allocate(/obj/prox_probe, near_turf)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(probe.ticks, 0, "nobody near: it never ran")
	TEST_ASSERT(length(probe.rx?.every_parked), "and it holds no timer")
	SSproximity.eye_place(eye, near_turf)
	test_time(4 SECONDS)
	TEST_ASSERT(probe.ticks >= 3 && probe.ticks <= 4, "a client near: it ran on its interval (ran [probe.ticks])")
	TEST_ASSERT(!length(probe.rx?.every_parked), "no longer parked")
	SSproximity.eye_place(eye, far_turf)
	var/seen = probe.ticks
	test_time(4 SECONDS)
	TEST_ASSERT(probe.ticks <= seen + 1, "the client left: it stopped (ran [probe.ticks - seen] more)")
	TEST_ASSERT(length(probe.rx?.every_parked), "and parked again")
	SSproximity.eye_place(eye, near_turf)
	seen = probe.ticks
	test_time(3 SECONDS)
	TEST_ASSERT(probe.ticks > seen, "woken once more")

/// The map-effect interval runs through the tracker: parked alone, firing near a client, held relevant by always_run.
/datum/unit_test/dq_proximity/map_effect_interval
/datum/unit_test/dq_proximity/map_effect_interval/run_proximity()
	var/obj/effect/map_effect/interval/prox_counter/effect = allocate(/obj/effect/map_effect/interval/prox_counter, near_turf)
	var/obj/effect/map_effect/interval/prox_counter/always/steady = allocate(/obj/effect/map_effect/interval/prox_counter/always, far_turf)
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(effect.fired, 0, "nobody near: no trigger")
	TEST_ASSERT(steady.fired >= 3, "always_run: it triggers with nobody near (fired [steady.fired])")
	SSproximity.eye_place(eye, near_turf)
	test_time(4 SECONDS)
	TEST_ASSERT(effect.fired >= 3, "a client near: it triggers (fired [effect.fired])")

/// What the tracker costs: a cell with many tracked members flipping near and far, and a client crossing cells.
/datum/unit_test/dq_proximity/cost
/datum/unit_test/dq_proximity/cost/run_proximity()
	var/list/probes = list()
	for(var/i in 1 to 200)
		probes += allocate(/obj/prox_probe, near_turf)
	var/start = world.tick_usage
	var/toggles = 200
	for(var/i in 1 to toggles)
		SSproximity.eye_place(eye, i % 2 ? near_turf : far_turf)
	var/flip_cost = world.tick_usage - start
	start = world.tick_usage
	var/moves = 2000
	for(var/i in 1 to moves)
		SSproximity.eye_place(eye, locate(30 + (i % 3), 30, near_turf.z))
	var/step_cost = world.tick_usage - start
	TEST_NOTICE(src, "[toggles] near/far flips of a cell with 200 tracked members: [flip_cost]% of a tick; [moves] eye steps inside one cell: [step_cost]% of a tick")
	TEST_ASSERT_EQUAL(relevance(probes[1]), RELEVANCE_NEAR, "still near after the steps")
