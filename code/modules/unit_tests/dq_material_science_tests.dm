/datum/unit_test/dq_material_slots_resolve_defaults

/datum/unit_test/dq_material_slots_resolve_defaults/Run()
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_CELL)
	var/list/resolved = slots.resolve(list(MATERIAL_ROLE_CONDUCTOR = MAT_SILVER))
	TEST_ASSERT_EQUAL(resolved[MATERIAL_ROLE_CONDUCTOR], MAT_SILVER, "An explicit role choice must override its default")
	TEST_ASSERT_EQUAL(resolved[MATERIAL_ROLE_ELECTRODE], MAT_COPPER, "Unchanged roles must retain their sensible defaults")
	TEST_ASSERT_EQUAL(resolved[MATERIAL_ROLE_THERMAL], MAT_COPPER, "The standard cell must include a real thermal buffer")
	TEST_ASSERT(resolved[MATERIAL_ROLE_STRUCTURE], "Every required role must resolve")

/datum/unit_test/dq_material_construction_is_multipart

/datum/unit_test/dq_material_construction_is_multipart/Run()
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_CELL)
	var/slots_total = SHEET_MATERIAL_AMOUNT * 2
	var/list/choices = list(
		MATERIAL_ROLE_CONDUCTOR = MAT_SILVER,
		MATERIAL_ROLE_ELECTRODE = MAT_GOLD,
		MATERIAL_ROLE_STRUCTURE = MAT_STEEL,
		MATERIAL_ROLE_INSULATION = MAT_GLASS,
	)
	TEST_ASSERT(cell.apply_material_construction(choices, slots.type, slots_total), "A normal item must accept role-addressed materials")
	TEST_ASSERT_EQUAL(cell.material_for_role(MATERIAL_ROLE_CONDUCTOR)?.name, MAT_SILVER, "The conductor must remain independently addressable")
	TEST_ASSERT_EQUAL(cell.material_for_role(MATERIAL_ROLE_ELECTRODE)?.name, MAT_GOLD, "The electrodes must not be averaged into the conductor")
	var/before = cell.charge
	var/delivered = cell.use(100)
	TEST_ASSERT_EQUAL(delivered, 100, "The requested charge must reach the load")
	TEST_ASSERT(before - cell.charge >= delivered, "Conductor losses must never multiply stored energy")
	TEST_ASSERT(abs((before - cell.charge - delivered) / CELLRATE - cell.material_service.loss_joules) < 0.01, "Undelivered cell energy must be accounted as heat")
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
		TEST_ASSERT(design.material_template, "Ordinary design [design.id] ([design.type]) lost its material blueprint")
		var/datum/material_template/blueprint = material_template_singleton(design.material_template)
		var/list/defaults = blueprint.resolve()
		TEST_ASSERT(defaults, "Ordinary design [design.id] has unresolvable standard materials")
		var/list/effective = design.effective_materials(defaults)
		var/slot_total = 0
		var/list/amounts = blueprint.role_amounts(design.material_total)
		for(var/role in blueprint.roles)
			var/list/spec = blueprint.roles[role]
			slot_total += amounts[role]
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
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_CELL)
	var/list/unusual = list(
		MATERIAL_ROLE_CONDUCTOR = MAT_CLOTH,
		MATERIAL_ROLE_ELECTRODE = MAT_GLASS,
		MATERIAL_ROLE_STRUCTURE = MAT_WOOD,
		MATERIAL_ROLE_INSULATION = MAT_STEEL,
	)
	TEST_ASSERT(slots.resolve(unusual), "Physically poor choices must remain selectable; continuous properties determine their performance")

/datum/unit_test/dq_material_duplicate_catalogue_removed

/datum/unit_test/dq_material_duplicate_catalogue_removed/Run()
	for(var/removed_id in list("material_knife", "material_power_cell", "material_pipe", "material_capacitor"))
		TEST_ASSERT(!SSresearch.techweb_designs[removed_id], "Duplicate special recipe [removed_id] must stay deleted")
	for(var/ordinary_id in list("basic_cell", "crowbar", "scalpel"))
		var/datum/design_techweb/design = SSresearch.techweb_design_by_id(ordinary_id)
		TEST_ASSERT(design?.material_template, "Ordinary recipe [ordinary_id] must provide construction customization")
	var/datum/design_techweb/capacitor = SSresearch.techweb_design_by_id("basic_capacitor")
	TEST_ASSERT(material_template_singleton(capacitor.material_template).roles[MATERIAL_ROLE_DIELECTRIC], "A capacitor must expose a dielectric, not a generic machine component")
	var/datum/design_techweb/magazine = SSresearch.techweb_design_by_id("pistol_mag_9mm")
	TEST_ASSERT(material_template_singleton(magazine.material_template).roles[MATERIAL_ROLE_FEED] && material_template_singleton(magazine.material_template).roles[MATERIAL_ROLE_SPRING], "A magazine must expose its feed mechanism and spring, not projectile parts")
	for(var/simple_id in list("kitchen_knife", "fork", "spoon", "plastic_knife", "plastic_fork", "plastic_spoon", "spring", "gear"))
		var/datum/design_techweb/simple_design = SSresearch.techweb_design_by_id(simple_id)
		TEST_ASSERT_EQUAL(length(material_template_singleton(simple_design.material_template).roles), 1, "Simple formed product [simple_id] must have exactly one selectable material")
		TEST_ASSERT(material_template_singleton(simple_design.material_template).roles[MATERIAL_ROLE_BODY], "Simple formed product [simple_id] must expose that choice as its material")
	for(var/electronic_id in list("multitool", "atmosanalyzer", "medical_analyzer"))
		var/datum/design_techweb/electronic = SSresearch.techweb_design_by_id(electronic_id)
		TEST_ASSERT_EQUAL(length(material_template_singleton(electronic.material_template).roles), 1, "Generic electronic [electronic_id] must expose only its casing")
		TEST_ASSERT(material_template_singleton(electronic.material_template).roles[MATERIAL_ROLE_STRUCTURE], "Generic electronic [electronic_id] must label its choice as casing")

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
		var/datum/material_template/slots = material_template_for_application(application)
		var/slots_total = SHEET_MATERIAL_AMOUNT * 4
		TEST_ASSERT(length(slots.roles), "Application [application] must define physical parts")
		var/list/defaults = slots.resolve()
		for(var/role in slots.roles)
			var/list/variant = defaults.Copy()
			variant[role] = defaults[role] == MAT_DIAMOND ? MAT_WOOD : MAT_DIAMOND
			var/obj/item/baseline = new(run_loc_floor_bottom_left)
			var/obj/item/changed = new(run_loc_floor_bottom_left)
			TEST_ASSERT(baseline.apply_material_construction(defaults, slots.type, slots_total), "Baseline [application]/[role] must construct")
			TEST_ASSERT(changed.apply_material_construction(variant, slots.type, slots_total), "Variant [application]/[role] must construct")
			var/changed_physics = baseline.max_integrity != changed.max_integrity || baseline.throw_speed != changed.throw_speed || baseline.throw_range != changed.throw_range || baseline.siemens_coefficient != changed.siemens_coefficient || baseline.material_effective_density != changed.material_effective_density
			TEST_ASSERT(changed_physics, "Changing [application]'s [role] must alter a live physical property")
			qdel(baseline)
			qdel(changed)

