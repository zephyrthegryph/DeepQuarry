// ref_one(unindexed = TRUE): the var works, the reverse index stays out of it.
/datum/ref_unindexed_holder
	var/datum/ref_unindexed_target/plain
	var/datum/ref_unindexed_target/quick

CAPABILITIES(/datum/ref_unindexed_holder)
	ref_one(nameof(plain))
	ref_one(nameof(quick), unindexed = TRUE)

/datum/ref_unindexed_target

/datum/unit_test/dq_ref_unindexed

/datum/unit_test/dq_ref_unindexed/Run()
	var/datum/ref_unindexed_holder/H = new
	var/datum/ref_unindexed_target/T = new
	rel_set(H, nameof(H.quick), T)
	TEST_ASSERT_EQUAL(H.quick, T, "The write lands")
	TEST_ASSERT(rel_names(H, nameof(H.quick), T), "rel_names still answers")
	TEST_ASSERT_EQUAL(length(rel_sources(T)), 0, "The target's index does not know the holder")
	rel_set(H, nameof(H.plain), T)
	TEST_ASSERT_EQUAL(length(rel_sources(T)), 1, "An ordinary ref on the same target is indexed")
	rel_clear(H, nameof(H.quick))
	TEST_ASSERT_NULL(H.quick, "A clear lands")
	TEST_ASSERT(!rel_names(H, nameof(H.quick), T), "rel_names follows it")
	TEST_ASSERT_EQUAL(length(rel_sources(T)), 1, "Clearing it leaves the ordinary ref's index row")
	rel_clear(H, nameof(H.plain))
	qdel(H)
	qdel(T)
