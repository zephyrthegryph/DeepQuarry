// A6 declared initialization jobs: preserve real parent/subtype output.
/datum/unit_test/dq_a6_power_init
	abstract_type = /datum/unit_test/dq_a6_power_init

/datum/unit_test/dq_a6_power_init/New()
	..()
	dview(0, test_floor())
	status_policies()
	get_light_type_instance(/obj/item/light/tube)
	get_light_type_instance(/obj/item/light/bulb)

/datum/unit_test/dq_a6_power_init/fuel_inheritance/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/fuel_assembly/ordinary = allocate(/obj/item/fuel_assembly, test_floor(), MAT_PHORON)
	var/datum/material/material = get_material_by_name(MAT_PHORON)
	TEST_ASSERT_NOTNULL(material, "The fixture uses a real phoron material")
	TEST_ASSERT_EQUAL(ordinary.fuel_type, material.use_name, "The actual rod normalizes the selected material name")
	TEST_ASSERT_EQUAL(ordinary.rod_quantities[ordinary.fuel_type], ordinary.initial_amount, "The material job fills the real rod quantity")
	TEST_ASSERT_EQUAL(ordinary.fuel_colour, material.icon_colour, "The selected material colors its rod")
	// A real nullspace constructor exercises the initial radiation pulse without irradiating unrelated fixtures.
	var/obj/item/fuel_assembly/blitz/unshielded/U = new /obj/item/fuel_assembly/blitz/unshielded
	own(U)
	var/obj/item/fuel_assembly/blitz/shielded/S = allocate(/obj/item/fuel_assembly/blitz/shielded, test_floor())
	TEST_ASSERT_EQUAL(U.fuel_type, "blitzu", "The unshielded subtype follows its parent's fuel setup")
	TEST_ASSERT_EQUAL(S.fuel_type, "blitz", "The shielded subtype follows its parent's fuel setup")
	TEST_ASSERT_EQUAL(U.rod_quantities["     "], U.initial_amount, "The original parent placeholder fuel entry is preserved")
	TEST_ASSERT_EQUAL(U.rod_quantities["blitzu"], U.initial_amount, "Unshielded setup adds its actual subtype fuel entry")
	TEST_ASSERT_EQUAL(S.rod_quantities["     "], S.initial_amount, "Shielded setup also preserves the original parent entry")
	TEST_ASSERT_EQUAL(S.rod_quantities["blitz"], S.initial_amount, "Shielded setup adds its actual subtype fuel entry")
	TEST_ASSERT(U.rod_glows && S.rod_glows, "Both real blitz subtypes enable their original glow")
	TEST_ASSERT_EQUAL(U.name, "unshielded blitz rod", "The subtype replaces its parent's temporary material label")
	TEST_ASSERT_EQUAL(S.name, "blitz rod", "The shielded subtype replaces its parent's temporary material label")

/obj/machinery/computer/fusion_core_control/dq_a6
	id_tag = "A6-core"

/obj/machinery/computer/fusion_fuel_control/dq_a6
	id_tag = "A6-fuel"

/obj/machinery/computer/gyrotron_control/dq_a6
	id_tag = "A6-gyro"
	scan_range = 13

/datum/unit_test/dq_a6_power_init/monitor_tags/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/computer/fusion_core_control/C = allocate(/obj/machinery/computer/fusion_core_control/dq_a6, test_floor())
	var/obj/machinery/computer/fusion_fuel_control/F = allocate(/obj/machinery/computer/fusion_fuel_control/dq_a6, test_floor())
	var/obj/machinery/computer/gyrotron_control/G = allocate(/obj/machinery/computer/gyrotron_control/dq_a6, test_floor())
	TEST_ASSERT(C.monitor && F.monitor && G.monitor, "The real declared monitors exist before tag setup")
	TEST_ASSERT_EQUAL(C.monitor.core_tag, "A6-core", "Core monitor receives its holder's actual tag")
	TEST_ASSERT_EQUAL(F.monitor.fuel_tag, "A6-fuel", "Fuel monitor receives its holder's actual tag")
	TEST_ASSERT_EQUAL(G.monitor.gyro_tag, "A6-gyro", "Gyrotron monitor receives its holder's actual tag")
	TEST_ASSERT_EQUAL(G.monitor.scan_range, 13, "Gyrotron monitor receives the configured scan range")