/datum/unit_test/dq_standard_light_matches_station_baseline

/datum/unit_test/dq_standard_light_matches_station_baseline/Run()
	var/obj/item/light/bulb/bulb = new(run_loc_floor_bottom_left)
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_LIGHT)
	var/slots_total = SHEET_MATERIAL_AMOUNT
	TEST_ASSERT(bulb.apply_material_construction(null, slots.type, slots_total), "The standard light blueprint must construct")
	TEST_ASSERT_EQUAL(bulb.brightness_power, bulb.init_brightness_power, "Standard glass/copper bulb brightness must match the authored station baseline")
	TEST_ASSERT_EQUAL(bulb.brightness_range, bulb.init_brightness_range, "Standard glass optics must match the authored station range")
	TEST_ASSERT_EQUAL(bulb.nightshift_power, bulb.init_nightshift_power, "Standard bulb nightshift output must remain calibrated")
	TEST_ASSERT_EQUAL(bulb.nightshift_range, bulb.init_nightshift_range, "Standard bulb nightshift range must remain calibrated")
	qdel(bulb)

/datum/unit_test/dq_material_pipe_installation_preserves_layers

/datum/unit_test/dq_material_pipe_installation_preserves_layers/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_PRESSURE)
	var/slots_total = SHEET_MATERIAL_AMOUNT
	var/list/choices = list(
		MATERIAL_ROLE_STRUCTURE = MAT_DIAMOND,
		MATERIAL_ROLE_LINER = MAT_GLASS,
		MATERIAL_ROLE_INSULATION = MAT_PLASTIC,
	)
	var/obj/item/pipe/fitting = new(test_turf, /obj/machinery/atmospherics/pipe/simple, NORTH)
	TEST_ASSERT(fitting.apply_material_construction(choices, slots.type, slots_total), "A pipe fitting must accept a complete pressure assembly")
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
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_PRESSURE)
	var/slots_total = 2 * SHEET_MATERIAL_AMOUNT
	var/obj/machinery/portable_atmospherics/canister/strong = new(test_turf)
	var/obj/machinery/portable_atmospherics/canister/weak = new(test_turf)
	strong.apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = MAT_DIAMOND), slots.type, slots_total)
	weak.apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = MAT_WOOD), slots.type, slots_total)
	TEST_ASSERT(strong.effective_maximum_pressure() > weak.effective_maximum_pressure(), "Canister shell material must change the actual internal rupture rating")
	TEST_ASSERT_EQUAL(strong.pressure_resistance, weak.pressure_resistance, "Internal vessel strength must not misuse decompression movement resistance")
	qdel(strong)
	qdel(weak)

/datum/unit_test/dq_material_cable_installation_preserves_insulation

/datum/unit_test/dq_material_cable_installation_preserves_insulation/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_CABLE)
	var/slots_total = SHEET_MATERIAL_AMOUNT
	var/obj/item/stack/cable_coil/coil = new(test_turf, 1)
	coil.apply_material_construction(list(MATERIAL_ROLE_CONDUCTOR = MAT_SILVER, MATERIAL_ROLE_INSULATION = MAT_GLASS), slots.type, slots_total)
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
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_CAPACITOR)
	var/slots_total = SHEET_MATERIAL_AMOUNT
	part.apply_material_construction(list(MATERIAL_ROLE_DIELECTRIC = MAT_DIAMOND), slots.type, slots_total)
	machine.component_parts = list(part)
	TEST_ASSERT(machine.finalize_material_assembly(), "A constructed machine must retain the material makeup of its installed parts")
	TEST_ASSERT(length(machine.material_component_manifest), "Machine material composition must remain inspectable after the frame is consumed")
	TEST_ASSERT(machine.material_emp_resistance > 0, "Installed dielectric parts must affect whole-machine EMP behavior")
	qdel(machine)

/datum/unit_test/dq_material_environment_conserves_heat

/datum/unit_test/dq_material_environment_conserves_heat/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/portable_atmospherics/canister/vessel = new(test_turf)
	var/datum/gas_mixture/outside = new(2500)
	vessel.air_contents.set_temperature(600)
	vessel.air_contents.adjust_moles(/datum/gas/oxygen, 100)
	outside.set_temperature(300)
	outside.adjust_moles(/datum/gas/oxygen, 100)
	var/energy_before = vessel.air_contents.thermal_energy() + outside.thermal_energy()
	TEST_ASSERT(vessel.process_material_environment(vessel.air_contents, outside, 1, vessel.maximum_pressure, MATERIAL_CANISTER_REFERENCE_RADIUS, MATERIAL_CANISTER_REFERENCE_THICKNESS), "A temperature differential must keep the environmental model active")
	var/energy_after = vessel.air_contents.thermal_energy() + outside.thermal_energy()
	TEST_ASSERT(abs(energy_after - energy_before) < max(1, energy_before * 0.0001), "Material heat transfer must conserve energy")
	TEST_ASSERT(vessel.air_contents.return_temperature() < 600 && outside.return_temperature() > 300, "Heat must move through the vessel wall in the physical direction")
	qdel(outside)
	qdel(vessel)

/datum/unit_test/dq_material_environment_distinguishes_surfaces

/datum/unit_test/dq_material_environment_distinguishes_surfaces/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/portable_atmospherics/canister/vessel = new(test_turf)
	var/datum/material_template/slots = material_template_for_application(MATERIAL_APPLICATION_PRESSURE)
	var/slots_total = 2 * SHEET_MATERIAL_AMOUNT
	vessel.apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = MAT_GLASS, MATERIAL_ROLE_LINER = MAT_WOOD, MATERIAL_ROLE_INSULATION = MAT_PLASTIC), slots.type, slots_total)
	var/datum/gas_mixture/clean_outside = new(2500)
	clean_outside.adjust_moles(/datum/gas/nitrogen, 100)
	vessel.air_contents.adjust_moles(/datum/gas/plasma, 100)
	vessel.process_material_environment(vessel.air_contents, clean_outside, 5, vessel.maximum_pressure, MATERIAL_CANISTER_REFERENCE_RADIUS, MATERIAL_CANISTER_REFERENCE_THICKNESS, FALSE)
	TEST_ASSERT(vessel.material_environment_liner_integrity < 100, "Corrosive contents must attack the wetted liner")
	TEST_ASSERT_EQUAL(vessel.material_environment_exterior_integrity, 100, "Clean ambient air must not attack an inert exterior")
	qdel(clean_outside)
	qdel(vessel)

/datum/unit_test/dq_material_environment_covers_infrastructure

/datum/unit_test/dq_material_environment_covers_infrastructure/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/list/objects = list(
		new /obj/machinery/atmospherics/pipe/simple(test_turf),
		new /obj/machinery/atmospherics/binary/pump(test_turf),
		new /obj/machinery/portable_atmospherics/powered/pump(test_turf),
		new /obj/machinery/portable_atmospherics/canister(test_turf),
		new /obj/item/tank/oxygen(test_turf),
		new /obj/structure/cable(test_turf),
		new /obj/machinery(test_turf),
	)
	for(var/obj/infrastructure as anything in objects)
		TEST_ASSERT(infrastructure.material_for_role(MATERIAL_ROLE_STRUCTURE) || infrastructure.material_for_role(MATERIAL_ROLE_CONDUCTOR), "[infrastructure.type] must initialize with a physical material assembly")
		if(infrastructure.type == /obj/machinery)
			TEST_ASSERT(!infrastructure.material_service, "Ordinary legacy machinery must not enter continuous material exposure merely because it has default parts")
		qdel(infrastructure)

