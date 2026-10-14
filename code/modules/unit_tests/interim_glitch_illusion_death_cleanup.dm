/// These fixture descendants configure the existing respawn probability without overriding any behavior.
/mob/living/simple_mob/glitch_boss_fake/interim_no_respawn
	prob_respawn = 0

/mob/living/simple_mob/glitch_boss_fake/strong/interim_always_respawn
	prob_respawn = 100

/datum/unit_test/interim_glitch_illusion_death_cleanup
	var/source_type = /mob/living/simple_mob/glitch_boss_fake/interim_no_respawn
	var/expected_respawns = 0

/datum/unit_test/interim_glitch_illusion_death_cleanup/respawn
	source_type = /mob/living/simple_mob/glitch_boss_fake/strong/interim_always_respawn
	expected_respawns = 1

/datum/unit_test/interim_glitch_illusion_death_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/simple_mob/glitch_boss_fake/source = allocate(source_type, T)
	var/mob/living/simple_mob/glitch_boss_fake/control = allocate(/mob/living/simple_mob/glitch_boss_fake, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(source.type, source_type, "the actual fixture constructor produces its configured probability variant")
	TEST_ASSERT_EQUAL(source.prob_respawn, expected_respawns ? 100 : 0, "the real fixture data deterministically selects the existing respawn branch")
	TEST_ASSERT_EQUAL(source.stat, CONSCIOUS, "the actual original illusion starts conscious")
	var/list/before_mobs = contents_of(T, /mob/living/simple_mob/glitch_boss_fake)
	var/list/before_visuals = contents_of(T, /obj/effect/temp_visual/glitch)
	TEST_ASSERT_EQUAL(source.death(FALSE), FALSE, "actual illusion death takes the unchanged replacement-death pipeline")
	own_turf_contents(T)
	var/list/products = contents_of(T, /mob/living/simple_mob/glitch_boss_fake) - before_mobs
	var/list/visuals = contents_of(T, /obj/effect/temp_visual/glitch) - before_visuals
	TEST_ASSERT(QDELETED(source), "actual replacement death consumes the exact original illusion")
	TEST_ASSERT_EQUAL(length(products), expected_respawns, "actual configured death creates exactly the expected number of real replacement illusions")
	var/mob/living/simple_mob/glitch_boss_fake/product
	if(expected_respawns)
		product = products[1]
		TEST_ASSERT_EQUAL(product.type, /mob/living/simple_mob/glitch_boss_fake, "real respawn produces the canonical base illusion rather than inheriting the configured strong fixture")
		TEST_ASSERT_EQUAL(product.prob_respawn, 15, "the actual canonical replacement retains its original fifteen-percent respawn data")
		TEST_ASSERT_EQUAL(product.stat, CONSCIOUS, "the actual replacement is a living conscious mob")
		TEST_ASSERT_EQUAL(product.loc, T, "the real replacement remains at its original creation floor")
		TEST_ASSERT(!QDELETED(product), "original illusion deletion preserves the actual replacement identity")
	TEST_ASSERT_EQUAL(length(visuals), 1, "actual replacement death creates exactly one real glitch visual")
	var/obj/effect/temp_visual/glitch/visual = visuals[1]
	TEST_ASSERT_EQUAL(visual.type, /obj/effect/temp_visual/glitch, "actual replacement death creates the exact canonical glitch visual")
	TEST_ASSERT_EQUAL(visual.loc, T, "actual replacement death places its real visual on the original floor")
	TEST_ASSERT(!QDELETED(visual), "the real visual survives deletion of its original source")
	test_time(0.4 SECONDS)
	TEST_ASSERT(!QDELETED(visual), "the exact real glitch visual survives before its actual half-second expiry")
	test_time(0.2 SECONDS)
	TEST_ASSERT(QDELETED(visual), "the original real glitch visual is deleted by its unchanged expiry timer")
	TEST_ASSERT(!QDELETED(control), "illusion replacement and visual expiry preserve the independent original control mob")
	TEST_ASSERT_EQUAL(control.stat, CONSCIOUS, "the independent original control mob stays conscious")
	TEST_ASSERT_EQUAL(control.loc, T, "the independent original control mob stays on its original floor")
	TEST_ASSERT(!QDELETED(pen), "illusion replacement and visual expiry preserve the exact original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "the original unrelated pen stays on its original floor")
	if(expected_respawns)
		TEST_ASSERT(!QDELETED(product), "real visual expiry preserves the exact original replacement mob")
