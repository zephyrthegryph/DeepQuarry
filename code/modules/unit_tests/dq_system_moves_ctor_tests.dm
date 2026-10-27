// The plant, xenoarch sampling and supply types made without New()/Initialize() overrides (migrate/unblock-system-moves).

/// A seed's traits come from default_traits(): the base defaults, then each subtype's own, in type order; growth stages follow the plant icon,
/// counted by the seed's after_init() when make() returns (it was an after() half a second later; a bare new never counts them).
/datum/unit_test/dq_seed_default_traits/Run()
	SSplants.ready()
	var/datum/seed/apple/gold/S = make(/datum/seed/apple/gold)
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_MATURATION), 10, "the subtype's own trait wins over its parent's")
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_POTENCY), 10, "a trait only the parent sets is kept")
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_REQUIRES_WATER), 1, "the base default is set")
	TEST_ASSERT_EQUAL(S.get_trait(TRAIT_PLANT_ICON), "tree2", "the plant icon comes from the parent")
	var/expected = SSplants.plant_sprites?["tree2"]
	TEST_ASSERT(expected > 0, "the plant sprites are built")
	TEST_ASSERT_EQUAL(S.growth_stages, expected, "growth stages are counted when make() returns")
	var/datum/seed/filed = SSplants.seeds[PLANT_APPLE]
	TEST_ASSERT_EQUAL(filed?.growth_stages, expected, "the boot seeds (made by make()) count theirs too")
	var/datum/seed/copy = S.copy_line()
	TEST_ASSERT_EQUAL(copy.growth_stages, expected, "a copied line keeps them")
	qdel(copy)
	qdel(S)

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
