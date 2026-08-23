/datum/unit_test/dq_material_science_process_chain

/datum/unit_test/dq_material_science_process_chain/Run()
	var/datum/material_batch/batch = new
	TEST_ASSERT(batch.add_material(MAT_STEEL, 2), "Steel must load into a batch")
	TEST_ASSERT(batch.add_material(MAT_COPPER, 1), "Copper must alloy into the same batch")
	TEST_ASSERT_EQUAL(batch.amount, 3, "Material conservation failed")
	while(batch.temperature < batch.melting_temperature())
		batch.apply_process(MATERIAL_PROCESS_HEAT)
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_MELT), "The feedstock must melt")
	TEST_ASSERT_EQUAL(batch.phase, MATERIAL_PHASE_MOLTEN, "Melt did not change phase")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_CAST), "Molten stock must cast")
	var/cast_porosity = batch.porosity
	TEST_ASSERT(!batch.apply_process(MATERIAL_PROCESS_FORGE), "Cold cast stock must not forge")
	while(batch.temperature < batch.melting_temperature() * 0.65)
		batch.apply_process(MATERIAL_PROCESS_HEAT)
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_FORGE), "Cast stock must forge")
	TEST_ASSERT(batch.porosity < cast_porosity, "Forging must close porosity")
	var/pre_quench_hardness = batch.hardness
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_SOLUTION_TREAT), "Hot stock must solution treat before quenching")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_QUENCH), "Stock must quench")
	TEST_ASSERT(batch.hardness >= pre_quench_hardness, "Quenching must not soften the material")
	var/quench_stress = batch.internal_stress
	while(batch.temperature < batch.melting_temperature() * 0.25)
		batch.apply_process(MATERIAL_PROCESS_HEAT)
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_TEMPER), "Quenched stock must temper")
	TEST_ASSERT(batch.internal_stress < quench_stress, "Tempering must relieve quench stress")
	qdel(batch)

/datum/unit_test/dq_material_science_registration

/datum/unit_test/dq_material_science_registration/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 3)
	batch.add_material(MAT_SILVER, 1)
	while(batch.temperature < batch.melting_temperature())
		batch.apply_process(MATERIAL_PROCESS_HEAT)
	batch.apply_process(MATERIAL_PROCESS_MELT)
	batch.apply_process(MATERIAL_PROCESS_CAST)
	var/key_a = register_processed_material(batch)
	var/key_b = register_processed_material(batch.copy_batch())
	TEST_ASSERT_NOTNULL(key_a, "A valid batch must become a material")
	TEST_ASSERT_EQUAL(key_a, key_b, "Identical batches must deduplicate")
	var/datum/material/processed_alloy/material = get_material_by_name(key_a)
	TEST_ASSERT(istype(material), "Registered material must resolve through the global material registry")
	TEST_ASSERT(material.hardness > 0 && material.integrity > 0, "Processed properties must reach manufactured objects")
	TEST_ASSERT_EQUAL(length(material.composite_material), 2, "Recycling composition must preserve both inputs")
	qdel(batch)

/datum/unit_test/dq_material_science_chemistry

/datum/unit_test/dq_material_science_chemistry/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_IRON, 1)
	var/start_purity = batch.purity
	batch.add_additive("carbon", 8)
	TEST_ASSERT(batch.purity < start_purity, "Uncontrolled chemical addition must affect purity")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_DISSOLVE), "Solid feedstock must be dissolved before electrolysis")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_ELECTROLYZE), "Electrolysis must process an impure batch")
	TEST_ASSERT(batch.purity > start_purity - 4, "Electrolysis must recover purity")
	TEST_ASSERT_EQUAL(length(batch.impurities), 0, "Electrolysis must separate tracked impurities")
	qdel(batch)

/datum/unit_test/dq_material_science_nonlinear_tradeoffs

/datum/unit_test/dq_material_science_nonlinear_tradeoffs/Run()
	var/datum/material_batch/controlled = new
	controlled.add_material(MAT_IRON, 4, null, 96, "CONTROL")
	controlled.add_additive("carbon", 6)
	var/datum/material_batch/excessive = new
	excessive.add_material(MAT_IRON, 4, null, 96, "EXCESS")
	excessive.add_additive("carbon", 20)
	TEST_ASSERT(controlled.hardness > excessive.hardness, "A concentration window must outperform excessive hardener addition")
	TEST_ASSERT(excessive.brittleness > controlled.brittleness, "Excess hardener must create a brittleness tradeoff")
	var/datum/material_batch/dirty = new
	dirty.add_material(MAT_IRON, 4, null, 78, "DIRTY")
	TEST_ASSERT(dirty.purity < controlled.purity, "Source-lot assay must affect an otherwise identical material")
	qdel(controlled)
	qdel(excessive)
	qdel(dirty)

