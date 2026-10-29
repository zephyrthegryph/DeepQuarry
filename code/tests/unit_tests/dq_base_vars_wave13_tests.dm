// base_vars wave 13: the speech state of a talking find and the reactive icon of an object became sparse links that go with it, the mob's last computer id
// became a sparse text slot, the unread antibodies list was deleted, and two lists that were built for every instance became lazy.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A talking find's speech state is the object's link: read back, bound to its holder, and gone with it.
/datum/unit_test/dq_base_vars_wave13_talking_atom

/datum/unit_test/dq_base_vars_wave13_talking_atom/Run()
	var/obj/item/pen/thing = allocate(/obj/item/pen, test_floor())
	TEST_ASSERT(!("talking_atom" in thing.vars), "talking_atom is not a var")
	TEST_ASSERT_NULL(thing.talking_atom(), "a pen does not talk")
	var/datum/talking_atom/talker = new /datum/talking_atom(thing)
	TEST_ASSERT_EQUAL(thing.talking_atom(), talker, "the object reads its speech state")
	TEST_ASSERT_EQUAL(talker.holder_atom(), thing, "the speech state reads its holder")
	qdel(thing)
	TEST_ASSERT(QDELETED(talker), "the speech state goes with its object")

/// A reactive icon is the object's link; a replacement retires the first, and the icon goes with its object.
/datum/unit_test/dq_base_vars_wave13_reactive_icon

/datum/unit_test/dq_base_vars_wave13_reactive_icon/Run()
	var/obj/item/pen/thing = allocate(/obj/item/pen, test_floor())
	TEST_ASSERT(!("reactive_icon" in thing.vars), "reactive_icon is not a var")
	TEST_ASSERT_NULL(thing.reactive_icon(), "a pen has no reactive icon")
	var/datum/reactive_icon_update/first = thing.add_reactive_icon(directions = list(NORTH), range = 1)
	TEST_ASSERT_NOTNULL(first, "the icon was made")
	TEST_ASSERT_EQUAL(thing.reactive_icon(), first, "the object reads its icon")
	TEST_ASSERT_EQUAL(first.owner(), thing, "the icon reads its object")
	var/datum/reactive_icon_update/second = thing.add_reactive_icon(directions = list(SOUTH), range = 1)
	TEST_ASSERT(QDELETED(first), "the replaced icon is retired")
	TEST_ASSERT_EQUAL(thing.reactive_icon(), second, "the object reads the new icon")
	qdel(thing)
	TEST_ASSERT(QDELETED(second), "the icon goes with its object")

/// The computer id is a sparse text slot of the mob, and the unread antibodies list is gone.
/datum/unit_test/dq_base_vars_wave13_mob_slots

/datum/unit_test/dq_base_vars_wave13_mob_slots/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(!("computer_id" in H.vars), "computer_id is not a var of the mob")
	TEST_ASSERT(!("antibodies" in H.vars), "antibodies is not a var of the mob")
	TEST_ASSERT_NULL(sparse_get(H, computer_id), "a mob that never had a client has no id")
	sparse_set(H, computer_id, "123456")
	TEST_ASSERT_EQUAL(sparse_get(H, computer_id), "123456", "the id reads back")
	sparse_set(H, computer_id, null)
	TEST_ASSERT_NULL(sparse_get(H, computer_id), "and clears")
	TEST_ASSERT_NULL(H.sparse_slots, "no slot is left behind")

/// The organ data's species cache is built on first use.
/datum/unit_test/dq_base_vars_wave13_organ_data_cache

/datum/unit_test/dq_base_vars_wave13_organ_data_cache/Run()
	var/datum/organ_data/data = new
	TEST_ASSERT_NULL(data.vars["cached_species_vars"], "a fresh organ data has no cache")
	TEST_ASSERT_NULL(data.get_species_name(), "and no species to ask")
	data.setup_from_species(GLOB.all_species[SPECIES_HUMAN])
	TEST_ASSERT_EQUAL(data.get_species_name(), SPECIES_HUMAN, "the species answers and fills the cache")
	TEST_ASSERT(islist(data.vars["cached_species_vars"]), "the cache exists now")
	qdel(data)

#endif
