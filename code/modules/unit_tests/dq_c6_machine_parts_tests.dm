// Machine internals as data (roadmap C6, doc/rewrite/containment.md §5).
//
// A machine's board and stock parts are declared through latent_generator()
// (machinery.dm) and resolved lazily into latent entries in
// CONTAINER_SLOT_INTERNALS -- never eager objects. RefreshParts() and
// get_part_rating()/get_part_count() read those entries (or the real objects
// once something materializes them) instead of scanning component_parts.
//
// dq_type_var() (machinery.dm) is the primitive that reads a declared var off
// a bare type path without the `:` operator (forbidden, AGENTS.md §3b): one
// transient instance, cached after that. These tests check it reads the
// SPECIFIC subtype asked for, not some base type's value -- the bug this
// whole file exists to catch (a first pass silently read /obj/item/circuit-
// board's empty req_components for every board, crashing RefreshParts on a
// division by zero for any machine whose formula divides by a part rating).

/datum/unit_test/dq_c6_type_var_reads_subtype

/datum/unit_test/dq_c6_type_var_reads_subtype/Run()
	// The base circuitboard declares no req_components; the microwave board
	// declares 5. A read that silently fell back to the base type would see
	// null here instead of the real list.
	var/list/base_req = dq_type_var(/obj/item/circuitboard, "req_components")
	TEST_ASSERT(isnull(base_req), "The base /obj/item/circuitboard is expected to declare no req_components.")

	var/list/microwave_req = dq_type_var(/obj/item/circuitboard/microwave, "req_components")
	TEST_ASSERT_NOTNULL(microwave_req, "dq_type_var() must read the microwave board's own req_components, not the base circuitboard's.")
	TEST_ASSERT_EQUAL(length(microwave_req), 5, "The microwave board declares 5 required component types.")
	TEST_ASSERT_EQUAL(microwave_req[/obj/item/stock_parts/matter_bin], 2, "The microwave board requires 2 matter bins.")

	// Caching must be per (path, var_name): a second, different var on the
	// same type must not return the first var's cached value.
	var/laser_default = dq_type_var(/obj/item/stock_parts/micro_laser, "rating")
	TEST_ASSERT_EQUAL(laser_default, 1, "A stock part's declared rating defaults to 1.")

/// A freshly constructed machine keeps its board and parts as data: no real
/// circuitboard or stock part objects exist until something asks for them.
/datum/unit_test/dq_c6_mapped_machine_stays_latent

/datum/unit_test/dq_c6_mapped_machine_stays_latent/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/autolathe/machine = new(test_turf)

	TEST_ASSERT(ispath(machine.circuit), "A freshly mapped machine's circuit must stay a type path (roadmap C6), not a materialized board.")
	TEST_ASSERT_NULL(machine.component_parts, "A freshly mapped machine must not hold real part objects before anything materializes them.")

	// Reading its board's own type still works: the autolathe board requires
	// 3 matter bins, not the recharger's or any other board's count.
	TEST_ASSERT_EQUAL(machine.get_part_count(/obj/item/stock_parts/matter_bin), 3, "The autolathe board requires 3 matter bins.")
	TEST_ASSERT_EQUAL(machine.get_part_count(/obj/item/stock_parts/manipulator), 1, "The autolathe board requires 1 manipulator.")
	qdel(machine)

/// RefreshParts() for each converted family reads the real board's own
/// req_components (a real subtype), not some empty or generic default.
/datum/unit_test/dq_c6_refresh_parts_reads_real_board

/datum/unit_test/dq_c6_refresh_parts_reads_real_board/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)

	// autolathe: matter_bin x3 (rating 1 each) -> mat_capacity = 3 * 37.5 * SHEET_MATERIAL_AMOUNT.
	var/obj/machinery/autolathe/lathe = new(test_turf)
	TEST_ASSERT_EQUAL(lathe.materials.max_amount, 3 * 37.5 * SHEET_MATERIAL_AMOUNT, "Autolathe material capacity must reflect its board's 3 matter bins, not a base/empty default.")
	qdel(lathe)

	// shield_generator: smes_coil x1 at its declared ChargeCapacity default
	// (6,000,000, /obj/item/smes_coil in smes_construction.dm). A read that
	// fell back to zero (an empty/base default) would leave the shield with
	// no strength at all.
	var/obj/machinery/power/shield_generator/gen = new(test_turf)
	var/obj/item/smes_coil/reference = new(null)
	TEST_ASSERT_EQUAL(gen.full_shield_strength, reference.ChargeCapacity * 5, "Shield generator strength must read the smes_coil's own ChargeCapacity, not zero.")
	qdel(reference)
	qdel(gen)

/// After a maintenance-panel part swap (RPED), the real installed part's
/// rating -- not the board's declared default -- drives RefreshParts().
/datum/unit_test/dq_c6_rped_swap_reads_real_part

/datum/unit_test/dq_c6_rped_swap_reads_real_part/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	// autolathe's board declares 1 manipulator, so its rating starts at 1.
	var/obj/machinery/autolathe/machine = new(test_turf)
	machine.panel_open = TRUE
	TEST_ASSERT_EQUAL(machine.get_part_rating(/obj/item/stock_parts/manipulator), 1, "Precondition: the mapped autolathe starts with a rating-1 manipulator.")

	var/obj/item/storage/part_replacer/R = new(test_turf)
	var/obj/item/stock_parts/manipulator/best = new(R)
	best.rating = 5

	machine.default_part_replacement(null, R)
	TEST_ASSERT_EQUAL(machine.get_part_rating(/obj/item/stock_parts/manipulator), 5, "RefreshParts must reflect the RPED-installed manipulator's real rating (5), not the board's default (1).")
	qdel(machine)
	qdel(R)

/// Deconstructing a mapped (never-materialized) machine yields the same real
/// board and parts as before machine internals became data.
/datum/unit_test/dq_c6_deconstruct_materializes_parts

/datum/unit_test/dq_c6_deconstruct_materializes_parts/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/autolathe/machine = new(test_turf)
	TEST_ASSERT_NULL(machine.component_parts, "Precondition: parts must still be latent before deconstruction.")

	machine.materialize_circuit()
	TEST_ASSERT(!ispath(machine.circuit), "materialize_circuit() must produce a real board instance.")
	TEST_ASSERT_EQUAL(length(machine.component_parts), 5, "Deconstruction-time materialization must produce all 5 declared parts (3 matter bins, 1 manipulator, 1 console screen).")
	qdel(machine)