/datum/unit_test/dq_material_science_physical_testing

/datum/unit_test/dq_material_science_physical_testing/Run()
	var/obj/item/reagent_containers/glass/material_crucible/crucible = new(run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/feedstock = new(run_loc_floor_bottom_left, 4)
	TEST_ASSERT(material_batch_absorb_sheet(crucible.batch, feedstock), "Physical feedstock must enter the crucible")
	var/datum/material_batch/original_batch = crucible.batch
	var/datum/material_batch/transferred_batch = crucible.release_batch()
	var/obj/item/material_workpiece/workpiece = new(run_loc_floor_bottom_left, transferred_batch)
	TEST_ASSERT_EQUAL(workpiece.batch, original_batch, "Casting must transfer the authoritative batch instead of reconstructing it")
	workpiece.batch.add_surface_layer(MATERIAL_SURFACE_CARBON, 30, "carbon", 3)
	workpiece.batch.add_dissolved_gas("nitrogen", 4)
	workpiece.batch.add_field_treatment(MATERIAL_FIELD_PARTICLE, 40)
	var/datum/material_batch/copy = workpiece.batch.copy_batch()
	TEST_ASSERT_EQUAL(copy.surface_layers[MATERIAL_SURFACE_CARBON], 30, "Physical surface treatments must survive batch copying")
	TEST_ASSERT_EQUAL(copy.dissolved_gases["nitrogen"], 4, "Real-atmos gas infusion must survive batch copying")
	TEST_ASSERT_EQUAL(copy.field_treatments[MATERIAL_FIELD_PARTICLE], 40, "Field treatments must survive batch copying")
	qdel(copy)
	qdel(workpiece)
	qdel(crucible)
	qdel(feedstock)

/datum/unit_test/dq_material_science_real_atmosphere

/datum/unit_test/dq_material_science_real_atmosphere/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left)
	if(!istype(test_turf, /turf/simulated/floor))
		test_turf = locate(/turf/simulated/floor) in world
	TEST_ASSERT_NOTNULL(test_turf, "Real-atmos material testing requires a simulated floor")
	var/obj/machinery/material_furnace/furnace = new(test_turf)
	var/datum/gas_mixture/air = furnace.chamber_air
	air.clear()
	air.adjust_moles(/datum/gas/oxygen, 10)
	air.adjust_moles(/datum/gas/nitrogen, 60)
	air.adjust_moles(/datum/gas/plasma, 2)
	air.set_temperature(T20C)
	var/oxygen_before = air.get_moles(/datum/gas/oxygen)
	var/nitrogen_before = air.get_moles(/datum/gas/nitrogen)
	var/phoron_before = air.get_moles(/datum/gas/plasma)
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 3, null, 96, "ATMOSLOT")
	batch.temperature = batch.melting_temperature()
	furnace.apply_real_atmosphere(batch)
	TEST_ASSERT(air.get_moles(/datum/gas/oxygen) < oxygen_before, "A hot open firing must consume real oxygen")
	TEST_ASSERT(air.get_moles(/datum/gas/nitrogen) < nitrogen_before, "A pressurized firing must consume real nitrogen")
	TEST_ASSERT(air.get_moles(/datum/gas/plasma) < phoron_before, "A phoron atmosphere must physically dope and consume real phoron")
	TEST_ASSERT(batch.dissolved_gases["nitrogen"] && batch.dissolved_gases["oxygen"] && batch.dissolved_gases["phoron"], "Consumed gases must remain represented in the physical batch")
	TEST_ASSERT(batch.surface_layers[MATERIAL_SURFACE_OXIDE], "Oxygen firing must leave visible oxide scale")
	qdel(batch)
	qdel(furnace)

/datum/unit_test/dq_material_composite_geometry

