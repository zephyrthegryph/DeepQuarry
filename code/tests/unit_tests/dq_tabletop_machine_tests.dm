// The small bench and lab devices are real machines: each carries a circuit board and comes apart into a frame holding that board, so it can be built and
// dismantled like any other machine (code/domains/world_model/machinery.dm dismantle(); the boards are rows of code/content/variants/circuitboards.dm).

/datum/unit_test/dq_tabletop_machines_dismantle

/datum/unit_test/dq_tabletop_machines_dismantle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/list/paths = list(
		/obj/machinery/chem_hot_plate,
		/obj/machinery/chem_condenser,
		/obj/machinery/bunsen_burner,
		/obj/machinery/scale,
		/obj/machinery/microscope,
		/obj/machinery/libraryscanner,
		/obj/machinery/bookbinder,
		/obj/machinery/gear_painter,
		/obj/machinery/icecream_vat,
		/obj/machinery/radiocarbon_spectrometer,
		/obj/machinery/optable,
		/obj/machinery/processor,
		/obj/machinery/processor/monkey)
	for(var/path in paths)
		var/obj/machinery/M = allocate(path, T)
		var/obj/item/circuitboard/board = M.board()
		TEST_ASSERT_NOTNULL(board, "[path] has no circuit board, so it cannot be dismantled")
		TEST_ASSERT(ispath(path, board.build_path), "[path]'s board builds [board.build_path], not that machine")
		TEST_ASSERT(istype(board.board_type, /datum/frame/frame_types/machine), "[path]'s board does not make a machine frame")
		if(GLOB.fab_trace)
			log_world("FAB: [path] carries [board] with [length(board.req_components)] required part kinds")
		TEST_ASSERT(M.dismantle(), "[path] did not dismantle")
		var/obj/structure/frame/frame = locate_on(T, /obj/structure/frame)
		TEST_ASSERT_NOTNULL(frame, "dismantling [path] left no frame")
		TEST_ASSERT(istype(frame.circuit, /obj/item/circuitboard), "the frame of [path] holds no board")
		TEST_ASSERT(ispath(path, frame.circuit.build_path), "the frame of [path] holds a board for [frame.circuit.build_path]")
		qdel(frame)
		for(var/obj/item/leftover in contents_of(T))
			qdel(leftover)
