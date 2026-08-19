/datum/unit_test/dq_material_science_process_chain

/datum/unit_test/dq_material_science_process_chain/Run()
	var/datum/material_batch/batch = new
	TEST_ASSERT(batch.add_material(MAT_STEEL, 2), "Steel must load into a batch")
	TEST_ASSERT(batch.add_material(MAT_COPPER, 1), "Copper must alloy into the same batch")
	TEST_ASSERT_EQUAL(batch.amount, 3, "Material conservation failed")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_MELT), "The feedstock must melt")
	TEST_ASSERT_EQUAL(batch.phase, MATERIAL_PHASE_MOLTEN, "Melt did not change phase")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_CAST), "Molten stock must cast")
	var/cast_porosity = batch.porosity
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_FORGE), "Cast stock must forge")
	TEST_ASSERT(batch.porosity < cast_porosity, "Forging must close porosity")
	var/pre_quench_hardness = batch.hardness
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_QUENCH), "Stock must quench")
	TEST_ASSERT(batch.hardness >= pre_quench_hardness, "Quenching must not soften the material")
	var/quench_stress = batch.internal_stress
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_TEMPER), "Quenched stock must temper")
	TEST_ASSERT(batch.internal_stress < quench_stress, "Tempering must relieve quench stress")
	qdel(batch)

/datum/unit_test/dq_material_science_registration

/datum/unit_test/dq_material_science_registration/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 3)
	batch.add_material(MAT_SILVER, 1)
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
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_ELECTROLYZE), "Electrolysis must process an impure batch")
	TEST_ASSERT(batch.purity > start_purity - 4, "Electrolysis must recover purity")
	TEST_ASSERT_EQUAL(length(batch.impurities), 0, "Electrolysis must separate tracked impurities")
	qdel(batch)
