// The Crossed() calls a step makes (/atom/movable/Move): what stands on the turf entered is crossed by the mover; the mover is not.

/// A movable that records who crossed it.
/obj/item/dq_cross_probe
	var/list/crossed_by

/obj/item/dq_cross_probe/Crossed(atom/movable/AM, oldloc)
	LAZYADD(crossed_by, AM)

/// A step onto a turf crosses what stands there, and never the mover itself (it is in the turf by then).
/datum/unit_test/dq_move_crossed_not_self/Run()
	var/turf/from = run_loc_floor_bottom_left
	var/turf/dest = get_step(from, EAST)
	TEST_ASSERT(istype(dest, /turf/simulated/floor), "the test room has a floor east of the corner")
	var/obj/item/dq_cross_probe/mover = allocate(/obj/item/dq_cross_probe, from)
	var/obj/item/dq_cross_probe/standing = allocate(/obj/item/dq_cross_probe, dest)
	TEST_ASSERT(mover.Move(dest, EAST), "the probe steps east")
	TEST_ASSERT_EQUAL(mover.loc, dest, "the probe is on the next turf")
	TEST_ASSERT(mover in standing.crossed_by, "the thing standing there was crossed by the mover")
	TEST_ASSERT(!(mover in mover.crossed_by), "the mover did not cross itself")
