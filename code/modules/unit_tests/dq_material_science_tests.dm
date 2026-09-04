/datum/unit_test/dq_material_slots_resolve_defaults

/datum/unit_test/dq_material_slots_resolve_defaults/Run()
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_CELL, SHEET_MATERIAL_AMOUNT * 2)
	var/list/resolved = material_slot_resolve(slots, list(MATERIAL_ROLE_CONDUCTOR = MAT_SILVER))
	TEST_ASSERT_EQUAL(resolved[MATERIAL_ROLE_CONDUCTOR], MAT_SILVER, "An explicit role choice must override its default")
	TEST_ASSERT_EQUAL(resolved[MATERIAL_ROLE_ELECTRODE], MAT_COPPER, "Unchanged roles must retain their sensible defaults")
	TEST_ASSERT_EQUAL(resolved[MATERIAL_ROLE_THERMAL], MAT_COPPER, "The standard cell must include a real thermal buffer")
	TEST_ASSERT(resolved[MATERIAL_ROLE_STRUCTURE], "Every required role must resolve")

/datum/unit_test/dq_material_construction_is_multipart

/datum/unit_test/dq_material_construction_is_multipart/Run()
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_CELL, SHEET_MATERIAL_AMOUNT * 2)
	var/list/choices = list(
		MATERIAL_ROLE_CONDUCTOR = MAT_SILVER,
		MATERIAL_ROLE_ELECTRODE = MAT_GOLD,
		MATERIAL_ROLE_STRUCTURE = MAT_STEEL,
		MATERIAL_ROLE_INSULATION = MAT_GLASS,
	)
	TEST_ASSERT(cell.apply_material_construction(choices, slots, MATERIAL_APPLICATION_CELL), "A normal item must accept role-addressed materials")
	TEST_ASSERT_EQUAL(cell.material_for_role(MATERIAL_ROLE_CONDUCTOR)?.name, MAT_SILVER, "The conductor must remain independently addressable")
	TEST_ASSERT_EQUAL(cell.material_for_role(MATERIAL_ROLE_ELECTRODE)?.name, MAT_GOLD, "The electrodes must not be averaged into the conductor")
	var/before = cell.charge
	cell.use(100)
	TEST_ASSERT_EQUAL(before - cell.charge, 100, "A superconducting construction must never multiply stored energy")
	qdel(cell)

/datum/unit_test/dq_material_design_costs_every_role

/datum/unit_test/dq_material_design_costs_every_role/Run()
	var/datum/design_techweb/design = SSresearch.techweb_design_by_id("basic_cell")
	TEST_ASSERT(istype(design), "The ordinary cell design must receive a multipart blueprint")
	var/list/choices = list(
		MATERIAL_ROLE_CONDUCTOR = MAT_SILVER,
		MATERIAL_ROLE_ELECTRODE = MAT_GOLD,
		MATERIAL_ROLE_STRUCTURE = MAT_STEEL,
		MATERIAL_ROLE_INSULATION = MAT_GLASS,
	)
	var/list/cost = design.effective_materials(choices)
	TEST_ASSERT(cost[get_material_by_name(MAT_SILVER)] > 0, "The selected conductor must be charged")
	TEST_ASSERT(cost[get_material_by_name(MAT_GOLD)] > 0, "The selected electrode must be charged")
	TEST_ASSERT(cost[get_material_by_name(MAT_STEEL)] > 0, "The selected casing must be charged")

/datum/unit_test/dq_material_feedstock_remains_normal_stack

/datum/unit_test/dq_material_feedstock_remains_normal_stack/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/item/stack/material/steel/feedstock = new(test_turf, 2)
	var/datum/material_batch/batch = new
	TEST_ASSERT(material_batch_absorb_sheet(batch, feedstock), "An ordinary material stack must feed alloy processing directly")
	TEST_ASSERT_EQUAL(feedstock.get_amount(), 1, "Processing must consume the actual physical stack")
	var/material_key = register_processed_material(batch)
	TEST_ASSERT(material_key, "A physical feedstock batch must register as a canonical material")
	TEST_ASSERT(get_material_by_name(material_key), "The registered material must be immediately available to physical stacks")
	var/obj/item/stack/material/processed_alloy/direct = new(test_turf, 1)
	TEST_ASSERT(istype(direct, /obj/item/stack/material), "The concrete processed-stock type must initialize as a normal stack")
	qdel(direct)
	var/obj/item/stack/material/processed_alloy/output = processed_spawn_stack(test_turf, batch, 1)
	TEST_ASSERT(istype(output, /obj/item/stack/material), "Processed output must remain a normal material stack (output=[output], turf=[test_turf], key=[material_key])")
	qdel(feedstock)
	qdel(output)
	qdel(batch)

