/// Test that all traits have unique names
/datum/unit_test/all_traits_unique_names

/datum/unit_test/all_traits_unique_names/Run()
	var/list/used_named = list()
	for(var/traitpath in GLOB.all_traits)
		var/datum/trait/T = GLOB.all_traits[traitpath]
		TEST_ASSERT(!(T.name in used_named), "[T.type]: Trait - The name \"[T.name]\" is already in use.")
		used_named.Add(T.name)

/// Test that autohiss traits shall be excluse
/datum/unit_test/autohiss_shall_be_exclusive

/datum/unit_test/autohiss_shall_be_exclusive/Run()
	var/list/hiss_list = list()
	for(var/traitpath in GLOB.all_traits)
		var/datum/trait/T = GLOB.all_traits[traitpath]
		if(!T.var_changes)
			continue
		if(!islist(T.var_changes["autohiss_basic_map"]))
			continue
		hiss_list += T

	for(var/datum/trait/T in hiss_list)
		TEST_ASSERT(!(T.type in T.excludes), "[T.type]: Trait - Autohiss excludes itself.")
		TEST_ASSERT(T.excludes, "[T.type]: Trait - Autohiss missing exclusion list.")

		if(!T.excludes)
			continue

		var/list/exempt_list = hiss_list.Copy() - T // MUST exclude all others except itself
		for(var/datum/trait/EX in exempt_list)
			TEST_ASSERT(EX.type in T.excludes, "[T.type]: Trait - Autohiss missing exclusion for [EX].")

/// The admin trait editor (modify_traits.dm) lists what a datum holds through trait_list(),
/// and traits are grants: held per source, released per source.
/datum/unit_test/admin_trait_listing_sees_added_trait

/datum/unit_test/admin_trait_listing_sees_added_trait/Run()
	var/datum/D = new()
	var/test_trait
	for(var/traitpath in GLOB.all_traits)
		test_trait = traitpath
		break
	TEST_ASSERT(test_trait, "No traits registered to test with.")

	add_trait(D, test_trait, "admin_trait_listing_test")
	TEST_ASSERT(has_trait(D, test_trait), "add_trait() did not grant the trait.")
	TEST_ASSERT(test_trait in trait_list(D), "trait_list() (the admin listing) did not see the granted trait.")
	TEST_ASSERT_EQUAL(length(trait_sources(D, test_trait)), 1, "trait_sources() should list the one source.")
	TEST_ASSERT(has_trait_from(D, test_trait, "admin_trait_listing_test"), "has_trait_from() did not see the text source.")

	remove_trait(D, test_trait, "admin_trait_listing_test")
	TEST_ASSERT(!has_trait(D, test_trait), "remove_trait() did not release the grant.")
	qdel(D)

/// Traits held by two sources stay until both release; a datum source releases on deletion;
/// ROUNDSTART_TRAIT survives a sourceless remove.
/datum/unit_test/trait_grants_per_source

/datum/unit_test/trait_grants_per_source/Run()
	var/datum/D = new()
	var/datum/source = new()
	var/test_trait = TRAIT_UNLUCKY
	add_trait(D, test_trait, source)
	add_trait(D, test_trait, JOB_TRAIT)
	remove_trait(D, test_trait, JOB_TRAIT)
	TEST_ASSERT(has_trait(D, test_trait), "a trait with another source left must stay")
	qdel(source)
	TEST_ASSERT(!has_trait(D, test_trait), "deleting a datum source must release its grant")
	add_trait(D, test_trait, ROUNDSTART_TRAIT)
	add_trait(D, test_trait, JOB_TRAIT)
	remove_trait(D, test_trait)
	TEST_ASSERT(has_trait_from(D, test_trait, ROUNDSTART_TRAIT), "a sourceless remove keeps ROUNDSTART_TRAIT")
	TEST_ASSERT(!has_trait_from(D, test_trait, JOB_TRAIT), "a sourceless remove releases the rest")
	remove_traits_in(D, ROUNDSTART_TRAIT)
	TEST_ASSERT(!has_trait(D, test_trait), "remove_traits_in() releases a source's traits")
	qdel(D)
