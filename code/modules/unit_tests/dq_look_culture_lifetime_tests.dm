/// The real sampler retains only the culture's newly copied blood products.
/datum/unit_test/dq_look_culture_product_lifetime
/datum/unit_test/dq_look_culture_product_lifetime/Run()
	scope_strain_archive()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/datum/borrowed_donor = allocate(/datum)
	var/list/products = list()
	for(var/type in list(
		/obj/item/reagent_containers/glass/beaker/vial/culture/cold,
		/obj/item/reagent_containers/glass/beaker/vial/culture/flu,
		/obj/item/reagent_containers/glass/beaker/vial/culture/blobspores,
		/obj/item/reagent_containers/glass/beaker/vial/culture/macrophages))
		var/obj/item/reagent_containers/glass/beaker/vial/culture/vial = dq_look_allocate(type, test_floor())
		own(vial)
		TEST_ASSERT_EQUAL(length(vial.diseases), 1, "Actual culture owns one source template")
		var/datum/affliction/contagion/template = vial.diseases[1]
		var/datum/reagent/blood/blood = vial.reagents.get_reagent(REAGENT_ID_BLOOD)
		TEST_ASSERT(istype(blood), "The real culture has blood")
		blood.data["donor"] = borrowed_donor
		var/list/strains = blood.data["viruses"]
		TEST_ASSERT_EQUAL(length(strains), 1, "Blood holds one copied strain")
		var/datum/affliction/contagion/strain = strains[1]
		TEST_ASSERT(strain != template && strain.type == template.type, "Fixture retained the actual distinct subtype copy")
		TEST_ASSERT(strain in allocated, "Sampler registers the exact born blood product for cleanup")
		TEST_ASSERT(!(template in allocated), "Sampler does not steal the vial-owned template")
		products += strain
		qdel(vial)
		TEST_ASSERT(QDELETED(template), "Real vial ownership deletes its own template")
		// A future production ownership repair may delete this already; cleanup is idempotent.
	// Keep the unrelated borrowed datum outside this fixture's deletion batch,
	// then immediately return it to cleanup ownership before any assertion.
	rel_remove(src, nameof(allocated), borrowed_donor)
	end_test_world()
	own(borrowed_donor)
	for(var/datum/affliction/contagion/strain as anything in products)
		TEST_ASSERT(QDELETED(strain), "Fixture teardown deletes its exact culture product and subscriptions")
	TEST_ASSERT(!QDELETED(borrowed_donor), "Cleanup never traverses/deletes non-codec borrowed donor metadata")
