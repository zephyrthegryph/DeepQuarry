/// Actual custom teppi use their fixed palettes through real setup, including the juvenile variant.
/datum/unit_test/interim_teppi_palette_data/Run()
	var/static/list/cases = list(
		list(/mob/living/simple_mob/vore/alienanimals/teppi/cass, "#c69c85", "#eeb698", "#272523", "#612c08", "#272523", "2", "0", TRUE),
		list(/mob/living/simple_mob/vore/alienanimals/teppi/baby/cass, "#c69c85", "#eeb698", "#272523", "#612c08", "#272523", "2", "0", FALSE),
		list(/mob/living/simple_mob/vore/alienanimals/teppi/aronai, "#404040", "#222222", "#141414", "#9f522c", "#e16f2d", "13", "1", TRUE),
		list(/mob/living/simple_mob/vore/alienanimals/teppi/lira, "#fdfae9", "#ffffc0", "#ffc965", "#1d7fb7", "#f09ca9", "13", "0", TRUE),
	)
	for(var/list/entry as anything in cases)
		var/mob/living/simple_mob/vore/alienanimals/teppi/animal = allocate(entry[1])
		TEST_ASSERT(!QDELETED(animal), "actual custom teppi survives full parent initialization")
		TEST_ASSERT(animal.inherit_colors, "actual custom teppi disables random palette replacement")
		TEST_ASSERT_EQUAL(animal.teppi_adult, entry[9], "actual custom teppi retains its configured age")
		for(var/pass in 1 to 2)
			TEST_ASSERT_EQUAL(animal.color, entry[2], "actual initialized body color matches its original fixed palette")
			TEST_ASSERT_EQUAL(animal.marking_color, entry[3], "actual initialized marking color matches its original fixed palette")
			TEST_ASSERT_EQUAL(animal.horn_color, entry[4], "actual initialized horn color matches its original fixed palette")
			TEST_ASSERT_EQUAL(animal.eye_color, entry[5], "actual initialized eye color matches its original fixed palette")
			TEST_ASSERT_EQUAL(animal.skin_color, entry[6], "actual initialized skin color matches its original fixed palette")
			TEST_ASSERT_EQUAL(animal.marking_type, entry[7], "actual initialized markings match the original pattern")
			TEST_ASSERT_EQUAL(animal.horn_type, entry[8], "actual initialized horns match the original pattern")
			if(pass == 1)
				animal.teppi_setup()

/// Real parent-supplied constructor arguments override custom defaults before adult setup.
/datum/unit_test/interim_teppi_palette_inheritance/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/simple_mob/vore/alienanimals/teppi/aronai/mother = allocate(/mob/living/simple_mob/vore/alienanimals/teppi/aronai, T)
	var/mob/living/simple_mob/vore/alienanimals/teppi/aronai/father = allocate(/mob/living/simple_mob/vore/alienanimals/teppi/aronai, T)
	mother.set_nutrition(1000)
	father.set_nutrition(1000)
	var/mob/living/simple_mob/vore/alienanimals/teppi/cass/child = allocate(/mob/living/simple_mob/vore/alienanimals/teppi/cass, T, mother, father)
	TEST_ASSERT(!QDELETED(child), "actual parent-supplied custom teppi initializes alive")
	TEST_ASSERT(child.teppi_adult, "actual parent-supplied custom teppi retains its adult setup branch")
	TEST_ASSERT(child.inherit_colors, "actual breeding constructor selects inherited color setup")
	TEST_ASSERT_EQUAL(child.color, mother.color, "actual inherited body color overrides the distinct Cass default")
	TEST_ASSERT_EQUAL(child.marking_color, mother.marking_color, "actual inherited marking color overrides the distinct Cass default")
	TEST_ASSERT_EQUAL(child.horn_color, mother.horn_color, "actual inherited horn color overrides the distinct Cass default")
	TEST_ASSERT_EQUAL(child.eye_color, mother.eye_color, "actual inherited eye color overrides the distinct Cass default")
	TEST_ASSERT_EQUAL(child.skin_color, mother.skin_color, "actual inherited skin color overrides the distinct Cass default")
	TEST_ASSERT_EQUAL(mother.nutrition, 500, "actual constructor inheritance debits the mother's configured nutrition")
	TEST_ASSERT_EQUAL(father.nutrition, 750, "actual constructor inheritance debits the father's configured nutrition")
