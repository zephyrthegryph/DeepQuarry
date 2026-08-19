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
	var/obj/machinery/material_processor/tester/tester = new(run_loc_floor_bottom_left)
	tester.batch = new
	tester.batch.add_material(MAT_STEEL, 4, null, 92, "TESTLOT")
	TEST_ASSERT(tester.run_material_test(MATERIAL_TEST_SPECTROMETRY, null), "Spectrometry must run non-destructively")
	TEST_ASSERT(tester.run_material_test(MATERIAL_TEST_MICROSCOPY, null), "Microscopy must expose structure")
	TEST_ASSERT(tester.run_material_test(MATERIAL_TEST_HARDNESS, null), "Hardness testing must expose hardness")
	TEST_ASSERT(tester.run_material_test(MATERIAL_TEST_CONDUCTIVITY, null), "Conductivity testing must expose conductivity")
	TEST_ASSERT(tester.run_material_test(MATERIAL_TEST_TENSILE, null), "A spare coupon must support destructive tensile testing")
	TEST_ASSERT(tester.run_material_test(MATERIAL_TEST_CORROSION, null), "A second coupon must support destructive corrosion testing")
	TEST_ASSERT_EQUAL(tester.batch.amount, 2, "Two destructive tests must consume exactly two sheets")
	TEST_ASSERT_EQUAL(length(tester.batch.test_results), 6, "Each test must reveal only its own tracked result")
	qdel(tester)

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

/datum/unit_test/dq_material_science_forms

/datum/unit_test/dq_material_science_forms/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 2, null, 95, "FORMLOT")
	batch.form = "sheet"
	TEST_ASSERT(batch.form_compatible(MATERIAL_FORM_PLATE), "Sheet stock must satisfy plate applications")
	TEST_ASSERT(!batch.form_compatible(MATERIAL_FORM_WIRE), "Sheet stock must not silently substitute for drawn wire")
	batch.form = "wire stock"
	TEST_ASSERT(batch.form_compatible(MATERIAL_FORM_WIRE), "Drawn stock must satisfy conductor applications")
	TEST_ASSERT(!batch.form_compatible(MATERIAL_FORM_FORGED), "Drawn stock must not silently substitute for forged stock")
	batch.form = "forged billet"
	TEST_ASSERT(batch.form_compatible(MATERIAL_FORM_FORGED), "A forged billet must satisfy forged applications")
	TEST_ASSERT(batch.form_compatible(MATERIAL_FORM_PRECISION), "A forged billet must be valid precision feedstock")
	qdel(batch)

/datum/unit_test/dq_material_science_applications

/datum/unit_test/dq_material_science_applications/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 2, null, 98, "APPLICATIONLOT")
	batch.add_material(MAT_COPPER, 1, null, 98, "APPLICATIONLOT")
	batch.form = "forged billet"
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

	batch.form = "wire stock"
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

/datum/unit_test/dq_material_capability_derivation