/datum/unit_test/dq_material_composite_geometry/Run()
	var/composite_key = register_composite_material(MAT_COPPER, 13, MAT_LEAD, 4, MAT_GLASS, 1, MAT_PLASTIC, 2)
	TEST_ASSERT_NOTNULL(composite_key, "A valid four-layer layup must register")
	var/datum/material/composite/composite = get_material_by_name(composite_key)
	TEST_ASSERT(istype(composite), "A registered layup must retain its physical layers")
	TEST_ASSERT_EQUAL(composite.core_material_id, MAT_COPPER, "The conductor core must not be averaged away")
	TEST_ASSERT_EQUAL(composite.functional_material_id, MAT_LEAD, "The functional layer must remain addressable")
	TEST_ASSERT_EQUAL(composite.liner_material_id, MAT_GLASS, "Chemistry must see the inner liner")
	TEST_ASSERT_EQUAL(composite.jacket_material_id, MAT_PLASTIC, "The exterior jacket must remain addressable")
	var/datum/material/copper = get_material_by_name(MAT_COPPER)
	var/datum/material/plastic = get_material_by_name(MAT_PLASTIC)
	var/datum/material/glass = get_material_by_name(MAT_GLASS)
	TEST_ASSERT(composite.material_thermal_conductance(1, 0.01, T20C) < copper.material_thermal_conductance(1, 0.01, T20C), "A series insulating jacket must reduce heat flow instead of being averaged into the core")
	TEST_ASSERT(composite.material_pressure_limit(20, 4, T20C) > composite.material_pressure_limit(20, 2, T20C), "Pressure strength must derive from wall geometry")
	TEST_ASSERT(composite.material_radiation_transmission(20) < composite.material_radiation_transmission(5), "Radiation attenuation must derive from actual thickness")
	TEST_ASSERT_EQUAL(composite.material_corrosion_rate(REAGENT_ID_SACID, T20C), glass.material_corrosion_rate(REAGENT_ID_SACID, T20C), "Reagents must contact the liner rather than an averaged bulk")
	TEST_ASSERT(composite.material_electrical_resistance(1, MATERIAL_CABLE_REFERENCE_AREA, T20C, 0) < plastic.material_electrical_resistance(1, MATERIAL_CABLE_REFERENCE_AREA, T20C, 0), "Electrical current must follow the conductive core")

/datum/unit_test/dq_material_composite_superconductor_stack

/datum/unit_test/dq_material_composite_superconductor_stack/Run()
	var/datum/material_batch/conductor_batch = new
	conductor_batch.add_material(MAT_METALHYDROGEN, 3, null, 99, "SUPERCONDUCTOR")
	var/conductor_key = register_processed_material(conductor_batch)
	var/datum/material/processed_alloy/conductor = get_material_by_name(conductor_key)
	TEST_ASSERT(conductor.critical_temperature > 0, "A qualified physical conductor must publish a critical temperature")
	var/datum/material_batch/buffer_batch = new
	buffer_batch.add_material(MAT_STEEL, 3, null, 99, "CRYOBUFFER")
	buffer_batch.add_surface_layer(MATERIAL_SURFACE_SLIME_CRYO, 60, "cryogenic slime extract", 1)
	var/buffer_key = register_processed_material(buffer_batch)
	var/composite_key = register_composite_material(conductor_key, 13, buffer_key, 4, MAT_GLASS, 1, MAT_PLASTIC, 2)
	var/datum/material/composite/composite = get_material_by_name(composite_key)
	TEST_ASSERT(composite.phase_change_capacity > 0, "A cryogenic functional layer must provide a conserved thermal buffer")
	var/cold_resistance = composite.material_electrical_resistance(1, MATERIAL_CABLE_REFERENCE_AREA, conductor.critical_temperature - 5, 1)
	var/warm_resistance = composite.material_electrical_resistance(1, MATERIAL_CABLE_REFERENCE_AREA, conductor.critical_temperature + 20, 1)
	TEST_ASSERT(cold_resistance < warm_resistance, "The core may superconduct only while the real composite remains below its critical temperature")
	TEST_ASSERT(composite.material_thermal_conductance(1, 0.01, T20C) < conductor.material_thermal_conductance(1, 0.01, T20C), "The outer insulating jacket must limit heat leaking through the finished conductor")
	qdel(buffer_batch)
	qdel(conductor_batch)

/datum/unit_test/dq_material_composite_physical_products

/datum/unit_test/dq_material_composite_physical_products/Run()
	var/composite_key = register_composite_material(MAT_COPPER, 13, MAT_LEAD, 4, MAT_GLASS, 1, MAT_PLASTIC, 2)
	var/obj/structure/material_composite_press/press = new(run_loc_floor_bottom_left)
	press.core_material_id = MAT_COPPER
	press.core_sheets = 1
	press.functional_material_id = MAT_LEAD
	press.functional_sheets = 1
	press.liner_material_id = MAT_GLASS
	press.liner_sheets = 1
	press.jacket_material_id = MAT_PLASTIC
	press.jacket_sheets = 1
	var/obj/item/stack/material/composite/pressed_stock = press.finish_layup(null)
	TEST_ASSERT_NOTNULL(pressed_stock, "The press must eject tangible composite stock")
	TEST_ASSERT_EQUAL(pressed_stock.get_amount(), 4, "Composite layup must conserve all four input sheets")
	var/obj/item/stack/cable_coil/engineered/coil = new(run_loc_floor_bottom_left, 10, null, composite_key)
	TEST_ASSERT_EQUAL(coil.engineered_material_id, composite_key, "Fabricated cable must retain its selected composite")
	var/obj/item/reagent_containers/glass/beaker/composite/vessel = new(run_loc_floor_bottom_left, composite_key)
	TEST_ASSERT_EQUAL(vessel.engineered_material_id, composite_key, "A reaction vessel must retain the same canonical material identity")
	var/datum/material/glass = get_material_by_name(MAT_GLASS)
	TEST_ASSERT_EQUAL(vessel.material_reaction_rate_multiplier(), 1 + glass.catalytic_activity / 100, "Vessel kinetics must be controlled by its exposed liner")
	qdel(vessel)
	qdel(coil)
	qdel(pressed_stock)
	qdel(press)

