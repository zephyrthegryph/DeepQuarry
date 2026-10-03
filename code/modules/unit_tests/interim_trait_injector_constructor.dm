/// Invalid abstract trait injectors refuse after parent initialization; real enabled/disabled constructors retain their gene record and owned cleanup.
/datum/unit_test/interim_trait_injector_constructor
	var/injector_type = /obj/item/dnainjector/set_trait/anxiety
	var/expected_value = 0xFFF
	var/expected_state = TRUE

/datum/unit_test/interim_trait_injector_constructor/disable
	injector_type = /obj/item/dnainjector/set_trait/anxiety/disable
	expected_value = 0x000
	expected_state = FALSE

/datum/unit_test/interim_trait_injector_constructor/Run()
	var/turf/T = test_floor()
	var/list/before = turf_contents_of_type(T, /obj/item/dnainjector/set_trait)
	var/obj/item/dnainjector/set_trait/refused = allocate(/obj/item/dnainjector/set_trait, T)
	TEST_ASSERT(QDELETED(refused), "The actual abstract missing-trait injector refuses its incomplete constructor")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/dnainjector/set_trait)), length(before), "Actual constructor refusal leaves no incomplete trait injector on the original floor")
	var/datum/gene/trait/gene = get_gene_from_trait(/datum/trait/negative/disability_nervousness)
	TEST_ASSERT(gene && gene.block > 0, "The actual canonical anxiety trait has a registered real gene block")
	var/obj/item/dnainjector/set_trait/injector = allocate(injector_type, T)
	TEST_ASSERT(injector && !QDELETED(injector), "The actual existing anxiety subtype completes ordinary construction")
	TEST_ASSERT(injector.flags & ATOM_INITIALIZED, "The actual valid injector chains complete parent initialization")
	TEST_ASSERT_EQUAL(injector.trait_path, /datum/trait/negative/disability_nervousness, "The actual anxiety subtype retains its original canonical trait")
	TEST_ASSERT_EQUAL(injector.block, gene.block, "The actual constructor selects the registered canonical anxiety gene block")
	TEST_ASSERT_EQUAL(injector.datatype, DNA2_BUF_SE, "The actual constructor retains the original structural-enzyme buffer kind")
	TEST_ASSERT_EQUAL(injector.value, expected_value, "The actual constructor retains its exact original enabled or disabled value")
	var/datum/dna2/record/record = injector.buf
	TEST_ASSERT(record && !QDELETED(record), "The actual parent constructor creates its real owned gene record")
	var/datum/dna/dna = record.dna
	TEST_ASSERT(dna && !QDELETED(dna), "The actual parent constructor creates the record's real owned DNA")
	TEST_ASSERT_EQUAL(record.types, DNA2_BUF_SE, "The actual parent record retains its structural-enzyme kind")
	TEST_ASSERT_EQUAL(injector.GetValue(), expected_value, "The actual parent buffer records the exact enabled or disabled value")
	TEST_ASSERT_EQUAL(injector.GetState(), expected_state, "The actual real buffer exposes its original enabled or disabled gene state")
	TEST_ASSERT_EQUAL(injector.loc, T, "The actual valid constructor preserves the original injector floor")
	qdel(injector)
	TEST_ASSERT(QDELETED(injector), "The original actual injector terminates on deletion")
	TEST_ASSERT(QDELETED(record), "Actual parent disposal deletes the original owned gene record")
	TEST_ASSERT(QDELETED(dna), "Actual parent disposal deletes the record's original owned DNA")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/dnainjector/set_trait)), length(before), "Actual parent disposal leaves no trait injector product on the original floor")
