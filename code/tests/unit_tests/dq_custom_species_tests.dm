/// A character's custom species name: the preference writes it into the mob's identity record, the DNA copy carries it, and the examine name
/// ender, the tooltip species and the ID card show it in place of the species name.
/datum/unit_test/dq_custom_species/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(H.bio.custom_species, "a new human has no custom species")
	var/datum/preference/pref = GLOB.preference_entries[/datum/preference/text/human/custom_species]
	TEST_ASSERT_NOTNULL(pref, "the custom species preference exists")
	pref.apply_to_human(H, "Fluffbeast")
	TEST_ASSERT_EQUAL(H.bio.custom_species, "Fluffbeast", "applying the preference writes the identity record")
	TEST_ASSERT_EQUAL(H.get_display_species(), "Fluffbeast", "the tooltip species is the custom name")
	TEST_ASSERT(findtext(H.examine_name_ender(NONE, NONE, FALSE), "Fluffbeast"), "the examine name ender shows the custom name")
	var/datum/dna/copy = new
	copy.ResetUIFrom(H)
	TEST_ASSERT_EQUAL(copy.custom_species, "Fluffbeast", "the DNA copy carries the custom name")
	var/mob/living/carbon/human/clone = allocate(/mob/living/carbon/human, T)
	copy.ApplyToMob(clone)
	TEST_ASSERT_EQUAL(clone.bio.custom_species, "Fluffbeast", "applying the DNA writes the clone's identity record")
	pref.apply_to_human(H, null)
	TEST_ASSERT(!H.bio.custom_species, "a cleared preference clears the record")
