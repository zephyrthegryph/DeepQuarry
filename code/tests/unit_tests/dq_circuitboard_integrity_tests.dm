// Circuit board integrity: a board builds a real machine, the boards stubbed to bare /obj/machinery while their machines were gone build
// those machines again, and every printable board design is reachable from the techweb.

/// The build_path of a board type or variant row is a real, non-abstract machine (never a bare /obj/machinery or /obj/machinery/computer).
/datum/unit_test/dq_circuitboard_build_paths_are_machines

/datum/unit_test/dq_circuitboard_build_paths_are_machines/Run()
	var/list/bad = list()
	var/checked = 0
	for(var/key in GLOB.dq_variants_circuitboards)
		var/list/row = GLOB.dq_variants_circuitboards[key]
		var/problem = dq_board_build_path_problem(row["build_path"])
		if(problem)
			bad += "row [key]: [problem]"
		checked++
	for(var/obj/item/circuitboard/path as anything in subtypesof(/obj/item/circuitboard))
		var/problem = dq_board_build_path_problem(initial(path.build_path))
		if(problem)
			bad += "[path]: [problem]"
		checked++
	TEST_ASSERT(checked > 160, "the boards were found ([checked])")
	TEST_ASSERT(!length(bad), "boards with a bad build_path:\n[jointext(bad, "\n")]")

/// Why `build_path` is not a buildable machine, or null when it is (or the board builds nothing).
/proc/dq_board_build_path_problem(build_path)
	if(isnull(build_path))
		return null
	if(!ispath(build_path, /obj/machinery))
		return "[build_path] is not a machine"
	if(build_path == /obj/machinery || build_path == /obj/machinery/computer)
		return "[build_path] is a bare base type"
	if(is_abstract(build_path))
		return "[build_path] is abstract"
	return null

/// The six boards stubbed while their machines were deleted finish a frame into their machine.
/datum/unit_test/dq_circuitboard_restored_boards_construct

/datum/unit_test/dq_circuitboard_restored_boards_construct/Run()
	var/list/expected = list(
		"area_atmos" = /obj/machinery/computer/area_atmos,
		"shutoff_monitor" = /obj/machinery/computer/shutoff_monitor,
		"turbine_control" = /obj/machinery/computer/turbine_computer,
		"arf_generator" = /obj/machinery/atmospheric_field_generator,
		"distiller" = /obj/machinery/portable_atmospherics/powered/reagent_distillery,
		"industrial_reagent_reactor" = /obj/machinery/reagent_refinery/reactor,
	)
	var/turf/T = dq_containment_floor()
	for(var/key in expected)
		var/machine_type = expected[key]
		var/computer = ispath(machine_type, /obj/machinery/computer)
		var/obj/structure/frame/F = new (computer ? /obj/structure/frame/computer : /obj/structure/frame)(T)
		var/obj/item/circuitboard/B = variant_new(variant_ref(/obj/item/circuitboard, key), F)
		TEST_ASSERT_EQUAL(B.build_path, machine_type, "[key] builds [machine_type]")
		rel_set(F, nameof(F.circuit), B)
		F.set_anchored(TRUE)
		if(computer)
			F.finish_computer()
		else
			F.finish_machine()
		var/obj/machinery/M = locate(machine_type) in T
		TEST_ASSERT_NOTNULL(M, "a frame holding the [key] board finishes into [machine_type]")
		TEST_ASSERT(QDELETED(F), "and the frame is gone")
		TEST_ASSERT(istype(M.circuit, /obj/item/circuitboard) && variant_is(M.circuit, variant_ref(/obj/item/circuitboard, key)), "the [key] machine holds its board")
		for(var/atom/movable/AM as anything in T.contents)
			if(!ismob(AM))
				qdel(AM)

/// Every design that prints a circuit board is in some techweb node's design_ids.
/datum/unit_test/dq_circuitboard_designs_reachable

/datum/unit_test/dq_circuitboard_designs_reachable/Run()
	var/list/in_nodes = list()
	for(var/node_id in SSresearch.techweb_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_nodes[node_id]
		for(var/design_id in node.design_ids)
			in_nodes[design_id] = TRUE
	var/list/orphans = list()
	var/boards = 0
	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design_techweb/design = SSresearch.techweb_designs[design_id]
		if(design.id == DESIGN_ID_IGNORE || !ispath(design.build_path, /obj/item/circuitboard))
			continue
		boards++
		if(!in_nodes[design.id])
			orphans += "[design.type] ([design.id])"
	TEST_ASSERT(boards > 50, "board designs were found ([boards])")
	TEST_ASSERT(!length(orphans), "board designs in no techweb node:\n[jointext(orphans, "\n")]")