/datum/unit_test/dq_material_hot_steel_loses_pressure_capacity

/datum/unit_test/dq_material_hot_steel_loses_pressure_capacity/Run()
	var/obj/machinery/portable_atmospherics/canister/vessel = new(run_loc_floor_bottom_left)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/cold = vessel.material_environment_pressure_limit(1000, 100, 4, T20C)
	var/hot = vessel.material_environment_pressure_limit(1000, 100, 4, (T20C + steel.melting_point) / 2)
	TEST_ASSERT(abs(cold - 1000) < 0.01, "Factory steel must retain its reference rating")
	TEST_ASSERT(hot < cold * 0.75, "Hot steel must weaken against a fixed cold reference")
	qdel(vessel)

/datum/unit_test/dq_material_pressure_has_safe_endurance_band

/datum/unit_test/dq_material_pressure_has_safe_endurance_band/Run()
	var/obj/vessel = new(run_loc_floor_bottom_left)
	var/datum/gas_mixture/internal = new(CELL_VOLUME)
	var/datum/gas_mixture/external = new(CELL_VOLUME)
	internal.set_temperature(T20C)
	external.set_temperature(T20C)
	internal.adjust_moles(/datum/gas/nitrogen, 850 * CELL_VOLUME / (R_IDEAL_GAS_EQUATION * T20C))
	vessel.process_material_environment(internal, external, 120, 1000, MATERIAL_PIPE_REFERENCE_RADIUS, MATERIAL_PIPE_REFERENCE_THICKNESS)
	TEST_ASSERT_EQUAL(vessel.material_environment_fatigue, 0, "Pressure inside the continuous operating envelope accumulated permanent fatigue")
	internal.adjust_moles(/datum/gas/nitrogen, 100 * CELL_VOLUME / (R_IDEAL_GAS_EQUATION * T20C))
	vessel.process_material_environment(internal, external, 60, 1000, MATERIAL_PIPE_REFERENCE_RADIUS, MATERIAL_PIPE_REFERENCE_THICKNESS)
	TEST_ASSERT(vessel.material_environment_fatigue > 0, "Sustained pressure above the fatigue threshold produced no wear")
	var/fatigue_before_recovery = vessel.material_environment_fatigue
	internal.remove_ratio(0.5)
	vessel.process_material_environment(internal, external, 10, 1000, MATERIAL_PIPE_REFERENCE_RADIUS, MATERIAL_PIPE_REFERENCE_THICKNESS)
	TEST_ASSERT(vessel.material_environment_fatigue < fatigue_before_recovery, "Returning below the recovery threshold did not relieve recent pressure fatigue")
	qdel(internal)
	qdel(external)
	qdel(vessel)

/datum/unit_test/dq_material_cell_delivery_and_rebuild

/datum/unit_test/dq_material_cell_delivery_and_rebuild/Run()
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	cell.material_discharge_limit = 10
	cell.material_discharge_credit = 10
	cell.material_discharge_updated = world.time
	var/before = cell.charge
	TEST_ASSERT(!cell.checked_use(20), "An action requiring more than the conductor can deliver must fail")
	TEST_ASSERT_EQUAL(cell.charge, before, "Failed all-or-nothing requests must consume no charge")
	TEST_ASSERT(cell.checked_use(5), "An affordable draw must succeed")
	TEST_ASSERT(!cell.checked_use(6), "Repeated same-tick requests must share one throughput budget")
	TEST_ASSERT(cell.checked_use(0.01), "Affordable fractional draws must not report failure after rounding the stored charge")
	before = cell.charge
	cell.apply_material_construction(null, material_template_path_for_application(MATERIAL_APPLICATION_CELL), 2000)
	TEST_ASSERT(cell.charge <= before, "Reapplying construction must not recharge the cell")
	qdel(cell)
	var/obj/item/cell/infinite/infinite_cell = new
	before = infinite_cell.charge
	TEST_ASSERT(infinite_cell.checked_use(100), "Infinite cells must preserve their explicit unlimited-power behavior under the delivered-amount API")
	TEST_ASSERT_EQUAL(infinite_cell.charge, before, "Infinite cells must not consume stored charge")
	qdel(infinite_cell)

/datum/unit_test/dq_material_reagent_exposure_uses_duration

/datum/unit_test/dq_material_reagent_exposure_uses_duration/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/item/reagent_containers/glass/beaker/vessel = new(test_turf)
	vessel.apply_material_construction(list(MATERIAL_ROLE_LINER = MAT_WOOD), material_template_path_for_application(MATERIAL_APPLICATION_CONTAINER), 2000)
	vessel.reagents.add_reagent(REAGENT_ID_SACID, 10)
	var/datum/material_service/service = vessel.material_service
	service.contents_changed()
	var/before = vessel.material_environment_liner_integrity
	service.contents_changed()
	service.contents_changed()
	TEST_ASSERT_EQUAL(vessel.material_environment_liner_integrity, before, "Repeated observations must not advance corrosion")
	service.chemical_last_update = world.time - 10 SECONDS
	service.settle_chemical()
	TEST_ASSERT(vessel.material_environment_liner_integrity < before, "Unchanged acid must corrode over elapsed time")
	var/cold_rate = service.chemical_rate
	service.add_heat(service.thermal_mass() * 300)
	vg_heat_debug_run_frames(1) // heat is a command to the owner's heat body, applied by the frame
	service.contents_changed()
	TEST_ASSERT(service.chemical_rate > cold_rate * 1.9, "Heating unchanged chemicals must raise the corrosion rate ([cold_rate] -> [service.chemical_rate])")
	service.chemical_last_update = world.time - 1 HOUR
	service.contents_changed()
	TEST_ASSERT(QDELETED(vessel), "A completely consumed liner must rupture the real vessel without continuing to access its deleted service owner")
	qdel(vessel)
	vessel = new
	vessel.reagents.add_reagent(REAGENT_ID_SACID, 10)
	vessel.material_environment_rupture()
	TEST_ASSERT(QDELETED(vessel), "A vessel without a turf must still rupture safely without spilling onto a null target")

/datum/unit_test/dq_material_power_graph_branches_and_loops

