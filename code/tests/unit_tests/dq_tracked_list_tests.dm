// A TRACKED list var gets generated mutators (tools/analyze/src/gens/tracked_lists.rs): add_, include_, remove_, set_<v>_at, clear_,
// insert_, swap_, cut_. Each returns TRUE exactly when the list changed, bumps <v>_version, and publishes the var like its setter.

/datum/tracked_list_fixture
	var/list/items


/datum/unit_test/dq_tracked_list_mutators

/datum/unit_test/dq_tracked_list_mutators/Run()
	var/datum/tracked_list_fixture/F = new
	TEST_ASSERT_EQUAL(F.items_version, 0, "a fresh list is at version 0")
	TEST_ASSERT(!F.remove_items("a"), "removing from a null list changes nothing")
	TEST_ASSERT(!F.clear_items(), "clearing a null list changes nothing")
	TEST_ASSERT(F.add_items("a"), "the first add makes the list")
	TEST_ASSERT_EQUAL(length(F.items), 1, "one item")
	TEST_ASSERT_EQUAL(F.items_version, 1, "an add bumps the version")
	TEST_ASSERT(F.add_items("b"), "a second add")
	TEST_ASSERT(!F.include_items("a"), "include of a present item changes nothing")
	TEST_ASSERT_EQUAL(F.items_version, 2, "a no-op include leaves the version")
	TEST_ASSERT(F.include_items("c"), "include of an absent item adds it")
	TEST_ASSERT_EQUAL(length(F.items), 3, "three items")
	TEST_ASSERT(F.swap_items(1, 3), "swap")
	TEST_ASSERT_EQUAL(F.items[1], "c", "swapped")
	TEST_ASSERT(F.remove_items("b"), "remove a present item")
	TEST_ASSERT(!F.remove_items("zzz"), "remove an absent item changes nothing")
	TEST_ASSERT(F.insert_items(1, "z"), "insert")
	TEST_ASSERT_EQUAL(F.items[1], "z", "inserted at the front")
	TEST_ASSERT(F.cut_items(1, 2), "cut a range")
	TEST_ASSERT_EQUAL(length(F.items), 2, "two left")
	TEST_ASSERT(F.set_items_at(1, "q"), "set an index")
	TEST_ASSERT(!F.set_items_at(1, "q"), "set the same value twice changes nothing")
	TEST_ASSERT(F.clear_items(), "clear a list with items")
	TEST_ASSERT(islist(F.items) && !length(F.items), "an emptied list stays a list, so a later .Find() is safe")
	var/before = F.items_version
	TEST_ASSERT(!F.clear_items(), "clearing an empty list changes nothing")
	TEST_ASSERT_EQUAL(F.items_version, before, "a no-op clear leaves the version")
	var/list/assoc = list()
	F.set_items(assoc)
	TEST_ASSERT(F.set_items_at("k", 0), "an assoc key set to 0")
	TEST_ASSERT(!F.set_items_at("k", 0), "an assoc key set to its value changes nothing")
	TEST_ASSERT(F.set_items_at("k", null), "0 to null is a change")
