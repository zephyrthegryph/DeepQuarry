// Per-mob species copies (produceCopy()) are owned by their mob: re-applying traits or a
// custom species (what the preferences preview does on every trait change) deletes the
// replaced copy, so handles to it (organ data, trait timers) resolve to null instead of
// reporting HANDLE TARGET COLLECTED WITHOUT QDEL. Shared singletons are never deleted.

/datum/unit_test/species_copy_owned_by_mob

/datum/unit_test/species_copy_owned_by_mob/Run()
	var/mob/living/carbon/human/dummy/mannequin/M = allocate(/mob/living/carbon/human/dummy/mannequin)
	M.set_species(SPECIES_CUSTOM)
	var/datum/species/singleton = GLOB.all_species[SPECIES_CUSTOM]
	TEST_ASSERT_EQUAL(M.species, singleton, "set_species adopts the registered singleton")

	var/list/capture = list()
	GLOB.dq_lifecycle_report_capture = capture
	var/list/traits = list(/datum/trait/neutral/addiction_coffee = null)
	var/datum/species/first = M.species.produceCopy(traits.Copy(), M, SPECIES_HUMAN, TRUE)
	TEST_ASSERT(first.per_mob_copy, "produceCopy marks its result as a per-mob copy")
	TEST_ASSERT(!QDELETED(singleton), "copying from the singleton leaves it alive")
	// Organs built now hold a handle to the first copy, as the preview mannequin's do.
	M.species.create_organs(M)
	// The preview re-applies traits: the first copy is replaced and must be deleted, not dropped.
	var/datum/species/second = M.species.produceCopy(traits.Copy(), M, SPECIES_HUMAN, TRUE)
	TEST_ASSERT(QDELETED(first), "the replaced per-mob copy was qdel'd by its owner")
	TEST_ASSERT_EQUAL(M.species, second, "the mob holds the new copy")
	// Every organ reads its species through its handle: resolved or cached, never a collected report.
	for(var/obj/item/organ/external/E as anything in M.organs)
		E.data.get_species_name()
		E.data.get_species_bodytype(M)
	M.regenerate_icons()
	// Back to a singleton: the second copy goes too, the singleton survives.
	M.set_species(SPECIES_HUMAN)
	GLOB.dq_lifecycle_report_capture = null
	TEST_ASSERT(QDELETED(second), "set_species deleted the mob's previous per-mob copy")
	TEST_ASSERT(!QDELETED(GLOB.all_species[SPECIES_HUMAN]) && !QDELETED(singleton), "singletons are never deleted")
	qdel(singleton)
	TEST_ASSERT(!QDELETED(singleton), "a singleton refuses qdel")
	TEST_ASSERT(!length(capture), "no lifecycle reports while swapping species copies: [json_encode(capture)]")
