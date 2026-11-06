// hop_moved() publishes the turf of a mover only on things whose reads cross it. A draw that reads "turf" (a vent pump drawing the floor it sits on)
// must be one of them, or moving it to another floor never redraws it.

/datum/unit_test/dq_hop_moved_publishes_to_draw_turf_reader

/datum/unit_test/dq_hop_moved_publishes_to_draw_turf_reader/Run()
	var/obj/machinery/atmospherics/unary/vent_pump/V = allocate(/obj/machinery/atmospherics/unary/vent_pump, run_loc_floor_bottom_left)
	TEST_ASSERT(V, "a vent pump allocated")
	TEST_ASSERT(HOP_TURF in plan_keys(V.type, PLAN_DRAW), "the vent pump's draw reads the turf it lies on (the generated plan)")
	TEST_ASSERT(hop_segment_read(HOP_TURF), "the turf segment is read by some generated draw")
	TEST_ASSERT(GLOB.stat_input_keys?[HOP_TURF] || GLOB.derived_read_vars?[HOP_TURF] || READERS(V, HOP_TURF), "hop_moved() reaches a draw that reads the turf")