/datum/unit_test/dq_material_capability_derivation/Run()
	var/datum/material_batch/electrical_batch = new
	electrical_batch.composition = list(MAT_QUARTZ = 1, MAT_METALHYDROGEN = 1, MAT_URANIUM = 1, MAT_IRON = 1)
	electrical_batch.impurities = list("thermal phase catalyst" = 4, "cryogenic stabilizer" = 3, "conductive dopant" = 4)
	electrical_batch.conductivity = 95
	electrical_batch.heat_resistance = 90
	electrical_batch.homogeneity = 95
	electrical_batch.purity = 98
	electrical_batch.corrosion_resistance = 80
	electrical_batch.hardness = 80
	electrical_batch.toughness = 80
	electrical_batch.structure[MATERIAL_STRUCTURE_HARDENED] = 30
	var/datum/material/processed_alloy/electrical = new
	electrical.batch_template = electrical_batch
	electrical.reflectivity = 0.7
	electrical.radioactivity = 80
	electrical.derive_material_capabilities()
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_THERMOELECTRIC), "Thermal catalyst and conductive structure must create thermoelectric behavior")
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_PIEZOELECTRIC), "A homogeneous electroactive crystal must create piezoelectric behavior")
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_ELECTROGENIC), "A yellow-slime conductive dopant must create a self-charging electrogenic matrix")
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_SUPERCONDUCTING), "Pure cryogenic conductor stock must create superconducting behavior")
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_RADIOVOLTAIC), "A conductive radioisotope lattice must create radiovoltaic behavior")
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_SCINTILLATING), "A homogeneous radioactive crystal must scintillate")
	TEST_ASSERT(electrical.has_material_capability(MATERIAL_CAP_MAGNETOSTRICTIVE), "A hardened conductive ferrous lattice must be magnetostrictive")

	var/datum/material_batch/medical_batch = new
	medical_batch.composition = list(MAT_BIOMASS = 1, MAT_MORPHIUM = 1, MAT_IRON = 1, MAT_SILVER = 1, MAT_PLATINUM = 1)
	medical_batch.purity = 95
	medical_batch.corrosion_resistance = 90
	medical_batch.homogeneity = 90
	medical_batch.toughness = 85
	medical_batch.surface_protection = 15
	medical_batch.structure[MATERIAL_STRUCTURE_AMORPHOUS] = 30
	var/datum/material/processed_alloy/medical = new
	medical.batch_template = medical_batch
	medical.derive_material_capabilities()
	TEST_ASSERT(medical.has_material_capability(MATERIAL_CAP_CATALYTIC), "Protected precious-metal surfaces must be catalytic")
	TEST_ASSERT(medical.has_material_capability(MATERIAL_CAP_ANTIMICROBIAL), "Corrosion-resistant silver stock must be antimicrobial")
	TEST_ASSERT(medical.has_material_capability(MATERIAL_CAP_HEMOSTATIC), "Biological ferrous interfaces must be hemostatic")
	TEST_ASSERT(medical.has_material_capability(MATERIAL_CAP_BIOMIMETIC), "Amorphous biological morphium must be biomimetic")
	TEST_ASSERT(medical.has_material_capability(MATERIAL_CAP_SHAPE_MEMORY), "Tough morphium stock must retain shape memory")

	var/datum/material_batch/structural_batch = new
	structural_batch.composition = list(MAT_PLASTEEL = 1, MAT_TITANIUM = 1, MAT_ALUMINIUM = 1, MAT_GRAPHITE = 1, MAT_GLASS = 1)
	structural_batch.impurities = list("thermal phase catalyst" = 4, "bluespace homogenizer" = 3)
	structural_batch.porosity = 30
	structural_batch.corrosion_resistance = 85
	structural_batch.homogeneity = 95
	structural_batch.heat_resistance = 90
	structural_batch.toughness = 85
	structural_batch.hardness = 85
	structural_batch.conductivity = 60
	structural_batch.structure[MATERIAL_STRUCTURE_PRECIPITATE] = 30
	structural_batch.structure[MATERIAL_STRUCTURE_HARDENED] = 30
	var/datum/substance/resonance = new
	resonance.family = SUBFAM_FIELD
	resonance.affinity = 90
	structural_batch.infused_substance = resonance
	var/datum/material/processed_alloy/structural = new
	structural.batch_template = structural_batch
	structural.reflectivity = 0.8
	structural.derive_material_capabilities()
	TEST_ASSERT(structural.has_material_capability(MATERIAL_CAP_REACTIVE_ARMOR), "Precipitation-hardened plasteel must create reactive armor behavior")
	TEST_ASSERT(structural.has_material_capability(MATERIAL_CAP_PHASE_CHANGE), "A heat-resistant thermal catalyst must create phase-change behavior")
	TEST_ASSERT(structural.has_material_capability(MATERIAL_CAP_GAS_GETTER), "Porous titanium or aluminium must create a gas getter")
	TEST_ASSERT(structural.has_material_capability(MATERIAL_CAP_POROUS_REAGENT), "A corrosion-resistant porous lattice must hold reagents")
	TEST_ASSERT(structural.has_material_capability(MATERIAL_CAP_OPTICAL), "A homogeneous reflective glass lattice must become an optical metamaterial")
	TEST_ASSERT(structural.has_material_capability(MATERIAL_CAP_RESONANT), "A bluespace-homogenized infusion must retain a resonant signature")

	qdel(structural)
	qdel(medical)
	qdel(electrical)