/datum/unit_test/dq_material_composite_power_response

/datum/unit_test/dq_material_composite_power_response/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left)
	if(!test_turf)
		test_turf = locate(/turf/simulated/floor) in world
	TEST_ASSERT_NOTNULL(test_turf, "Composite power response requires a real turf")
	var/composite_key = register_composite_material(MAT_COPPER, 13, MAT_LEAD, 4, MAT_GLASS, 1, MAT_PLASTIC, 2)
	var/obj/structure/cable/cable = new(test_turf)
	cable.set_engineered_material(composite_key)
	var/datum/powernet/network = new
	network.add_cable(cable)
	network.load = 500000
	var/start_temperature = cable.material_temperature
	network.process_material_network()
	TEST_ASSERT(network.material_hotspot == cable, "Powernet topology must select the engineered conductor without rescanning stable networks")
	TEST_ASSERT(cable.material_temperature > start_temperature || cable.material_buffer_energy > 0, "Real electrical load must become conductor heat or conserved phase-buffer energy")
	qdel(network)
	qdel(cable)

/datum/unit_test/dq_material_science_solution_and_bath

/datum/unit_test/dq_material_science_solution_and_bath/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left)
	if(!istype(test_turf, /turf/simulated/floor))
		test_turf = locate(/turf/simulated/floor) in world
	TEST_ASSERT_NOTNULL(test_turf, "Physical chemistry testing requires a simulated floor")
	var/obj/machinery/material_furnace/furnace = new(test_turf)
	var/obj/item/reagent_containers/glass/material_crucible/crucible = new(furnace)
	crucible.batch.add_material(MAT_STEEL, 3, null, 96, "CHEMLOT")
	crucible.reagents.add_reagent(REAGENT_ID_SACID, 10)
	furnace.crucible = crucible
	TEST_ASSERT(furnace.process_crucible_chemistry(crucible.batch), "Ordinary acid must move a solid charge into the solution route")
	TEST_ASSERT_EQUAL(crucible.batch.phase, MATERIAL_PHASE_SOLUTION, "A newly dissolved charge must persist as a physical solution instead of immediately becoming stock")

	var/datum/material_batch/workpiece_batch = new
	workpiece_batch.add_material(MAT_STEEL, 3, null, 96, "BATHLOT")
	workpiece_batch.temperature = round(workpiece_batch.melting_temperature() * 0.72)
	workpiece_batch.solution_treated = TRUE
	var/obj/item/material_workpiece/workpiece = new(test_turf, workpiece_batch)
	var/obj/structure/bed/bath/material_treatment/bath = new(test_turf)
	bath.reagents.add_reagent(REAGENT_ID_WATER, 10)
	var/water_before = bath.reagents.get_reagent_amount(REAGENT_ID_WATER)
	TEST_ASSERT(bath.quench_workpiece(workpiece, null), "A real water bath must quench a prepared hot workpiece")
	TEST_ASSERT(bath.reagents.get_reagent_amount(REAGENT_ID_WATER) < water_before, "Quenching must consume its ordinary reagent medium")
	TEST_ASSERT(workpiece.batch.structure[MATERIAL_STRUCTURE_HARDENED] > 0, "The physical quench must harden the lattice")

	workpiece.batch.temperature = T20C
	bath.reagents.add_reagent(REAGENT_ID_SILVER, 10)
	var/obj/item/cell/high/cell = new(bath)
	bath.electrode_cell = cell
	TEST_ASSERT(bath.chemically_treat_workpiece(workpiece, null), "A powered ordinary silver bath must plate a cool workpiece")
	TEST_ASSERT(workpiece.batch.impurities["silver plating"] && workpiece.batch.surface_layers[MATERIAL_SURFACE_PLATING], "Plating must remain a visible surface layer rather than silently altering bulk composition")
	qdel(bath)
	qdel(workpiece)
	qdel(furnace)