/datum/unit_test/dq_material_blueprint_covers_catalogue

/datum/unit_test/dq_material_blueprint_covers_catalogue/Run()
	var/eligible = 0
	var/covered = 0
	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design_techweb/design = SSresearch.techweb_designs[design_id]
		if(!length(design.standard_material_costs))
			continue
		eligible++
		TEST_ASSERT(length(design.material_slots), "Ordinary design [design.id] ([design.type]) lost its material blueprint")
		var/list/defaults = material_slot_resolve(design.material_slots)
		TEST_ASSERT(defaults, "Ordinary design [design.id] has unresolvable standard materials")
		var/list/effective = design.effective_materials(defaults)
		var/slot_total = 0
		for(var/role in design.material_slots)
			var/list/spec = design.material_slots[role]
			slot_total += spec["amount"]
			var/label = lowertext(spec["label"])
			TEST_ASSERT(!findtext(label, "functional component") && !findtext(label, "recipe component") && !findtext(label, "auxiliary component"), "Configurable design [design.id] exposes placeholder part '[spec["label"]]' instead of a physical blueprint")
		TEST_ASSERT_EQUAL(slot_total, design.original_material_total, "Blueprint [design.id] must conserve its original feedstock quantity")
		for(var/material_id in design.standard_material_costs)
			var/datum/material/material = get_material_by_name(material_id)
			TEST_ASSERT_EQUAL(effective[material], design.standard_material_costs[material_id], "Standard [design.id] must preserve its original [material_id] cost")
		covered++
	TEST_ASSERT(eligible >= 500, "The corpus audit must cover the real catalogue, not a handful of authored examples (found [eligible])")
	TEST_ASSERT_EQUAL(covered, eligible, "Every ordinary material-cost design must have a blueprint")

/datum/unit_test/dq_material_blueprint_has_no_category_gate

/datum/unit_test/dq_material_blueprint_has_no_category_gate/Run()
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_CELL, SHEET_MATERIAL_AMOUNT * 2)
	var/list/unusual = list(
		MATERIAL_ROLE_CONDUCTOR = MAT_CLOTH,
		MATERIAL_ROLE_ELECTRODE = MAT_GLASS,
		MATERIAL_ROLE_STRUCTURE = MAT_WOOD,
		MATERIAL_ROLE_INSULATION = MAT_STEEL,
	)
	TEST_ASSERT(material_slot_resolve(slots, unusual), "Physically poor choices must remain selectable; continuous properties determine their performance")

/datum/unit_test/dq_material_duplicate_catalogue_removed

/datum/unit_test/dq_material_duplicate_catalogue_removed/Run()
	for(var/removed_id in list("material_knife", "material_power_cell", "material_pipe", "material_capacitor"))
		TEST_ASSERT(!SSresearch.techweb_designs[removed_id], "Duplicate special recipe [removed_id] must stay deleted")
	for(var/ordinary_id in list("basic_cell", "crowbar", "scalpel"))
		var/datum/design_techweb/design = SSresearch.techweb_design_by_id(ordinary_id)
		TEST_ASSERT(length(design?.material_slots), "Ordinary recipe [ordinary_id] must provide construction customization")
	var/datum/design_techweb/capacitor = SSresearch.techweb_design_by_id("basic_capacitor")
	TEST_ASSERT(capacitor.material_slots[MATERIAL_ROLE_DIELECTRIC], "A capacitor must expose a dielectric, not a generic machine component")
	var/datum/design_techweb/magazine = SSresearch.techweb_design_by_id("pistol_mag_9mm")
	TEST_ASSERT(magazine.material_slots[MATERIAL_ROLE_FEED] && magazine.material_slots[MATERIAL_ROLE_SPRING], "A magazine must expose its feed mechanism and spring, not projectile parts")
	for(var/simple_id in list("kitchen_knife", "fork", "spoon", "plastic_knife", "plastic_fork", "plastic_spoon", "spring", "gear"))
		var/datum/design_techweb/simple_design = SSresearch.techweb_design_by_id(simple_id)
		TEST_ASSERT_EQUAL(length(simple_design.material_slots), 1, "Simple formed product [simple_id] must have exactly one selectable material")
		TEST_ASSERT(simple_design.material_slots[MATERIAL_ROLE_BODY], "Simple formed product [simple_id] must expose that choice as its material")
	for(var/electronic_id in list("multitool", "atmosanalyzer", "medical_analyzer"))
		var/datum/design_techweb/electronic = SSresearch.techweb_design_by_id(electronic_id)
		TEST_ASSERT_EQUAL(length(electronic.material_slots), 1, "Generic electronic [electronic_id] must expose only its casing")
		TEST_ASSERT(electronic.material_slots[MATERIAL_ROLE_STRUCTURE], "Generic electronic [electronic_id] must label its choice as casing")