/datum/unit_test/dq_a6_power_init/sensor_history/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/power/sensor/S = allocate(/obj/machinery/power/sensor, test_floor())
	TEST_ASSERT_EQUAL(S.name_tag, "Grid [S.z]-[S.x]-[S.y]", "An unnamed real sensor uses its actual map coordinates")
	TEST_ASSERT(findtext(S.name, S.name_tag), "The prepared sensor display name includes its chosen tag")
	TEST_ASSERT(islist(S.history["supply"]), "Supply history is an actual prepared list")
	TEST_ASSERT(islist(S.history["demand"]), "Demand history is an actual prepared list")
	TEST_ASSERT_EQUAL(length(S.history["supply"]), 0, "Prepared supply history starts empty")
	TEST_ASSERT_EQUAL(length(S.history["demand"]), 0, "Prepared demand history starts empty")

/datum/unit_test/dq_a6_power_init/mapped_rack/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/power/smes/batteryrack/mapped/R = allocate(/obj/machinery/power/smes/batteryrack/mapped, test_floor())
	TEST_ASSERT(length(R.internal_cells), "The actual mapped rack is filled with real cells")
	TEST_ASSERT(length(R.internal_cells) <= R.cell_number, "Mapped filling never exceeds its requested cell count")
	TEST_ASSERT(length(R.internal_cells) <= R.max_cells, "Mapped filling respects the real parts-derived rack capacity")
	for(var/obj/item/cell/C as anything in R.internal_cells)
		TEST_ASSERT_EQUAL(C.loc, R, "Each actual starting cell is inside the rack")
		TEST_ASSERT(!QDELETED(C), "Each actual rack cell stays alive")
	TEST_ASSERT_EQUAL(R.shown_overlays, jointext(R.rack_overlays(), ","), "The final rack look follows the cells inserted by subtype setup")

/datum/unit_test/dq_a6_power_init/field_orientation/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/containment_field/F = allocate(/obj/machinery/containment_field, test_floor(), EAST)
	TEST_ASSERT_EQUAL(F.dir, EAST, "The machinery constructor applies its actual facing before field setup")
	TEST_ASSERT_EQUAL(length(F.shockdirs), 2, "The real field prepares both perpendicular shock directions")
	TEST_ASSERT(turn(EAST, 90) in F.shockdirs, "The first perpendicular shock direction is present")
	TEST_ASSERT(turn(EAST, -90) in F.shockdirs, "The second perpendicular shock direction is present")

/datum/unit_test/dq_a6_power_init/broken_lights/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/light/broken/tube = allocate(/obj/machinery/light/broken, test_floor())
	var/obj/machinery/light/broken/small/bulb = allocate(/obj/machinery/light/broken/small, test_floor())
	TEST_ASSERT_EQUAL(tube.status, LIGHT_BROKEN, "The real mapped broken tube is broken after parent initialization")
	TEST_ASSERT_EQUAL(bulb.status, LIGHT_BROKEN, "The real small broken subtype is broken after both inherited jobs")
	TEST_ASSERT(!tube.on && !bulb.on, "Neither broken fixture produces operational light")

/datum/unit_test/dq_a6_power_init/poi_charge/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/power/smes/buildable/point_of_interest/S = allocate(/obj/machinery/power/smes/buildable/point_of_interest, test_floor())
	TEST_ASSERT(S.capacity > 0, "The real POI SMES has positive parent-prepared capacity")
	TEST_ASSERT_EQUAL(S.stored_charge(), S.capacity, "POI setup fills the actual native storage counter")
	TEST_ASSERT_EQUAL(S.input_level, S.input_level_max, "POI input is set to its parent-prepared maximum")
	TEST_ASSERT_EQUAL(S.output_level, S.output_level_max, "POI output is set to its parent-prepared maximum")