/datum/unit_test/dq_material_science_feedstock_lots

/datum/unit_test/dq_material_science_feedstock_lots/Run()
	var/obj/item/stack/material/steel/feedstock = new(run_loc_floor_bottom_left, 5)
	feedstock.ensure_feedstock_lot()
	TEST_ASSERT(feedstock.feedstock_purity >= 78 && feedstock.feedstock_purity <= 99, "Physical feedstock must carry a bounded source assay")
	TEST_ASSERT_NOTNULL(feedstock.feedstock_lot_id, "Physical feedstock must carry a stable lot identity")
	var/original_lot = feedstock.feedstock_lot_id
	feedstock.ensure_feedstock_lot()
	TEST_ASSERT_EQUAL(feedstock.feedstock_lot_id, original_lot, "Inspecting a feedstock source must not reroll it")
	qdel(feedstock)

/datum/unit_test/dq_material_science_cost_accounting

/datum/unit_test/dq_material_science_cost_accounting/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 4, null, 95, "COSTLOT")
	batch.add_additive("priced reagent", 3, 2, MATERIAL_COST_CHEMICALS)
	batch.add_additive("priced catalyst", 5, 4, MATERIAL_COST_CATALYSTS)
	batch.record_electricity(2000)
	batch.record_cost(MATERIAL_COST_MEDIA, 3)
	var/initial_total = batch.total_production_cost()
	TEST_ASSERT(initial_total > 30, "Feedstock, chemicals, catalysts, electricity, and media must all enter total expense")
	var/initial_unit = batch.unit_production_cost()
	batch.yield_fraction = 0.5
	batch.record_yield_loss(0.5)
	var/post_waste_total = batch.total_production_cost()
	TEST_ASSERT_EQUAL(post_waste_total, initial_total + 1, "Waste may add handling cost but must not double-charge feedstock already purchased")
	TEST_ASSERT(batch.unit_production_cost() >= initial_unit * 1.99, "Lower yield must increase cost per usable sheet")
	TEST_ASSERT(batch.cost_ledger[MATERIAL_COST_WASTE] > 0, "Lost yield must remain visible in the audit ledger")
	batch.record_recovery(5)
	TEST_ASSERT_EQUAL(batch.total_production_cost(), post_waste_total - 5, "Recovered byproducts must credit production expense")
	var/datum/material_batch/copy = batch.copy_batch()
	TEST_ASSERT_EQUAL(copy.total_production_cost(), batch.total_production_cost(), "Batch transfers must preserve their complete cost ledger")
	qdel(copy)
	qdel(batch)

/datum/unit_test/dq_material_science_applications

/datum/unit_test/dq_material_science_applications/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 2, null, 98, "APPLICATIONLOT")
	batch.add_material(MAT_COPPER, 1, null, 98, "APPLICATIONLOT")
	batch.hardness = 90
	batch.toughness = 85
	batch.conductivity = 75
	batch.heat_resistance = 80
	batch.corrosion_resistance = 85
	batch.recalculate()
	var/material_key = register_processed_material(batch)
	var/datum/material/processed_alloy/material = get_material_by_name(material_key)
	TEST_ASSERT(istype(material), "Application test alloy must register")
	TEST_ASSERT(material.density > 0 && material.protectiveness > 0 && material.thermal_insulation >= 0, "Processed alloys must publish the complete material property model")

	var/obj/item/tool/wrench/tool = new(run_loc_floor_bottom_left)
	var/original_force = tool.force
	TEST_ASSERT(tool.apply_engineered_material(material, MATERIAL_APPLICATION_TOOL), "Ordinary tools must accept an engineered material profile")
	TEST_ASSERT_EQUAL(tool.get_material(), material, "An engineered item must retain its actual material identity")
	TEST_ASSERT(tool.force >= original_force && tool.toolspeed < 1.25, "Tool performance must derive from alloy properties")

	var/obj/item/surgical/scalpel/scalpel = new(run_loc_floor_bottom_left)
	TEST_ASSERT(scalpel.apply_engineered_material(material, MATERIAL_APPLICATION_SURGICAL), "Surgical instruments must accept an engineered material profile")
	TEST_ASSERT(scalpel.material_surgery_cleanliness_bonus > 0 && scalpel.material_tool_quality_bonus > 0, "Surgical alloys must affect cleanliness and procedure quality")

	var/wire_key = register_processed_material(batch)
	var/datum/material/processed_alloy/wire_material = get_material_by_name(wire_key)
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	var/base_capacity = cell.maxcharge
	TEST_ASSERT(cell.apply_engineered_material(wire_material, MATERIAL_APPLICATION_CELL), "Power cells must accept engineered conductor cores")
	TEST_ASSERT(cell.maxcharge != base_capacity && cell.material_emp_resistance > 0, "Cell capacity and EMP resistance must derive from conductor properties")

	qdel(cell)
	qdel(scalpel)
	qdel(tool)
	qdel(batch)