/datum/unit_test/dq_material_power_graph_branches_and_loops/Run()
	var/datum/material_power_graph/graph = new
	graph.vertices = list(null, null, null)
	graph.edges = list(list(1, 2, 1, null, 0), list(1, 3, 1, null, 0))
	graph.solve(list(10, -1, -9))
	var/list/small = graph.edges[1]
	var/list/large = graph.edges[2]
	TEST_ASSERT(abs(small[MATERIAL_POWER_EDGE_CURRENT] - 1) < 0.001, "Small branch must only carry its own one amp load")
	TEST_ASSERT(abs(large[MATERIAL_POWER_EDGE_CURRENT] - 9) < 0.001, "Large branch must carry its own nine amp load")
	graph.vertices = list(null, null, null, null)
	graph.edges = list(list(1, 2, 1, null, 0), list(2, 4, 1, null, 0), list(1, 3, 1, null, 0), list(3, 4, 1, null, 0))
	graph.solve(list(10, 0, 0, -10))
	for(var/list/edge as anything in graph.edges)
		TEST_ASSERT(abs(edge[MATERIAL_POWER_EDGE_CURRENT] - 5) < 0.001, "Equal parallel paths must divide current equally")
	TEST_ASSERT(abs(graph.loss_watts - 100) < 0.01, "Four one-ohm branches carrying five amps lose 100 W total")
	TEST_ASSERT(graph.residual < 0.001, "The solved graph must satisfy junction current balance")
	graph.solve(list(10, 0, 0, -10))
	TEST_ASSERT_EQUAL(graph.iterations, 0, "An unchanged graph must reuse its converged solution without another iteration")
	graph.solve(list(12, 0, 0, -12))
	for(var/list/edge as anything in graph.edges)
		TEST_ASSERT(abs(edge[MATERIAL_POWER_EDGE_CURRENT] - 6) < 0.001, "A warm-started solve must respond to changed load without retaining old current")
	qdel(graph)

/datum/unit_test/dq_material_thermal_buffer_conserves_energy

/datum/unit_test/dq_material_thermal_buffer_conserves_energy/Run()
	// In nullspace the heat body has no coupling, so only the added heat moves it.
	var/obj/item/cell/cell = new
	var/datum/material_service/service = cell.material_service
	TEST_ASSERT_NOTNULL(service.ensure_body(), "A material assembly must keep its thermal state in a heat body")
	vg_heat_debug_run_frames(1)
	var/before = service.current_temperature()
	service.add_heat(12000)
	vg_heat_debug_run_frames(1)
	var/after = service.current_temperature()
	TEST_ASSERT(abs((after - before) * service.thermal_mass() - 12000) < 1, "Heating must add exactly the supplied energy ([before] -> [after] K)")
	service.add_heat(-12000)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(abs(service.current_temperature() - before) < 0.01, "Cooling must remove exactly the supplied energy")
	qdel(cell)

/datum/unit_test/dq_material_pump_parts_change_operation

/datum/unit_test/dq_material_pump_parts_change_operation/Run()
	var/obj/machinery/atmospherics/binary/pump/pump = new(run_loc_floor_bottom_left)
	var/baseline = pump.material_pump_power(7500)
	pump.set_construction_material(MATERIAL_ROLE_CONDUCTOR, MAT_WOOD)
	TEST_ASSERT(pump.material_pump_power(7500) < baseline, "Insulating motor windings must reduce actual pump capacity")
	pump.set_construction_material(MATERIAL_ROLE_CONDUCTOR, MAT_COPPER)
	var/efficiency = pump.material_pump_efficiency()
	pump.set_construction_material(MATERIAL_ROLE_BEARINGS, MAT_WOOD)
	TEST_ASSERT(pump.material_pump_efficiency() != efficiency, "Bearing material must affect actual pumping efficiency")
	qdel(pump)

/datum/material/engineering_test_conductor
	name = "engineering test conductor"
	supply_conversion_value = 0
	critical_temperature = 260
	critical_current_density = 25
	electrical_resistivity = 1
	conductivity = 90
	thermoelectric_coefficient = 0.2

/datum/material/engineering_test_buffer
	name = "engineering test buffer"
	supply_conversion_value = 0
	phase_change_temperature = 250
	phase_change_capacity = 50000
	specific_heat = 500

/datum/unit_test/dq_material_cold_assembly_operates

/datum/unit_test/dq_material_cold_assembly_operates/Run()
	var/obj/item/cell/cell = new
	var/datum/material/conductor_type = /datum/material/engineering_test_conductor
	var/datum/material/buffer_type = /datum/material/engineering_test_buffer
	cell.apply_material_construction(list(MATERIAL_ROLE_CONDUCTOR = initial(conductor_type.name), MATERIAL_ROLE_THERMAL = initial(buffer_type.name)), material_template_path_for_application(MATERIAL_APPLICATION_CELL), 2000)
	var/datum/material_service/service = cell.material_service
	service.ensure_body()
	vg_heat_debug_run_frames(1)
	var/mass = service.thermal_mass()
	var/latent = initial(buffer_type.phase_change_capacity)
	// Room-temperature cryogenic stock arrives with its plateau full: cooling to 240 K must
	// also remove the latent heat.
	service.add_heat(-(service.current_temperature() - 250) * mass - latent / 2)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(abs(service.current_temperature() - 250) < 0.01, "Removing half the latent heat must hold the phase temperature ([service.current_temperature()] K)")
	service.add_heat(-latent / 2 - 10 * mass)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(abs(service.current_temperature() - 240) < 0.01, "Actual removed heat must cool through the plateau ([service.current_temperature()] K)")
	var/cold = cell.construction_electrical_resistance(1, 1, service.current_temperature(), 5)
	var/quenched = cell.construction_electrical_resistance(1, 1, service.current_temperature(), 50)
	TEST_ASSERT(quenched > cold * 100, "Exceeding critical current must quench the conductor even while cold")
	service.add_heat(10 * mass + latent / 2)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(abs(service.current_temperature() - 250) < 0.01, "The finite buffer must hold temperature while absorbing real operating heat")
	TEST_ASSERT(cell.construction_electrical_resistance(1, 1, service.current_temperature(), 5) <= cold, "A suitable phase plateau must preserve superconducting operation")
	service.add_heat(latent / 2 + 20 * mass)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(service.current_temperature() > 260 && cell.construction_electrical_resistance(1, 1, service.current_temperature(), 5) > cold * 100, "Exhausted cooling must expose the thermal limit")
	qdel(cell)

/datum/unit_test/dq_superconducting_cell_automatic_envelope

/datum/unit_test/dq_superconducting_cell_automatic_envelope/Run()
	var/obj/item/cell/cell = new
	var/datum/material/conductor_type = /datum/material/engineering_test_conductor
	var/datum/material/buffer_type = /datum/material/engineering_test_buffer
	cell.apply_material_construction(list(MATERIAL_ROLE_CONDUCTOR = initial(conductor_type.name), MATERIAL_ROLE_THERMAL = initial(buffer_type.name)), material_template_path_for_application(MATERIAL_APPLICATION_CELL), 2000)
	var/datum/material_service/service = cell.material_service
	service.ensure_body()
	vg_heat_debug_run_frames(1)
	var/mass = service.thermal_mass()
	var/latent = initial(buffer_type.phase_change_capacity)
	service.add_heat(-(service.current_temperature() - 240) * mass - latent)
	vg_heat_debug_run_frames(1)
	var/envelope = cell.material_output_envelope(10)
	TEST_ASSERT(envelope > 1, "A physically cold superconductor must automatically expose enhanced output")
	var/charge_before = cell.charge
	TEST_ASSERT(cell.checked_use(10 * envelope), "The enhanced envelope must still debit real stored energy")
	cell.material_record_enhanced_output(10, envelope)
	TEST_ASSERT(cell.charge < charge_before - 10, "Enhanced output must cost more energy than an ordinary action")
	vg_heat_debug_run_frames(1)
	service.add_heat((initial(conductor_type.critical_temperature) + 1 - service.current_temperature()) * mass + latent)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT_EQUAL(cell.material_output_envelope(10), 1, "A hot or quenched conductor must fall back to ordinary device output")
	qdel(cell)

