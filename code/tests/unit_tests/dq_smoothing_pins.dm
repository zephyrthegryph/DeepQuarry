/// A broken belt stops the belts of its line on both sides (they are found through the conveyor adjacency kind).
/datum/unit_test/dq_conveyor_line_breaks

/datum/unit_test/dq_conveyor_line_breaks/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/list/belts = list()
	for(var/i in 1 to 3)
		var/obj/machinery/conveyor/C = allocate(/obj/machinery/conveyor, locate(origin.x + i, origin.y + 1, origin.z), EAST)
		C.set_id("dq_line")
		belts += C
	var/obj/machinery/conveyor/middle = belts[2]
	middle.broken()
	var/obj/machinery/conveyor/first = belts[1]
	var/obj/machinery/conveyor/last = belts[3]
	TEST_ASSERT(!first.operable, "the belt before the broken one stops")
	TEST_ASSERT(!last.operable, "and the belt after it")
