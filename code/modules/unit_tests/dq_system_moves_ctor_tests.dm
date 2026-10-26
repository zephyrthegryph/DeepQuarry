// The plant, xenoarch sampling and supply types made without New()/Initialize() overrides (migrate/unblock-system-moves).

/// A seed's traits come from default_traits(): the base defaults, then each subtype's own, in type order; growth stages follow the plant icon.
/datum/unit_test/dq_seed_default_traits/Run()
	test_driver_begin()
	var/datum/seed/apple/gold/S = new
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_MATURATION), 10, "the subtype's own trait wins over its parent's")
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_YIELD), 5, "a trait only the parent sets is kept")
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_REQUIRES_WATER), 1, "the base default is set")
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_PLANT_ICON), "tree2", "the plant icon comes from the parent")
	test_time(1 SECOND)
	var/expected = SSplants.plant_sprites?["tree2"]
	if(expected)
		TEST_ASSERT_EQUAL(S.growth_stages, expected, "growth stages are counted after the seed is made")
	qdel(S)
	test_driver_end()

/// A random seed packet rolls its own seed line when none was given, and holds it.
/datum/unit_test/dq_random_seed_packet_rolls/Run()
	var/obj/item/seeds/random/P = allocate(/obj/item/seeds/random, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(P.seed(), "the packet holds a seed")
	TEST_ASSERT_EQUAL(P.seed_type, P.seed().name, "its seed_type names the rolled seed")
	TEST_ASSERT(P.seed_type in SSplants.seeds, "the rolled line is registered")

/// geosample_of() samples a mine turf; a copy is a private equal sample.
/datum/unit_test/dq_geosample_of_turf/Run()
	var/datum/geosample/G = geosample_of(null)
	TEST_ASSERT_EQUAL(G.age, 0, "a sample of nothing is empty")
	G.age = 7
	var/datum/geosample/C = G.copy()
	TEST_ASSERT(C != G, "a copy is its own sample")
	TEST_ASSERT_EQUAL(C.age, 7, "and equal")
	qdel(C)
	qdel(G)