/datum/unit_test/dq_material_every_slot_changes_real_physics

/datum/unit_test/dq_material_every_slot_changes_real_physics/Run()
	var/list/applications = list(
		MATERIAL_APPLICATION_TOOL, MATERIAL_APPLICATION_SURGICAL, MATERIAL_APPLICATION_CELL,
		MATERIAL_APPLICATION_ARMOR, MATERIAL_APPLICATION_PRESSURE, MATERIAL_APPLICATION_MACHINE_PART,
		MATERIAL_APPLICATION_PROJECTILE, MATERIAL_APPLICATION_ELECTRONICS, MATERIAL_APPLICATION_FIREARM,
		MATERIAL_APPLICATION_CONTAINER, MATERIAL_APPLICATION_CAPACITOR, MATERIAL_APPLICATION_MANIPULATOR,
		MATERIAL_APPLICATION_MATTER_BIN, MATERIAL_APPLICATION_SCANNER, MATERIAL_APPLICATION_LASER,
		MATERIAL_APPLICATION_MAGAZINE, MATERIAL_APPLICATION_CIRCUIT_BOARD, MATERIAL_APPLICATION_SOFT_GOODS,
		MATERIAL_APPLICATION_MECHANICAL, MATERIAL_APPLICATION_CABLE, MATERIAL_APPLICATION_LIGHT,
		MATERIAL_APPLICATION_ENERGY_DEVICE, MATERIAL_APPLICATION_MONOLITHIC,
	)
	for(var/application in applications)
		var/list/slots = default_material_slots(application, SHEET_MATERIAL_AMOUNT * 4)
		TEST_ASSERT(length(slots), "Application [application] must define physical parts")
		var/list/defaults = material_slot_resolve(slots)
		for(var/role in slots)
			var/list/variant = defaults.Copy()
			variant[role] = defaults[role] == MAT_DIAMOND ? MAT_WOOD : MAT_DIAMOND
			var/obj/item/baseline = new(run_loc_floor_bottom_left)
			var/obj/item/changed = new(run_loc_floor_bottom_left)
			TEST_ASSERT(baseline.apply_material_construction(defaults, slots, application), "Baseline [application]/[role] must construct")
			TEST_ASSERT(changed.apply_material_construction(variant, slots, application), "Variant [application]/[role] must construct")
			var/changed_physics = baseline.max_integrity != changed.max_integrity || baseline.throw_speed != changed.throw_speed || baseline.throw_range != changed.throw_range || baseline.siemens_coefficient != changed.siemens_coefficient || baseline.material_effective_density != changed.material_effective_density
			TEST_ASSERT(changed_physics, "Changing [application]'s [role] must alter a live physical property")
			qdel(baseline)
			qdel(changed)

/datum/unit_test/dq_standard_light_matches_station_baseline

/datum/unit_test/dq_standard_light_matches_station_baseline/Run()
	var/obj/item/light/bulb/bulb = new(run_loc_floor_bottom_left)
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_LIGHT, SHEET_MATERIAL_AMOUNT)
	TEST_ASSERT(bulb.apply_material_construction(null, slots, MATERIAL_APPLICATION_LIGHT), "The standard light blueprint must construct")
	TEST_ASSERT_EQUAL(bulb.brightness_power, bulb.init_brightness_power, "Standard glass/copper bulb brightness must match the authored station baseline")
	TEST_ASSERT_EQUAL(bulb.brightness_range, bulb.init_brightness_range, "Standard glass optics must match the authored station range")
	TEST_ASSERT_EQUAL(bulb.nightshift_power, bulb.init_nightshift_power, "Standard bulb nightshift output must remain calibrated")
	TEST_ASSERT_EQUAL(bulb.nightshift_range, bulb.init_nightshift_range, "Standard bulb nightshift range must remain calibrated")
	qdel(bulb)

