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

/// Regression test for the admin trait editor (modify_traits.dm) reading the real
/// trait storage (_status_traits) instead of the removed dead `status_traits` var.
/datum/unit_test/admin_trait_listing_sees_added_trait

/datum/unit_test/admin_trait_listing_sees_added_trait/Run()
	var/datum/D = new()
	var/test_trait
	for(var/traitpath in GLOB.all_traits)
		test_trait = traitpath
		break
	TEST_ASSERT(test_trait, "No traits registered to test with.")

	ADD_TRAIT(D, test_trait, "admin_trait_listing_test")

	// This mirrors what /datum/admins/proc/modify_traits does when listing traits
	// to remove: iterate D._status_traits. Before the fix this iterated the dead
	// `status_traits` var and always saw nothing.
	var/found = FALSE
	for(var/trait in D._status_traits)
		if(trait == test_trait)
			found = TRUE
			break
	TEST_ASSERT(found, "Admin trait listing (D._status_traits) did not see the trait added via ADD_TRAIT.")

	var/list/sources = GET_TRAIT_SOURCES(D, test_trait)
	TEST_ASSERT(length(sources), "GET_TRAIT_SOURCES did not return the source list for the added trait.")

	REMOVE_TRAIT(D, test_trait, "admin_trait_listing_test")
	qdel(D)
