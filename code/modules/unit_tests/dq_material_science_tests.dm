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