/datum/unit_test/dq_material_capability_runtime

/datum/unit_test/dq_material_capability_runtime/Run()
	var/datum/material/processed_alloy/material = new
	material.name = "unit_test_capability_material"
	material.display_name = "capability test alloy"
	material.icon_colour = "#88ccff"
	material.batch_template = new
	material.batch_template.form = "wire stock"
	material.material_capabilities = list(
		MATERIAL_CAP_PIEZOELECTRIC = 90,
		MATERIAL_CAP_SUPERCONDUCTING = 90,
		MATERIAL_CAP_RADIOVOLTAIC = 80,
		MATERIAL_CAP_ELECTROGENIC = 80,
	)
	GLOB.name_to_material[material.name] = material
	var/obj/item/cell/cell = new(run_loc_floor_bottom_left)
	var/turf/cell_turf = get_turf(run_loc_floor_bottom_left)
	if(!cell_turf)
		cell_turf = locate(1, 1, 1)
	cell.forceMove(cell_turf)
	cell.apply_engineered_material(material, MATERIAL_APPLICATION_CELL)
	var/datum/component/material_capabilities/component = cell.GetComponent(/datum/component/material_capabilities)
	TEST_ASSERT(istype(component), "Manufacturing must install the generic capability component")
	TEST_ASSERT_EQUAL(component.capability(MATERIAL_CAP_PIEZOELECTRIC), 90, "The manufactured form must retain capability potency")
	TEST_ASSERT(!(component in SSobj.processing), "Stable capability items must never enter continuous SSobj processing")
	cell.charge = 0
	cell.material_capability_form_trigger(SUB_TRIG_IMPACT, get_turf(cell), cell)
	TEST_ASSERT(cell.charge > 0, "Piezoelectric forms must turn an impact into stored charge")
	var/after_first_impact = cell.charge
	cell.material_capability_form_trigger(SUB_TRIG_IMPACT, get_turf(cell), cell)
	TEST_ASSERT_EQUAL(cell.charge, after_first_impact, "Piezoelectric generation must be rate-limited")
	cell.charge = 0
	component.apply_radiation_energy(50)
	TEST_ASSERT(cell.charge > 0, "Radiovoltaic cells must generate charge from a radiation event")
	var/datum/gas_mixture/air = cell_turf.return_air()
	var/original_temperature = air.return_temperature()
	air.set_temperature(T0C - 20)
	TEST_ASSERT(cell.material_cell_use_cost(100) < 100, "A cold superconducting cell must spend less charge for the same load")
	air.set_temperature(original_temperature)
	qdel(cell)
	GLOB.name_to_material -= material.name
	qdel(material)

/datum/unit_test/dq_material_capability_form_gating

/datum/unit_test/dq_material_capability_form_gating/Run()
	var/datum/material/processed_alloy/material = new
	material.name = "unit_test_form_material"
	material.display_name = "form gate alloy"
	material.batch_template = new
	material.batch_template.form = "sheet"
	material.material_capabilities = list(
		MATERIAL_CAP_REACTIVE_ARMOR = 80,
		MATERIAL_CAP_ANTIMICROBIAL = 80,
		MATERIAL_CAP_ELECTROGENIC = 80,
		MATERIAL_CAP_PHASE_CHANGE = 80,
	)
	GLOB.name_to_material[material.name] = material
	var/obj/item/surgical/scalpel/scalpel = new(run_loc_floor_bottom_left)
	scalpel.apply_engineered_material(material, MATERIAL_APPLICATION_SURGICAL)
	var/datum/component/material_capabilities/scalpel_component = scalpel.GetComponent(/datum/component/material_capabilities)
	TEST_ASSERT(scalpel_component.capability(MATERIAL_CAP_ANTIMICROBIAL), "A surgical form must retain medical surface behavior")
	TEST_ASSERT(!scalpel_component.capability(MATERIAL_CAP_REACTIVE_ARMOR), "A scalpel must not inherit armor-only behavior")
	TEST_ASSERT(!scalpel_component.capability(MATERIAL_CAP_ELECTROGENIC), "A scalpel must not become a self-charging generator")
	var/obj/item/material/armor_plating/plate = new(run_loc_floor_bottom_left, material.name)
	var/datum/component/material_capabilities/plate_component = plate.GetComponent(/datum/component/material_capabilities)
	TEST_ASSERT(plate_component.capability(MATERIAL_CAP_REACTIVE_ARMOR), "Armor stock must retain reactive protection")
	TEST_ASSERT(plate_component.capability(MATERIAL_CAP_PHASE_CHANGE), "Armor stock must retain a structural heat reservoir")
	TEST_ASSERT(!plate_component.capability(MATERIAL_CAP_ANTIMICROBIAL), "Armor stock must not inherit surgery-only behavior")
	qdel(plate)
	qdel(scalpel)
	GLOB.name_to_material -= material.name
	qdel(material)