/datum/unit_test/dq_material_service_sleep_move_delete

/datum/unit_test/dq_material_service_sleep_move_delete/Run()
	var/turf/start = run_loc_floor_bottom_left
	if(!start)
		for(var/turf/open/candidate in world)
			if(candidate.return_air())
				start = candidate
				break
	var/turf/destination = get_step(start, EAST) || get_step(start, WEST)
	TEST_ASSERT(start && destination && start != destination, "Movement coverage requires two real map turfs")
	var/obj/item/cell/cell = new(start)
	var/datum/material_service/service = cell.material_service
	service.rebind()
	TEST_ASSERT(length(service.mixture_ids), "The test must actually subscribe to a real atmosphere")
	for(var/subscribed_id in service.mixture_ids)
		TEST_ASSERT(REF(service) in SSmachines.material_gas_subscribers["[subscribed_id]"], "Material subscriptions must use the coalesced mixture registry")
	TEST_ASSERT(length(service.movement_sources), "A stationary assembly must watch movement while sleeping")
	service.timer = REACT_REARM(service, service.timer, null)
	service.active = FALSE
	service.last_update = world.time - 10 MINUTES
	service.environment_changed()
	TEST_ASSERT_EQUAL(service.last_update, world.time, "A newly changed environment must not be charged for the preceding sleep interval")
	TEST_ASSERT(!isnull(service.timer), "An environment change must schedule the assembly")
	var/token = service.timer
	for(var/i in 1 to 1000)
		service.environment_changed(FALSE)
	TEST_ASSERT_EQUAL(service.timer, token, "Repeated gas publications must coalesce into one REACT_AT, not allocate timers")
	cell.forceMove(destination)
	service.rebind()
	var/list/ids = service.mixture_ids.Copy()
	var/reference = REF(service)
	qdel(cell)
	TEST_ASSERT(QDELETED(service), "Deleting the assembly must delete its operating state")
	TEST_ASSERT(!service.reactor_id, "Deleting an assembly must drop its scheduled advance (REACT_CLEAR)")
	for(var/id in ids)
		var/list/subscribers = SSmachines.gas_mixture_subscribers["[id]"]
		TEST_ASSERT(!(reference in subscribers), "Deleted assemblies must release mixture subscriptions")
		var/list/material_subscribers = SSmachines.material_gas_subscribers["[id]"]
		TEST_ASSERT(!(reference in material_subscribers), "Deleted assemblies must release coalesced material subscriptions")

/datum/unit_test/dq_material_gas_publication_filtering

/datum/unit_test/dq_material_gas_publication_filtering/Run()
	var/obj/machinery/machine = new(run_loc_floor_bottom_left)
	TEST_ASSERT(!machine.material_service, "An idle ordinary machine must not allocate material exposure state")
	var/datum/material_service/service = machine.enable_material_service()
	TEST_ASSERT(service, "Explicit diagnostic monitoring must expose material service state")
	TEST_ASSERT(!(service.gas_dependency_interest_mask() & GAS_DEPENDENCY_PRESSURE), "An ordinary housing must not subscribe to irrelevant turf pressure churn")
	var/mixture_id = 12345
	service.mixture_pressures = list("[mixture_id]" = ONE_ATMOSPHERE)
	service.mixture_corrosion = list("[mixture_id]" = 0)
	var/list/pressure_jitter = list(mixture_id, GAS_DEPENDENCY_PRESSURE, 2, ONE_ATMOSPHERE + 5, T20C, CELL_VOLUME, 22, 82, 0, 0, 0, 0, 0, 0, 104)
	TEST_ASSERT(!service.gas_dependency_changed(mixture_id, GAS_DEPENDENCY_PRESSURE, pressure_jitter, 1), "Harmless pressure-only publication must not wake an ordinary machine")
	var/list/clean_composition = list(mixture_id, GAS_DEPENDENCY_COMPOSITION, 3, ONE_ATMOSPHERE, T20C, CELL_VOLUME, 21, 83, 0, 0, 0, 0, 0, 0, 104)
	TEST_ASSERT(!service.gas_dependency_changed(mixture_id, GAS_DEPENDENCY_COMPOSITION, clean_composition, 1), "Non-corrosive room-air mixing must not wake an ordinary machine")
	var/list/plasma_exposure = list(mixture_id, GAS_DEPENDENCY_COMPOSITION, 4, ONE_ATMOSPHERE, T20C, CELL_VOLUME, 20, 82, 2, 0, 0, 0, 0, 0, 104)
	TEST_ASSERT(service.gas_dependency_changed(mixture_id, GAS_DEPENDENCY_COMPOSITION, plasma_exposure, 1), "A newly corrosive atmosphere must wake the material service")
	qdel(machine)

	var/obj/machinery/portable_atmospherics/canister/canister = new(run_loc_floor_bottom_left)
	service = canister.enable_material_service()
	TEST_ASSERT(service.gas_dependency_interest_mask() & GAS_DEPENDENCY_PRESSURE, "Pressure vessels must retain pressure-change subscriptions")
	service.mixture_pressures = list("1" = 0, "2" = 0)
	var/list/dangerous_pressure = list(1, GAS_DEPENDENCY_PRESSURE, 5, 100 * ONE_ATMOSPHERE, T20C, 1000, 0, 0, 0, 0, 0, 0, 0, 0, 100)
	TEST_ASSERT(service.gas_dependency_changed(1, GAS_DEPENDENCY_PRESSURE, dangerous_pressure, 1), "A pressure vessel must wake when differential load approaches its material limit")
	qdel(canister)

/datum/unit_test/dq_material_service_schedule_moves_earlier

/// SSmaterial_services' heap is gone: each assembly keeps one REACT_AT, moved only earlier.
/datum/unit_test/dq_material_service_schedule_moves_earlier/Run()
	var/obj/item/cell/a = new(run_loc_floor_bottom_left)
	var/datum/material_service/service = a.material_service
	service.timer = REACT_REARM(service, service.timer, null)
	service.schedule(10 SECONDS)
	var/token = service.timer
	TEST_ASSERT(!isnull(token), "Scheduling must set a timer")
	service.schedule(20 SECONDS)
	TEST_ASSERT_EQUAL(service.timer, token, "A later request must not move the timer")
	service.schedule(1 SECOND)
	TEST_ASSERT(service.timer != token, "An earlier request must move the timer")
	TEST_ASSERT_EQUAL(service.next_update, world.time + 1 SECOND, "An accelerated event must update the deadline")
	qdel(a)

/datum/unit_test/dq_material_corrosion_interval_invariance

/datum/unit_test/dq_material_corrosion_interval_invariance/Run()
	var/obj/machinery/portable_atmospherics/canister/a = new(run_loc_floor_bottom_left)
	var/obj/machinery/portable_atmospherics/canister/b = new(run_loc_floor_bottom_left)
	a.air_contents.adjust_moles(/datum/gas/plasma, 100)
	b.air_contents.copy_from(a.air_contents)
	a.set_construction_material(MATERIAL_ROLE_LINER, MAT_WOOD)
	b.set_construction_material(MATERIAL_ROLE_LINER, MAT_WOOD)
	for(var/index in 1 to 10)
		a.process_material_environment(a.air_contents, null, 1, 0, 1, 1, FALSE)
	b.process_material_environment(b.air_contents, null, 10, 0, 1, 1, FALSE)
	TEST_ASSERT(abs(a.material_environment_liner_integrity - b.material_environment_liner_integrity) < 0.001, "Corrosion must depend on duration rather than tick count")
	qdel(a)
	qdel(b)