/datum/unit_test/dq_material_response_derivation

/datum/unit_test/dq_material_response_derivation/Run()
	var/datum/material_batch/batch = new
	batch.composition = list(MAT_QUARTZ = 2, MAT_COPPER = 3, MAT_URANIUM = 1)
	batch.impurities = list("thermal phase catalyst" = 4, "conductive dopant" = 4)
	batch.surface_layers[MATERIAL_SURFACE_SLIME_THERMAL] = 35
	batch.surface_layers[MATERIAL_SURFACE_SLIME_CONDUCTIVE] = 35
	batch.field_treatments[MATERIAL_FIELD_PARTICLE] = 60
	batch.conductivity = 90
	batch.heat_resistance = 85
	batch.homogeneity = 92
	batch.purity = 96
	batch.corrosion_resistance = 80
	batch.recalculate()
	var/material_key = register_processed_material(batch)
	var/datum/material/processed_alloy/material = get_material_by_name(material_key)
	TEST_ASSERT_NOTNULL(material, "A tested physical batch must register as a material")
	TEST_ASSERT(material.thermoelectric_coefficient > 0, "A thermally catalyzed conductor must derive a thermoelectric coefficient")
	TEST_ASSERT(material.piezoelectric_coefficient > 0, "A homogeneous crystal conductor must derive a piezoelectric coefficient")
	TEST_ASSERT(material.electrogenic_rate > 0, "A conductive surface treatment must derive an electrogenic rate")
	TEST_ASSERT(length(material.material_response_summary()) >= 3, "Measured coefficients must produce an inspectable response summary")
	qdel(batch)

/datum/unit_test/dq_material_response_application

/datum/unit_test/dq_material_response_application/Run()
	var/datum/material/processed_alloy/material = new
	material.name = "unit_test_response_material"
	material.display_name = "response test alloy"
	material.batch_template = new
	material.piezoelectric_coefficient = 0.8
	material.electrogenic_rate = 10
	material.antimicrobial_activity = 80
	material.reactive_energy_capacity = 2000
	GLOB.name_to_material[material.name] = material
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	TEST_ASSERT(cell.apply_engineered_material(material, MATERIAL_APPLICATION_CELL), "A cell must accept an engineered conductor")
	var/datum/component/material_response/cell_response = cell.GetComponent(/datum/component/material_response)
	TEST_ASSERT_NOTNULL(cell_response, "Numeric electrical responses must attach to an electrical form")
	cell.charge = 0
	cell.material_response_impact(SUB_TRIG_IMPACT, get_turf(cell), cell)
	TEST_ASSERT(cell.charge > 0, "A piezoelectric coefficient must create charge from a physical impact")
	var/obj/item/surgical/scalpel/scalpel = new(run_loc_floor_bottom_left)
	TEST_ASSERT(scalpel.apply_engineered_material(material, MATERIAL_APPLICATION_SURGICAL), "A scalpel must accept an engineered material")
	TEST_ASSERT_NOTNULL(scalpel.GetComponent(/datum/component/material_response), "A medical coefficient must attach to surgical geometry")
	qdel(scalpel)
	qdel(cell)
	GLOB.name_to_material -= material.name
	qdel(material)

/datum/unit_test/dq_material_composite_conservation

/datum/unit_test/dq_material_composite_conservation/Run()
	var/composite_key = register_composite_material(MAT_COPPER, 7, MAT_LEAD, 3, MAT_GLASS, 2, MAT_PLASTIC, 1)
	var/datum/material/composite/composite = get_material_by_name(composite_key)
	TEST_ASSERT_NOTNULL(composite, "A complete layup must register")
	TEST_ASSERT_EQUAL(composite.core_sheets, 7, "The composite must retain its actual core input")
	TEST_ASSERT_EQUAL(composite.functional_sheets, 3, "The composite must retain its actual functional input")
	TEST_ASSERT_EQUAL(composite.liner_sheets, 2, "The composite must retain its actual liner input")
	TEST_ASSERT_EQUAL(composite.jacket_sheets, 1, "The composite must retain its actual jacket input")
	var/total_sheets = composite.core_sheets + composite.functional_sheets + composite.liner_sheets + composite.jacket_sheets
	TEST_ASSERT(abs(composite.core_fraction * total_sheets - 7) < 0.0001, "Core matter must be exactly conserved")
	TEST_ASSERT(abs(composite.functional_fraction * total_sheets - 3) < 0.0001, "Functional matter must be exactly conserved")
	TEST_ASSERT(abs(composite.liner_fraction * total_sheets - 2) < 0.0001, "Liner matter must be exactly conserved")
	TEST_ASSERT(abs(composite.jacket_fraction * total_sheets - 1) < 0.0001, "Jacket matter must be exactly conserved")
	TEST_ASSERT(abs(composite.core_fraction + composite.functional_fraction + composite.liner_fraction + composite.jacket_fraction - 1) < 0.0001, "Layer fractions must sum to one")

