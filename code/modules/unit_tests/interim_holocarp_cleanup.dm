/// Actual holographic carp disappear through both real death and gib entry points.
/datum/unit_test/interim_holocarp_cleanup
	var/gibbed = FALSE

/datum/unit_test/interim_holocarp_cleanup/gibbed
	gibbed = TRUE

/datum/unit_test/interim_holocarp_cleanup/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/simple_mob/animal/space/carp/holodeck/hologram = allocate(/mob/living/simple_mob/animal/space/carp/holodeck, T)
	TEST_ASSERT(!QDELETED(hologram), "actual holographic carp initializes alive")
	TEST_ASSERT_EQUAL(hologram.stat, CONSCIOUS, "actual holographic carp starts conscious")
	TEST_ASSERT_EQUAL(hologram.meat_amount, 0, "actual hologram has no physical meat yield")
	TEST_ASSERT_NULL(hologram.icon_gib, "actual hologram has no physical gib icon")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/reagent_containers/food/snacks/meat)), 0, "real hologram destination starts without meat products")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/decal/cleanable/blood/gibs)), 0, "real hologram destination starts without physical gib decals")
	if(gibbed)
		hologram.gib()
	else
		hologram.death()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(hologram), "actual holographic death or gibbing consumes the original hologram")
	TEST_ASSERT_EQUAL(length(contents_of(T, /mob/living/simple_mob/animal/space/carp/holodeck)), 0, "actual cleanup leaves no holographic carp corpse")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/reagent_containers/food/snacks/meat)), 0, "actual holographic cleanup creates no physical meat")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/decal/cleanable/blood/gibs)), 0, "actual holographic cleanup creates no physical gib decals")
	var/mob/living/simple_mob/animal/space/carp/ordinary = allocate(/mob/living/simple_mob/animal/space/carp, T)
	TEST_ASSERT_EQUAL(ordinary.stat, CONSCIOUS, "real ordinary carp starts alive before the death control")
	ordinary.death()
	TEST_ASSERT(!QDELETED(ordinary), "ordinary actual carp death preserves its physical corpse")
	TEST_ASSERT_EQUAL(ordinary.stat, DEAD, "ordinary actual death marks its physical corpse dead")
	TEST_ASSERT_EQUAL(ordinary.loc, T, "ordinary real corpse remains on its original floor")
