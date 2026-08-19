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