/datum/unit_test/dq_material_composite_remelt_conservation

/datum/unit_test/dq_material_composite_remelt_conservation/Run()
	var/composite_key = register_composite_material(MAT_COPPER, 7, MAT_LEAD, 3, MAT_GLASS, 2, MAT_PLASTIC, 1)
	var/obj/item/stack/material/composite/stock = new(run_loc_floor_bottom_left, 13, composite_key)
	var/datum/material_batch/reclaimed = new
	for(var/index in 1 to 13)
		TEST_ASSERT(material_batch_absorb_sheet(reclaimed, stock), "Every physical composite sheet must be reclaimable")
	TEST_ASSERT(abs(reclaimed.composition[MAT_COPPER] - 7) < 0.0001, "Remelting must recover every copper sheet without rounding loss")
	TEST_ASSERT(abs(reclaimed.composition[MAT_LEAD] - 3) < 0.0001, "Remelting must recover every lead sheet without rounding loss")
	TEST_ASSERT(abs(reclaimed.composition[MAT_GLASS] - 2) < 0.0001, "Remelting must recover every glass sheet without rounding loss")
	TEST_ASSERT(abs(reclaimed.composition[MAT_PLASTIC] - 1) < 0.0001, "Remelting must recover every plastic sheet without rounding loss")
	TEST_ASSERT(abs(reclaimed.amount - 13) < 0.0001, "Reclamation must conserve the total physical sheet count")
	qdel(stock)
	qdel(reclaimed)

/datum/unit_test/dq_material_effect_unification

/datum/unit_test/dq_material_effect_unification/Run()
	var/datum/substance/impact = new
	impact.name = "impact test response"
	impact.family = SUBFAM_DISCHARGE
	impact.trigger = SUB_TRIG_IMPACT
	impact.energy = 60
	impact.purity = 90
	var/datum/substance/heat = new
	heat.name = "heat test response"
	heat.family = SUBFAM_THERMAL
	heat.trigger = SUB_TRIG_HEAT
	heat.energy = 55
	heat.purity = 88
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 4)
	batch.add_material_effect(impact)
	batch.add_material_effect(heat)
	batch.recalculate()
	var/material_key = register_processed_material(batch)
	var/datum/material/material = get_material_by_name(material_key)
	TEST_ASSERT_EQUAL(length(material.material_effects), 2, "A processed alloy must preserve every triggered material response")
	var/composite_key = register_composite_material(material_key, 4, MAT_COPPER, 1, MAT_GLASS, 1, MAT_PLASTIC, 1)
	var/datum/material/composite/composite = get_material_by_name(composite_key)
	TEST_ASSERT_EQUAL(length(composite.material_effects), 2, "Layering must preserve all effects through the canonical material response architecture")
	var/obj/item/material/knife/knife = new(run_loc_floor_bottom_left)
	knife.set_material(composite.name)
	TEST_ASSERT_NOTNULL(knife.GetComponent(/datum/component/material_response), "An effected material form must use the shared material response component")
	qdel(knife)
	qdel(batch)
	qdel(heat)
	qdel(impact)

/datum/unit_test/dq_material_stock_part_designs

/datum/unit_test/dq_material_stock_part_designs/Run()
	var/datum/design_techweb/material_stock_part/capacitor/design = new
	var/obj/item/stock_parts/capacitor/part = design.create_item(run_loc_floor_bottom_left, MAT_COPPER)
	TEST_ASSERT_NOTNULL(part, "The material-selectable stock-part family must create a physical part")
	TEST_ASSERT_EQUAL(part.material_id, MAT_COPPER, "The selected material identity must survive fabrication")
	TEST_ASSERT_EQUAL(part.rating, part.get_rating(), "The legacy rating field and material-derived rating must agree")
	qdel(part)

/datum/unit_test/dq_material_gas_sorption_conservation