/datum/unit_test/dq_material_capability_conservation

/datum/unit_test/dq_material_capability_conservation/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left)
	if(!istype(test_turf, /turf/simulated/floor))
		test_turf = locate(/turf/simulated/floor) in world
	TEST_ASSERT_NOTNULL(test_turf, "Conservation testing requires a mutable simulated turf")
	var/datum/gas_mixture/air = test_turf.return_air()
	air.clear()
	air.adjust_moles(/datum/gas/oxygen, 20)
	air.adjust_moles(/datum/gas/nitrogen, 60)
	air.adjust_moles(/datum/gas/miasma, 2)
	air.adjust_moles(/datum/gas/plasma, 3)
	air.set_temperature(T0C + 200)
	var/datum/material/processed_alloy/material = new
	material.name = "unit_test_conservation_material"
	material.display_name = "conservation alloy"
	material.batch_template = new
	material.batch_template.form = "sintered stock"
	material.material_capabilities = list(
		MATERIAL_CAP_PHASE_CHANGE = 80,
		MATERIAL_CAP_GAS_GETTER = 80,
		MATERIAL_CAP_CATALYTIC = 80,
	)
	GLOB.name_to_material[material.name] = material
	var/obj/item/material/armor_plating/plate = new(test_turf, material.name)
	var/datum/component/material_capabilities/component = plate.GetComponent(/datum/component/material_capabilities)
	var/initial_energy = air.thermal_energy()
	var/absorbed = component.absorb_ambient_heat()
	TEST_ASSERT(absorbed > 0, "A hot atmosphere must charge a phase-change reservoir")
	TEST_ASSERT(abs((air.thermal_energy() + component.stored_phase_energy) - initial_energy) < 5, "Phase-change absorption must conserve thermal energy")
	component.release_stored_heat()
	TEST_ASSERT(abs(air.thermal_energy() - initial_energy) < 5, "Releasing a phase reservoir must return the stored thermal energy")
	var/initial_moles = air.total_moles()
	var/miasma_before = air.get_moles(/datum/gas/miasma)
	var/carbon_dioxide_before = air.get_moles(/datum/gas/carbon_dioxide)
	component.activate_catalyst(null)
	TEST_ASSERT(abs(air.total_moles() - initial_moles) < 0.001, "Catalysis must conserve total gas moles")
	TEST_ASSERT(air.get_moles(/datum/gas/miasma) < miasma_before && air.get_moles(/datum/gas/carbon_dioxide) > carbon_dioxide_before, "Catalysis must convert contamination into carbon dioxide")
	var/plasma_before = air.get_moles(/datum/gas/plasma)
	component.capture_hazardous_gas(null)
	TEST_ASSERT(air.get_moles(/datum/gas/plasma) < plasma_before && component.stored_gas_moles > 0, "A getter must move hazardous gas into finite storage")
	component.release_stored_gas()
	TEST_ASSERT(abs(air.get_moles(/datum/gas/plasma) - plasma_before) < 0.001, "Releasing a getter must return exactly the captured gas")
	qdel(plate)
	GLOB.name_to_material -= material.name
	qdel(material)

/datum/unit_test/dq_material_capability_discovery

