// A mob's species is PROTO (doc/rewrite/ownership.md sec 3): the registered singleton until
// produceCopy() makes a private copy the mob owns. Re-applying traits (the preferences preview does
// it on every change) replaces the private copy, which proto_set() deletes; going back to a
// singleton deletes it too. Registered singletons are never deleted.

/datum/unit_test/species_copy_owned_by_mob

/datum/unit_test/species_copy_owned_by_mob/Run()
	var/mob/living/carbon/human/dummy/mannequin/M = allocate(/mob/living/carbon/human/dummy/mannequin)
	M.set_species(SPECIES_CUSTOM)
	var/datum/species/singleton = GLOB.all_species[SPECIES_CUSTOM]
	TEST_ASSERT_EQUAL(M.species, singleton, "set_species points at the registered singleton")
	TEST_ASSERT(!rel_is_private(M, nameof(M.species)), "a registered species is shared, not the mob's own")

	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/list/traits = list(/datum/trait/neutral/addiction_coffee = null)
	var/datum/species/first = M.species.produceCopy(traits.Copy(), M, SPECIES_HUMAN, TRUE)
	TEST_ASSERT(rel_is_private(M, nameof(M.species)), "produceCopy's result is the mob's private copy")
	TEST_ASSERT_EQUAL(owner_of(first), M, "the private copy is stamped with its owner")
	TEST_ASSERT(!QDELETED(singleton), "copying from the singleton leaves it alive")
	M.species.create_organs(M)
	var/datum/species/second = M.species.produceCopy(traits.Copy(), M, SPECIES_HUMAN, TRUE)
	TEST_ASSERT(QDELETED(first), "the replaced private copy was deleted by proto_set()")
	TEST_ASSERT_EQUAL(M.species, second, "the mob holds the new copy")
	for(var/obj/item/organ/external/E as anything in M.organs)
		E.data.get_species_name()
		E.data.get_species_bodytype(M)
	M.regenerate_icons()
	M.set_species(SPECIES_HUMAN)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(QDELETED(second), "set_species deleted the mob's previous private copy")
	TEST_ASSERT(!QDELETED(GLOB.all_species[SPECIES_HUMAN]) && !QDELETED(singleton), "singletons are never deleted")
	qdel(singleton)
	TEST_ASSERT(!QDELETED(singleton), "a registered singleton refuses qdel")
	TEST_ASSERT(!length(capture), "no lifecycle reports while swapping species copies: [json_encode(capture)]")