/datum/unit_test/dq_material_gas_sorption_conservation/Run()
	var/datum/material/processed_alloy/sorbent = new
	sorbent.name = "unit_test_sorbent"
	sorbent.display_name = "test sorbent"
	sorbent.gas_sorption_capacity = 5
	GLOB.name_to_material[sorbent.name] = sorbent
	var/obj/machinery/atmospherics/pipe/pipe = locate() in world
	TEST_ASSERT_NOTNULL(pipe, "The focused map must contain a physical pipe for the sorption integration test")
	var/original_material_id = pipe.engineered_material_id
	pipe.engineered_material_id = sorbent.name
	pipe.material_last_exposure = world.time - 10
	var/datum/gas_mixture/test_gas = new(2500)
	test_gas.adjust_moles(/datum/gas/plasma, 10)
	test_gas.set_temperature(T0C + 200)
	var/initial_moles = test_gas.get_moles(/datum/gas/plasma)
	var/initial_energy = test_gas.thermal_energy()
	TEST_ASSERT(pipe.process_engineered_material_exposure(test_gas), "A sorbent liner must react to a real plasma atmosphere")
	TEST_ASSERT(pipe.material_sorbed_moles > 0, "Sorption must retain captured matter on the physical pipe")
	TEST_ASSERT(abs(test_gas.get_moles(/datum/gas/plasma) + pipe.material_sorbed_moles - initial_moles) < 0.0001, "Sorption must conserve plasma moles")
	TEST_ASSERT(abs(test_gas.thermal_energy() + pipe.material_sorbed_thermal_energy - initial_energy) < 0.01, "Sorption must conserve thermal energy")
	var/datum/gas_mixture/environment = new(2500)
	var/environment_plasma = environment.get_moles(/datum/gas/plasma)
	pipe.release_sorbed_material_gas(environment)
	TEST_ASSERT(abs(environment.get_moles(/datum/gas/plasma) - environment_plasma - (initial_moles - test_gas.get_moles(/datum/gas/plasma))) < 0.0001, "Dismantling must return captured gas to the world")
	TEST_ASSERT_EQUAL(pipe.material_sorbed_moles, 0, "Released gas must not remain duplicated in pipe storage")
	qdel(test_gas)
	qdel(environment)
	pipe.engineered_material_id = original_material_id
	GLOB.name_to_material -= sorbent.name
	qdel(sorbent)

/datum/unit_test/dq_substance_physical_source_rendering

/datum/unit_test/dq_substance_physical_source_rendering/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	TEST_ASSERT_NOTNULL(test_turf, "Physical source rendering requires a real world turf")
	var/obj/machinery/particle_smasher/focus = new(test_turf)
	var/obj/item/slime_extract/blue/extract = new(focus)
	focus.target = extract
	focus.energy = SUBSTANCE_REFINE_ENERGY
	TEST_ASSERT_EQUAL(substance_source_category(extract), "bio", "A real slime extract must be recognized as finite biological feedstock")
	var/obj/item/stack/material/substance/output = focus.try_substance_source_render()
	TEST_ASSERT(output, "Charged particle bombardment must destructively render a cultivated source")
	if(!output)
		qdel(focus)
		return
	TEST_ASSERT(istype(output, /obj/item/stack/material/substance), "Physical rendering returned the wrong item type instead of substance sheets")
	TEST_ASSERT_NULL(focus.target, "Rendering must consume the original source rather than duplicate it")
	TEST_ASSERT_EQUAL(get_turf(output), get_turf(focus), "Physical rendering must eject ordinary substance material sheets into the world")
	TEST_ASSERT(output.amount >= 2, "A cultivated source must produce a usable finite stack")
	qdel(output)
	qdel(focus)

/datum/unit_test/dq_material_cell_product_family

/datum/unit_test/dq_material_cell_product_family/Run()
	var/list/design_types = list(
		/datum/design_techweb/material_power_cell,
		/datum/design_techweb/material_power_cell/high,
		/datum/design_techweb/material_power_cell/device,
		/datum/design_techweb/material_power_cell/weapon,
		/datum/design_techweb/material_power_cell/mech,
	)
	for(var/design_type in design_types)
		var/datum/design_techweb/material_power_cell/design = new design_type
		var/obj/item/cell/cell = design.create_item(run_loc_floor_bottom_left, MAT_COPPER)
		TEST_ASSERT_NOTNULL(cell, "Every material cell geometry must fabricate a real compatible cell")
		TEST_ASSERT_EQUAL(cell.engineered_material_id, MAT_COPPER, "Every cell geometry must retain the selected canonical material")
		TEST_ASSERT_EQUAL(cell.engineered_material_profile, MATERIAL_APPLICATION_CELL, "Every cell geometry must receive functional electrical behavior")
		TEST_ASSERT(cell.maxcharge > 0 && cell.charge == cell.maxcharge, "A fabricated material cell must be immediately usable")
		qdel(cell)