/datum/unit_test/dq_material_pump_energy_conservation

/datum/unit_test/dq_material_pump_energy_conservation/Run()
	var/obj/machinery/atmospherics/binary/pump/pump = new(run_loc_floor_bottom_left)
	pump.enable_material_service()
	pump.air1.adjust_moles(/datum/gas/nitrogen, 100)
	pump.air2.adjust_moles(/datum/gas/nitrogen, 200)
	var/before = pump.air1.thermal_energy() + pump.air2.thermal_energy() + pump.material_service.heat_added
	var/input = pump_gas(pump, pump.air1, pump.air2, 1, 7500)
	TEST_ASSERT(input > 0, "Pumping into higher pressure must require positive input energy")
	var/after = pump.air1.thermal_energy() + pump.air2.thermal_energy() + pump.material_service.heat_added
	TEST_ASSERT(abs(after - before - input) < max(1, input * 0.001), "Delivered compression work plus shell losses must equal paid pump energy")
	TEST_ASSERT(abs(pump.material_service.input_joules - pump.material_service.output_joules - pump.material_service.loss_joules) < 0.01, "The pump operating ledger must close")
	qdel(pump)

/datum/unit_test/dq_material_emitter_energy_conservation

/datum/unit_test/dq_material_emitter_energy_conservation/Run()
	var/turf/test_turf
	for(var/turf/space/candidate in world)
		if(candidate.x > 2 && candidate.y > 2 && candidate.y < world.maxy - 2 && istype(get_step(candidate, NORTH), /turf/space))
			test_turf = candidate
			break
	TEST_ASSERT(test_turf, "A real beam test requires an in-bounds clear firing lane")
	var/obj/machinery/target = new(get_step(test_turf, NORTH))
	target.density = TRUE
	target.max_integrity = 10000
	target.update_integrity(10000)
	var/obj/machinery/power/emitter/emitter = new(test_turf)
	emitter.set_dir(NORTH)
	var/datum/powernet/net = new
	net.add_machine(emitter)
	net.avail = 1000000
	emitter.state = 2
	emitter.active = TRUE
	TEST_ASSERT(abs(emitter.emitter_output_limit() - 1) < 0.001, "Default glass and copper must support the emitter's rated output")
	emitter.material_last_charge = world.time - 10 SECONDS
	emitter.charge_emitter()
	var/datum/material_service/service = emitter.material_service
	TEST_ASSERT(service.input_joules > 0 && emitter.material_stored_energy > 0, "A real network draw must charge the emitter reservoir")
	emitter.last_shot = world.time - 1 MINUTE
	emitter.process()
	TEST_ASSERT(emitter.material_beam_joules > 0, "Stored energy must produce a real beam (state=[emitter.state], active=[emitter.active], stat=[emitter.stat], stored=[emitter.material_stored_energy], rating=[emitter.active_power_usage], efficiency=[emitter.emitter_efficiency()], time=[world.time], last=[emitter.last_shot], delay=[emitter.fire_delay])")
	TEST_ASSERT(abs(service.input_joules - emitter.material_beam_joules - service.loss_joules - emitter.material_stored_energy) < 1, "Input must equal beam energy plus heat plus remaining stored energy")
	TEST_ASSERT(target.get_integrity() < target.max_integrity, "The accounted beam must physically hit its target")
	for(var/obj/item/projectile/beam/emitter/beam in range(2, emitter))
		qdel(beam)
	qdel(emitter)
	qdel(target)
	if(!QDELETED(net))
		qdel(net)

/datum/unit_test/dq_material_fingerprint_is_quantity_independent

/datum/unit_test/dq_material_fingerprint_is_quantity_independent/Run()
	var/datum/material_batch/small = new
	small.add_material(MAT_STEEL, 1)
	small.add_additive("carbon", 1, 0)
	var/datum/material_batch/large = new
	large.add_material(MAT_STEEL, 10)
	large.add_additive("carbon", 10, 0)
	TEST_ASSERT_EQUAL(small.fingerprint(), large.fingerprint(), "equivalent alloy recipes registered different materials solely because batch size changed")
	qdel(small)
	qdel(large)

/datum/unit_test/dq_material_recovery_is_production_backed

/datum/unit_test/dq_material_recovery_is_production_backed/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/material_batch/source = new
	source.add_material(MAT_STEEL, 2)
	var/obj/item/stack/material/processed_alloy/stock = processed_spawn_stack(test_turf, source, 2)
	var/datum/material_batch/reclaimed = new
	TEST_ASSERT(material_batch_absorb_sheet(reclaimed, stock), "processed stock could not be returned to the furnace charge")
	TEST_ASSERT(reclaimed.cost_ledger[MATERIAL_COST_RECOVERY] > 0, "remelting reclaimed stock did not record any recovered value")
	qdel(source)
	qdel(reclaimed)
	qdel(stock)

/obj/machinery/material_furnace/unpowered_test

/obj/machinery/material_furnace/unpowered_test/use_power_oneoff(amount, chan)
	return 0

/datum/unit_test/dq_material_furnace_cannot_create_heat

/datum/unit_test/dq_material_furnace_cannot_create_heat/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/material_furnace/unpowered_test/furnace = new(test_turf)
	var/obj/item/stack/material/steel/stock = new(test_turf, 2)
	stock.forceMove(furnace)
	furnace.feedstock = list(stock)
	furnace.finish_firing()
	var/datum/material_batch/output = furnace.output_stock ? furnace.output_stock.physical_batch() : null
	TEST_ASSERT(output, "power-starved furnace failed to return recoverable stock")
	TEST_ASSERT_EQUAL(output.energy_spent, 0, "power-starved furnace invented process energy")
	TEST_ASSERT(!(MATERIAL_PROCESS_MELT in output.process_history), "power-starved furnace completed a melt without supplied energy")
	qdel(furnace)

/datum/unit_test/dq_processed_stock_split_preserves_physical_state

/datum/unit_test/dq_processed_stock_split_preserves_physical_state/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 6)
	batch.temperature = 900
	var/obj/item/stack/material/processed_alloy/stock = processed_spawn_stack(test_turf, batch, 6)
	var/material_name = stock.material.name
	var/obj/item/stack/material/processed_alloy/split_stock = stock.split(2)
	TEST_ASSERT(split_stock, "processed stock could not be split through ordinary stack handling")
	TEST_ASSERT_EQUAL(split_stock.material.name, material_name, "split stock lost its processed alloy definition")
	TEST_ASSERT_EQUAL(split_stock.physical_batch().temperature, 900, "split stock lost its physical temperature")
	TEST_ASSERT_EQUAL(split_stock.physical_batch().amount, 2, "split stock retained the wrong quantity state")
	TEST_ASSERT_EQUAL(stock.physical_batch().amount, 4, "source stock retained the wrong quantity state")
	split_stock.physical_batch().temperature = 300
	TEST_ASSERT_EQUAL(split_stock.transfer_to(stock, 2), 2, "compatible processed stocks could not merge")
	TEST_ASSERT_EQUAL(stock.physical_batch().amount, 6, "merged stock did not conserve quantity")
	TEST_ASSERT(abs(stock.physical_batch().temperature - 700) < 0.1, "merged stock did not conserve thermal energy")
	qdel(stock)
	qdel(batch)