/datum/unit_test/dq_material_capability_discovery/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_COPPER, 3, null, 98, "DISCOVERY")
	batch.add_additive("conductive dopant", 4)
	var/list/all_capabilities = batch.material_capability_preview(FALSE)
	TEST_ASSERT(length(all_capabilities) > 0, "A reachable doped conductor must contain a latent capability")
	TEST_ASSERT_EQUAL(length(batch.material_capability_preview(TRUE)), 0, "Untested capability behavior must remain unqualified")
	batch.test_results[MATERIAL_TEST_CONDUCTIVITY] = batch.conductivity
	batch.test_results[MATERIAL_TEST_SPECTROMETRY] = batch.purity
	TEST_ASSERT(length(batch.material_capability_preview(TRUE)) > 0, "Relevant physical tests must reveal the latent capability")
	qdel(batch)

/datum/unit_test/dq_material_capability_reachable_routes

/datum/unit_test/dq_material_capability_reachable_routes/Run()
	var/datum/material_batch/conductor = new
	TEST_ASSERT(conductor.add_material(MAT_COPPER, 3, null, 98, "ROUTE"), "Copper feedstock must enter the normal batch route")
	TEST_ASSERT(conductor.add_additive("conductive dopant", 4), "The normal additive route must accept conductive dopant")
	var/list/conductor_caps = conductor.material_capability_preview(FALSE)
	var/found_electrical = FALSE
	for(var/list/capability in conductor_caps)
		if(capability["id"] in list(MATERIAL_CAP_ELECTROGENIC, MATERIAL_CAP_PIEZOELECTRIC, MATERIAL_CAP_THERMOELECTRIC))
			found_electrical = TRUE
			break
	TEST_ASSERT(found_electrical, "A player-reachable doped conductor must develop an electrical capability")
	var/datum/material_batch/getter = new
	TEST_ASSERT(getter.add_material(MAT_TITANIUM, 3, null, 98, "ROUTE"), "Titanium feedstock must enter the normal batch route")
	TEST_ASSERT(getter.apply_process(MATERIAL_PROCESS_PULVERIZE), "The normal process route must produce porous powder")
	var/found_getter = FALSE
	for(var/list/capability in getter.material_capability_preview(FALSE))
		if(capability["id"] == MATERIAL_CAP_GAS_GETTER)
			found_getter = TRUE
			break
	TEST_ASSERT(found_getter, "Player-reachable porous titanium must develop gas-getter behavior")
	qdel(getter)
	qdel(conductor)

/datum/unit_test/dq_material_capability_medical_runtime

/datum/unit_test/dq_material_capability_medical_runtime/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left)
	if(!istype(test_turf, /turf/simulated/floor))
		test_turf = locate(/turf/simulated/floor) in world
	TEST_ASSERT_NOTNULL(test_turf, "Medical capability testing requires a valid turf")
	var/datum/material/processed_alloy/material = new
	material.name = "unit_test_medical_capability_material"
	material.display_name = "medical capability alloy"
	material.batch_template = new
	material.batch_template.form = "surgical stock"
	material.material_capabilities = list(MATERIAL_CAP_ANTIMICROBIAL = 80, MATERIAL_CAP_BIOMIMETIC = 80)
	GLOB.name_to_material[material.name] = material
	var/obj/item/surgical/scalpel/scalpel = new(test_turf)
	scalpel.apply_engineered_material(material, MATERIAL_APPLICATION_SURGICAL)
	var/mob/living/carbon/human/patient = new(test_turf)
	var/obj/item/organ/external/affected = patient.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(affected, "A generated patient must have a torso organ")
	affected.germ_level = 200
	patient.germ_level = 100
	affected.brute_dam = 20
	SEND_SIGNAL(scalpel, COMSIG_MATERIAL_SURGERY, patient, BP_TORSO, TRUE)
	TEST_ASSERT(affected.germ_level < 200 && patient.germ_level < 100, "An antimicrobial surgical form must sanitize both patient and site")
	TEST_ASSERT(affected.brute_dam < 20, "A biomimetic surgical form must repair real organ damage")
	qdel(patient)
	qdel(scalpel)
	GLOB.name_to_material -= material.name
	qdel(material)