/datum/unit_test/dq_material_pipe_installation_preserves_layers

/datum/unit_test/dq_material_pipe_installation_preserves_layers/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_PRESSURE, SHEET_MATERIAL_AMOUNT)
	var/list/choices = list(
		MATERIAL_ROLE_STRUCTURE = MAT_DIAMOND,
		MATERIAL_ROLE_LINER = MAT_GLASS,
		MATERIAL_ROLE_INSULATION = MAT_PLASTIC,
	)
	var/obj/item/pipe/fitting = new(test_turf, /obj/machinery/atmospherics/pipe/simple, NORTH)
	TEST_ASSERT(fitting.apply_material_construction(choices, slots, MATERIAL_APPLICATION_PRESSURE), "A pipe fitting must accept a complete pressure assembly")
	var/obj/machinery/atmospherics/pipe/simple/installed = new(test_turf)
	fitting.build_pipe(installed)
	TEST_ASSERT_EQUAL(installed.material_for_role(MATERIAL_ROLE_STRUCTURE)?.name, MAT_DIAMOND, "Installation must preserve the load-bearing pipe shell")
	TEST_ASSERT_EQUAL(installed.material_for_role(MATERIAL_ROLE_LINER)?.name, MAT_GLASS, "Installation must preserve the gas-contact liner")
	TEST_ASSERT_EQUAL(installed.material_for_role(MATERIAL_ROLE_INSULATION)?.name, MAT_PLASTIC, "Installation must preserve pipe insulation")
	qdel(fitting)
	qdel(installed)

/datum/unit_test/dq_material_canister_rating_is_physical

/datum/unit_test/dq_material_canister_rating_is_physical/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_PRESSURE, 2 * SHEET_MATERIAL_AMOUNT)
	var/obj/machinery/portable_atmospherics/canister/strong = new(test_turf)
	var/obj/machinery/portable_atmospherics/canister/weak = new(test_turf)
	strong.apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = MAT_DIAMOND), slots, MATERIAL_APPLICATION_PRESSURE)
	weak.apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = MAT_WOOD), slots, MATERIAL_APPLICATION_PRESSURE)
	TEST_ASSERT(strong.effective_maximum_pressure() > weak.effective_maximum_pressure(), "Canister shell material must change the actual internal rupture rating")
	TEST_ASSERT_EQUAL(strong.pressure_resistance, weak.pressure_resistance, "Internal vessel strength must not misuse decompression movement resistance")
	qdel(strong)
	qdel(weak)

/datum/unit_test/dq_material_cable_installation_preserves_insulation

/datum/unit_test/dq_material_cable_installation_preserves_insulation/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_CABLE, SHEET_MATERIAL_AMOUNT)
	var/obj/item/stack/cable_coil/coil = new(test_turf, 1)
	coil.apply_material_construction(list(MATERIAL_ROLE_CONDUCTOR = MAT_SILVER, MATERIAL_ROLE_INSULATION = MAT_GLASS), slots, MATERIAL_APPLICATION_CABLE)
	var/obj/structure/cable/cable = new(test_turf)
	cable.copy_material_construction_from(coil)
	TEST_ASSERT_EQUAL(cable.engineered_material()?.name, MAT_SILVER, "Installed cable must retain its selected conductor")
	TEST_ASSERT_EQUAL(cable.insulation_material()?.name, MAT_GLASS, "Installed cable must retain its independently selected insulation")
	qdel(coil)
	qdel(cable)

/datum/unit_test/dq_material_machine_retains_component_makeup

/datum/unit_test/dq_material_machine_retains_component_makeup/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/machine = new(test_turf)
	var/obj/item/stock_parts/capacitor/part = new(machine)
	var/list/slots = default_material_slots(MATERIAL_APPLICATION_CAPACITOR, SHEET_MATERIAL_AMOUNT)
	part.apply_material_construction(list(MATERIAL_ROLE_DIELECTRIC = MAT_DIAMOND), slots, MATERIAL_APPLICATION_CAPACITOR)
	machine.component_parts = list(part)
	TEST_ASSERT(machine.finalize_material_assembly(), "A constructed machine must retain the material makeup of its installed parts")
	TEST_ASSERT(length(machine.material_component_manifest), "Machine material composition must remain inspectable after the frame is consumed")
	TEST_ASSERT(machine.material_emp_resistance > 0, "Installed dielectric parts must affect whole-machine EMP behavior")
	qdel(machine)
