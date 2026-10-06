// Smoothing pins: the connection state walls, low walls, tables and catwalks show in a fixed layout, before and after a neighbour goes.
// Recorded before smoothing moved onto adjacency() (code/engine/lifeforms/adjacency.dm); the same rows must hold after.
// Rows: code/modules/unit_tests/snapshots/smoothing_pins/<test type>.txt (`--bless dq_smoothing_pins` rewrites them).

/datum/unit_test/dq_smoothing_pins
	var/list/rows

/datum/unit_test/dq_smoothing_pins/proc/at(dx, dy)
	var/turf/origin = run_loc_floor_bottom_left
	return locate(origin.x + dx, origin.y + dy, origin.z)

/datum/unit_test/dq_smoothing_pins/proc/note(stage, atom/A, dx, dy)
	var/text
	if(istype(A, /turf/simulated/wall))
		var/turf/simulated/wall/W = A
		text = jointext(W.get_wall_connections(), ",")
	else
		var/obj/structure/S = A
		text = "[jointext(S.connections || list(), ",")]|[jointext(S.other_connections || list(), ",")]"
	rows += "[stage] [replacetext("[A.type]", "/", ".")] [dx],[dy] => [text]"

/datum/unit_test/dq_smoothing_pins/Run()
	rows = list()
	test_driver_begin()
	var/list/restore = list()
	var/list/wall_at = list(list(1, 1), list(2, 1), list(1, 2))
	for(var/list/xy as anything in wall_at)
		var/turf/T = at(xy[1], xy[2])
		restore[T] = T.type
		T.ChangeTurf(/turf/simulated/wall)
	var/obj/structure/low_wall/LW = allocate(/obj/structure/low_wall, at(3, 1))
	var/obj/structure/low_wall/LW2 = allocate(/obj/structure/low_wall, at(3, 2))
	var/obj/structure/table/T1 = allocate(/obj/structure/table/steel, at(1, 4))
	var/obj/structure/table/T2 = allocate(/obj/structure/table/steel, at(2, 4))
	var/obj/structure/table/T3 = allocate(/obj/structure/table/steel, at(2, 3))
	var/obj/structure/catwalk/C1 = allocate(/obj/structure/catwalk, at(4, 4))
	var/obj/structure/catwalk/C2 = allocate(/obj/structure/catwalk, at(4, 3))
	test_time(1 SECOND)

	for(var/list/xy as anything in wall_at)
		note("placed", at(xy[1], xy[2]), xy[1], xy[2])
	note("placed", LW, 3, 1)
	note("placed", LW2, 3, 2)
	note("placed", T1, 1, 4)
	note("placed", T2, 2, 4)
	note("placed", T3, 2, 3)
	note("placed", C1, 4, 4)
	note("placed", C2, 4, 3)

	qdel(T2)
	qdel(C2)
	var/turf/gone = at(2, 1)
	gone.ChangeTurf(restore[gone])
	test_time(1 SECOND)
	note("removed", at(1, 1), 1, 1)
	note("removed", at(1, 2), 1, 2)
	note("removed", LW, 3, 1)
	note("removed", T1, 1, 4)
	note("removed", T3, 2, 3)
	note("removed", C1, 4, 4)

	for(var/turf/T as anything in restore)
		if(T.type != restore[T])
			T.ChangeTurf(restore[T])

	test_driver_end()
	var/dir = "code/modules/unit_tests/snapshots/smoothing_pins/"
	var/list/bad = list()
	var/list/expected = dq_snapshot_read_dir(dir, bad)
	var/failure = dq_snapshot_compare(dir, "smoothing_pins", list((type) = rows), expected, bad)
	if(failure)
		TEST_FAIL(failure)

/// A broken belt stops the belts of its line on both sides (they are found through the conveyor adjacency kind).
/datum/unit_test/dq_conveyor_line_breaks

/datum/unit_test/dq_conveyor_line_breaks/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/list/belts = list()
	for(var/i in 1 to 3)
		var/obj/machinery/conveyor/C = allocate(/obj/machinery/conveyor, locate(origin.x + i, origin.y + 1, origin.z), EAST)
		C.id = "dq_line"
		belts += C
	var/obj/machinery/conveyor/middle = belts[2]
	middle.broken()
	var/obj/machinery/conveyor/first = belts[1]
	var/obj/machinery/conveyor/last = belts[3]
	TEST_ASSERT(!first.operable, "the belt before the broken one stops")
	TEST_ASSERT(!last.operable, "and the belt after it")
