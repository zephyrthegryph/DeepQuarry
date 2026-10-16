/datum/unit_test/dq_organ_species_cache_home
/datum/unit_test/dq_organ_species_cache_home/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/datum/organ_data/D = allocate(/datum/organ_data)
	TEST_ASSERT_NULL(D.vars["cached_species_vars"], "an unread organ snapshot does not allocate its fallback cache")
	TEST_ASSERT_NULL(D.get_species_name(), "a snapshot with no source or cached value returns null")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	D.setup_from_species(H.species)
	var/expected = H.species.name
	TEST_ASSERT_EQUAL(D.get_species_name(), expected, "the real getter reads its current species")
	var/list/cache = D.vars["cached_species_vars"]
	TEST_ASSERT_EQUAL(cache["name"], expected, "the actual read records its fallback")
	D.setup_from_species(null)
	TEST_ASSERT_EQUAL(D.get_species_name(), expected, "losing the species reference preserves the last observed value")
