// T9: a machine the map makes keeps its circuit board as data (stock_circuit) until something needs the item; its wires are a record made on first
// use (wires.dm). These check a mapped machine still has its parts, is hacked as before, and gives up a real board when taken apart or wrecked.

/// Makes `type` the way a map load does (mapload TRUE) on the containment floor.
/proc/dq_board_mapped(type, turf/T)
	SSatoms.map_loader_begin("dq_board_on_first_use")
	var/atom/A = new type(T)
	SSatoms.map_loader_stop("dq_board_on_first_use")
	SSatoms.InitializeAtoms(list(A))
	return A

/datum/unit_test/dq_board_mapped_machine_keeps_board_as_data

/datum/unit_test/dq_board_mapped_machine_keeps_board_as_data/Run()
	var/obj/machinery/microwave/M = dq_board_mapped(/obj/machinery/microwave, dq_containment_floor())
	TEST_ASSERT_NULL(M.circuit, "a mapped microwave has made no board item")
	TEST_ASSERT(M.holds_board(), "but it has a board")
	TEST_ASSERT_EQUAL(M.get_part_count(/obj/item/stock_parts), 6, "it has its board's six default parts, as one built at runtime does")
	var/obj/item/circuitboard/B = M.board()
	TEST_ASSERT(istype(B, /obj/item/circuitboard/microwave), "asked for, the board is made: a microwave board")
	TEST_ASSERT_EQUAL(B.loc, M, "inside the machine")
	TEST_ASSERT_EQUAL(M.board(), B, "and made once")
	var/turf/T = get_turf(M)
	qdel(M)
	for(var/obj/item/stock_parts/P in T) // a deleted machine leaves its parts, built or mapped
		qdel(P)

/datum/unit_test/dq_board_mapped_machine_dismantles_into_board

/datum/unit_test/dq_board_mapped_machine_dismantles_into_board/Run()
	var/obj/machinery/microwave/M = dq_board_mapped(/obj/machinery/microwave, dq_containment_floor())
	var/turf/T = get_turf(M)
	TEST_ASSERT(M.dismantle(), "a mapped microwave dismantles")
	var/obj/structure/frame/F = locate() in T
	TEST_ASSERT_NOTNULL(F, "into a frame")
	TEST_ASSERT(istype(F.circuit, /obj/item/circuitboard/microwave), "holding its microwave board")
	for(var/atom/movable/AM as anything in T.contents)
		if(istype(AM, /obj/structure/frame) || istype(AM, /obj/item/stock_parts) || istype(AM, /obj/item/stack))
			qdel(AM)

/datum/unit_test/dq_board_mapped_machine_wreck_salvages_board

/datum/unit_test/dq_board_mapped_machine_wreck_salvages_board/Run()
	var/obj/machinery/microwave/M = dq_board_mapped(/obj/machinery/microwave, dq_containment_floor())
	var/turf/T = get_turf(M)
	M.deconstruct(TRUE)
	var/obj/item/circuitboard/microwave/B = locate() in T
	TEST_ASSERT_NOTNULL(B, "a wrecked mapped microwave leaves its board on the floor")
	for(var/atom/movable/AM as anything in T.contents)
		if(isitem(AM) || istype(AM, /obj/machinery/microwave))
			qdel(AM)

/datum/unit_test/dq_board_mapped_alarm_is_hacked

/datum/unit_test/dq_board_mapped_alarm_is_hacked/Run()
	var/obj/machinery/alarm/A = dq_board_mapped(/obj/machinery/alarm, dq_containment_floor())
	TEST_ASSERT(A.holds_board(), "a mapped air alarm has its board")
	TEST_ASSERT(!A.aidisabled, "and lets the AI in")
	var/datum/wires_test_adapter/W = wires_test(A)
	W.cut(WIRE_AI_CONTROL)
	TEST_ASSERT(A.aidisabled, "cutting its AI control wire locks the AI out")
	qdel(A)