/datum/unit_test/dq_material_furnace_requires_and_performs_real_melt

/datum/unit_test/dq_material_furnace_requires_and_performs_real_melt/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/material_furnace/furnace = new(test_turf)
	var/obj/item/stack/material/steel/stock = new(test_turf, 4)
	stock.forceMove(furnace)
	furnace.feedstock = list(stock)
	furnace.finish_firing()
	TEST_ASSERT(furnace.output_stock, "raw stock firing did not produce recoverable processed stock")
	var/datum/material_batch/output = furnace.output_stock.physical_batch()
	TEST_ASSERT(MATERIAL_PROCESS_MELT in output.process_history, "furnace produced alloy stock without melting it")
	TEST_ASSERT(MATERIAL_PROCESS_HOMOGENIZE in output.process_history, "furnace skipped molten homogenization")
	TEST_ASSERT(MATERIAL_PROCESS_CAST in output.process_history, "furnace did not cast its molten charge")
	TEST_ASSERT(output.energy_spent > 0, "furnace heating did not record physical energy expense")
	qdel(furnace)

/datum/unit_test/dq_material_delivery_requires_matching_shipment

/datum/unit_test/dq_material_delivery_requires_matching_shipment/Run()
	var/datum/contract/social/contract = new
	contract.title = "Physical material delivery test"
	contract.description = "Test matching assay and shipment."
	contract.department = DEPARTMENT_RESEARCH
	contract.reward = 0
	var/list/checks = list(list("key" = "hardness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 50))
	var/datum/contract_requirement/qualified_material_delivery/requirement = new(checks, 4)
	contract.add_requirement(requirement)
	TEST_ASSERT(contract.accept(), "material delivery fixture could not activate")
	var/datum/contract_event/assay = new(CONTRACT_EVENT_MATERIAL_CERTIFIED, null, null, null, list("department" = DEPARTMENT_RESEARCH, "fingerprint" = "qualified", "material_lot_id" = "LOT-QUALIFIED", "hardness" = 60, "amount" = 4, "contributor_account" = 42))
	TEST_ASSERT(requirement.handle_event(assay), "qualifying assay was rejected")
	TEST_ASSERT_EQUAL(requirement.state, CONTRACT_REQUIREMENT_PENDING, "assay alone completed a physical stock order")
	var/datum/contract_event/wrong_shipment = new(CONTRACT_EVENT_ITEM_EXPORTED, null, null, null, list("department" = DEPARTMENT_RESEARCH, "origin_department" = DEPARTMENT_RESEARCH, "handling_department" = DEPARTMENT_CARGO, "material_fingerprint" = "qualified", "material_lot_id" = "LOT-WRONG", "material_amount" = 4))
	TEST_ASSERT(!requirement.handle_event(wrong_shipment), "a different batch satisfied the assayed stock order")
	var/datum/contract_event/shipment = new(CONTRACT_EVENT_ITEM_EXPORTED, null, null, null, list("department" = DEPARTMENT_RESEARCH, "origin_department" = DEPARTMENT_RESEARCH, "handling_department" = DEPARTMENT_CARGO, "material_fingerprint" = "qualified", "material_lot_id" = "LOT-QUALIFIED", "material_amount" = 4))
	TEST_ASSERT(requirement.handle_event(shipment), "matching assayed cargo shipment was rejected")
	TEST_ASSERT_EQUAL(requirement.state, CONTRACT_REQUIREMENT_COMPLETE, "matching assay and shipment did not complete the order")
	qdel(assay)
	qdel(wrong_shipment)
	qdel(shipment)
	qdel(contract)

/datum/unit_test/dq_material_furnace_prepares_real_heat_treatment

/datum/unit_test/dq_material_furnace_prepares_real_heat_treatment/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 4)
	var/obj/item/stack/material/processed_alloy/stock = processed_spawn_stack(test_turf, batch, 4)
	TEST_ASSERT(stock, "failed to create physical processed stock for heat-treatment test")
	var/obj/machinery/material_furnace/furnace = new(test_turf)
	stock.forceMove(furnace)
	furnace.feedstock = list(stock)
	furnace.finish_firing()
	TEST_ASSERT(furnace.output_stock, "furnace failed to return heat-treated stock")
	var/datum/material/processed_alloy/output_material = furnace.output_stock.material
	var/datum/material_batch/output_batch = output_material.batch_template
	TEST_ASSERT(output_batch.solution_treated, "a dedicated furnace heat-treatment firing did not prepare the stock for quenching")
	TEST_ASSERT(output_batch.can_process(MATERIAL_PROCESS_QUENCH), "furnace output was not physically hot enough to quench")
	var/datum/material_batch/forge_sample = output_batch.copy_batch()
	TEST_ASSERT(forge_sample.apply_process(MATERIAL_PROCESS_FORGE), "hot furnace output could not be forged without fictitious anvil heating")
	TEST_ASSERT(output_batch.apply_process(MATERIAL_PROCESS_QUENCH), "hot solution-treated furnace output could not be physically quenched")
	TEST_ASSERT_EQUAL(output_batch.temperature, T20C, "quenching did not cool the workpiece")
	qdel(forge_sample)
	qdel(batch)
	qdel(furnace)

/datum/unit_test/dq_material_rebuild_preserves_damage

/datum/unit_test/dq_material_rebuild_preserves_damage/Run()
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	cell.take_damage(cell.max_integrity * 0.4, BRUTE)
	var/ratio = cell.get_integrity() / cell.max_integrity
	cell.apply_material_construction(null, material_template_path_for_application(MATERIAL_APPLICATION_CELL), 2000)
	TEST_ASSERT(abs(cell.get_integrity() / cell.max_integrity - ratio) < 0.001, "Recalculation must not repair structural damage")
	qdel(cell)

/datum/unit_test/dq_material_qualification_records

/datum/unit_test/dq_material_qualification_records/Run()
	var/datum/contract/contract = new
	contract.title = "Recorded assembly test"
	contract.description = "Test ordered physical records."
	contract.reward = 0
	var/datum/contract_requirement/recorded_stages/requirement = new("power", "minimum_output_watts", "W", list(100, 200))
	contract.add_requirement(requirement)
	TEST_ASSERT(contract.accept(), "A recorded-stage contract must be acceptable")
	contract.accepted_at = 1 MINUTE
	var/list/payload = list("kind" = "power", "destination" = CONTRACT_FAX_ENGINEERING, "started" = 1 MINUTE, "ended" = 2 MINUTES, "duration" = 60, "minimum_output_watts" = 100, "efficiency" = 0.9)
	var/id = SScontracts.register_evidence(CONTRACT_EVIDENCE_ENGINEERING, "assembly-test", null, null, payload)
	payload["evidence_ids"] = list(id)
	var/datum/contract_event/event = new(CONTRACT_EVENT_FAX_ACCEPTED, null, null, null, payload)
	event.occurred_at = 2 MINUTES
	TEST_ASSERT(requirement.handle_event(event), "A complete recorded minute must advance one stage")
	TEST_ASSERT_EQUAL(requirement.progress, 1, "One record may advance only one stage")
	TEST_ASSERT(!requirement.handle_event(event), "A copied or overlapping report must not advance another stage")
	qdel(event)
	payload["started"] = 2 MINUTES
	payload["ended"] = 3 MINUTES
	payload["minimum_output_watts"] = 200
	id = SScontracts.register_evidence(CONTRACT_EVIDENCE_ENGINEERING, "assembly-test", null, null, payload)
	payload["evidence_ids"] = list(id)
	event = new(CONTRACT_EVENT_FAX_ACCEPTED, null, null, null, payload)
	event.occurred_at = 3 MINUTES
	TEST_ASSERT(requirement.handle_event(event), "A subsequent stronger observation must advance the next stage")
	TEST_ASSERT_EQUAL(requirement.progress, 2, "All stages must complete from separate measurements")
	qdel(event)
	qdel(contract)

/datum/unit_test/dq_material_refit_clears_old_behaviors

/datum/unit_test/dq_material_refit_clears_old_behaviors/Run()
	var/obj/item/item = new
	var/datum/component/material_behaviors/behavior = item.AddComponent(/datum/component/material_behaviors, 30, 20, 10, "#00ff00")
	TEST_ASSERT(behavior.processing && behavior.radioactivity > 0, "The initial material must actually emit radiation")
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	steel.dq_apply_material_behaviors(item)
	TEST_ASSERT(!behavior.processing && !behavior.radioactivity && !behavior.toxicity && !behavior.luminescence, "Inert replacement stock must remove all old emissions and stop processing")
	qdel(item)

/datum/unit_test/dq_material_physical_cable_loss

/datum/unit_test/dq_material_physical_cable_loss/Run()
	var/datum/powernet/net = new
	var/obj/structure/cable/start = new(locate(2, 2, 1))
	var/obj/structure/cable/middle = new(locate(3, 2, 1))
	var/obj/structure/cable/end = new(locate(4, 2, 1))
	start.d1 = 0
	start.d2 = EAST
	middle.d1 = EAST
	middle.d2 = WEST
	end.d1 = 0
	end.d2 = WEST
	net.add_cable(start)
	net.add_cable(middle)
	net.add_cable(end)
	net.rebuild_material_cache()
	var/datum/material_power_graph/graph = net.material_graph
	TEST_ASSERT_EQUAL(length(graph.vertices), 2, "A real straight cable run should reduce to its two attachment vertices")
	TEST_ASSERT_EQUAL(length(graph.edges), 1, "Real cable connectivity should produce one reduced edge")
	var/list/sources = list()
	var/list/consumers = list()
	sources[WEAKREF(start)] = 10000
	consumers[WEAKREF(end)] = 10000
	graph.resolve_loads(sources, consumers)
	TEST_ASSERT(graph.loss_watts > 0, "A real loaded ordinary cable must have positive resistance loss")
	graph.deposit_losses(12000)
	for(var/obj/structure/cable/cable as anything in net.cables)
		TEST_ASSERT(!cable.material_service, "Normally loaded station cable must not enter per-object material exposure")
		cable.set_engineered_material(MAT_COPPER)
	net.rebuild_material_cache()
	graph = net.material_graph
	graph.resolve_loads(sources, consumers)
	var/before = 0
	for(var/obj/structure/cable/cable as anything in net.cables)
		cable.enable_material_service()
		before += cable.material_service.heat_added
	graph.deposit_losses(12000)
	var/after = 0
	for(var/obj/structure/cable/cable as anything in net.cables)
		after += cable.material_service.heat_added
	TEST_ASSERT(abs(after - before - 12000) < 2, "Paid loss must become exactly that much heat across the real cable run")
	TEST_ASSERT(!graph.resistance_dirty && length(graph.dirty_edges) == 1, "Heating a cable run must invalidate that run without requesting a full network resistance scan")
	graph.resolve_loads(sources, list())
	graph.deposit_losses(0)
	TEST_ASSERT_EQUAL(middle.material_current, 0, "Disconnecting the load must clear the cable's current")
	qdel(start)
	qdel(middle)
	qdel(end)
	if(!QDELETED(net))
		qdel(net)

/datum/unit_test/dq_material_high_energy_progression

/datum/unit_test/dq_material_high_energy_progression/Run()
	var/datum/material_batch/storage_batch = new
	storage_batch.add_material(MAT_COPPER, 3, null, 98)
	storage_batch.add_material(MAT_QUARTZ, 2, null, 98)
	storage_batch.add_field_treatment(MATERIAL_FIELD_PARTICLE, 45)
	storage_batch.add_field_treatment(MATERIAL_FIELD_ENERGY_STORAGE, 30)
	var/datum/material/storage = get_material_by_name(register_processed_material(storage_batch))
	TEST_ASSERT(storage.field_energy_capacity >= 1000, "PA-conditioned conductive crystal did not become an energy-storage material")
	TEST_ASSERT(storage.field_charge_efficiency > 0, "PA-conditioned conductive crystal cannot accept deposited field energy")

	var/datum/material_batch/switch_batch = new
	switch_batch.add_material(MAT_COPPER, 3, null, 98)
	switch_batch.add_material(MAT_NICKEL, 2, null, 98)
	switch_batch.add_field_treatment(MATERIAL_FIELD_FUSION, 50)
	var/datum/material/thermal_switch = get_material_by_name(register_processed_material(switch_batch))
	TEST_ASSERT(thermal_switch.thermoelectric_coefficient > 0, "copper-nickel alloy did not gain useful thermoelectric response")
	TEST_ASSERT(thermal_switch.thermal_switch_temperature > T20C, "fusion-conditioned copper-nickel alloy did not become a thermal switch")

	var/datum/material_batch/heater_batch = new
	heater_batch.add_material(MAT_TUNGSTEN, 4, null, 98)
	heater_batch.add_material(MAT_PHORON, 1, null, 98)
	heater_batch.add_field_treatment(MATERIAL_FIELD_FUSION, 45)
	var/datum/material/heater = get_material_by_name(register_processed_material(heater_batch))
	TEST_ASSERT(heater.exothermic_heat_rate >= 25, "fusion-conditioned tungsten-phoron alloy did not become an exothermic heat source")

	var/datum/material_batch/pump_batch = new
	pump_batch.add_material(MAT_COPPER, 3, null, 98)
	pump_batch.add_material(MAT_NICKEL, 2, null, 98)
	pump_batch.add_field_treatment(MATERIAL_FIELD_FUSION, 45)
	var/datum/material/pump = get_material_by_name(register_processed_material(pump_batch))
	TEST_ASSERT(pump.heat_pump_coefficient > 0, "fusion-conditioned copper-nickel stock did not become an active heat-pump material")
	var/datum/material_batch/memory_batch = new
	memory_batch.add_material(MAT_NICKEL, 2, null, 98)
	memory_batch.add_material(MAT_TITANIUM, 3, null, 98)
	memory_batch.homogeneity = 90
	memory_batch.toughness = 80
	var/datum/material/memory = get_material_by_name(register_processed_material(memory_batch))
	TEST_ASSERT(memory.shape_recovery_rate > 0, "nickel-titanium stock did not gain shape-memory recovery")
	qdel(storage_batch)
	qdel(switch_batch)
	qdel(heater_batch)
	qdel(pump_batch)
	qdel(memory_batch)
