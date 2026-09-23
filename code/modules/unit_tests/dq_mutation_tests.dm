/// Regression tests for the /mob/var/list/mutations lazy-list accessors
/// (code/modules/mob/mutations.dm). `mutations` is null when empty; every
/// read/write must go through has_mutation()/add_mutation()/remove_mutation()/
/// mutation_count()/get_mutations() rather than touching the list directly.

/datum/unit_test/dq_mutations_lazy_and_accessors

/datum/unit_test/dq_mutations_lazy_and_accessors/Run()
	var/mob/M = new()

	TEST_ASSERT_EQUAL(M.mutations, null, "a freshly created mob should have a null mutations list")
	TEST_ASSERT_EQUAL(M.mutation_count(), 0, "mutation_count() on an empty mob should be 0")
	TEST_ASSERT(!M.has_mutation(HULK), "has_mutation() on an empty mob should be FALSE")
	TEST_ASSERT(islist(M.get_mutations()), "get_mutations() on an empty mob should return a list, not null")
	TEST_ASSERT_EQUAL(length(M.get_mutations()), 0, "get_mutations() on an empty mob should be an empty list")

	M.add_mutation(HULK)
	TEST_ASSERT(M.mutations, "adding a mutation should lazily allocate the list")
	TEST_ASSERT(M.has_mutation(HULK), "has_mutation() should see the mutation just added")
	TEST_ASSERT_EQUAL(M.mutation_count(), 1, "mutation_count() should be 1 after adding one mutation")

	M.add_mutation(XRAY)
	TEST_ASSERT_EQUAL(M.mutation_count(), 2, "mutation_count() should be 2 after adding a second mutation")
	TEST_ASSERT(M.has_mutation(XRAY), "has_mutation() should see the second mutation")
	TEST_ASSERT(M.has_mutation(HULK), "has_mutation() should still see the first mutation")

	M.remove_mutation(HULK)
	TEST_ASSERT(!M.has_mutation(HULK), "has_mutation() should not see a removed mutation")
	TEST_ASSERT(M.has_mutation(XRAY), "removing one mutation should not affect another")
	TEST_ASSERT_EQUAL(M.mutation_count(), 1, "mutation_count() should be 1 after removing one of two mutations")

	M.remove_mutation(XRAY)
	TEST_ASSERT_EQUAL(M.mutations, null, "removing the last mutation should null out the list again (lazy)")
	TEST_ASSERT_EQUAL(M.mutation_count(), 0, "mutation_count() should be 0 after removing every mutation")
	TEST_ASSERT(!M.has_mutation(XRAY), "has_mutation() should be FALSE once the list is empty again")

	// Removing/checking a mutation that was never added must not runtime and must
	// not allocate the lazy list.
	M.remove_mutation(HUSK)
	TEST_ASSERT_EQUAL(M.mutations, null, "removing a mutation that was never present should not allocate the list")
	TEST_ASSERT(!M.has_mutation(HUSK), "has_mutation() for a never-added mutation should be FALSE")

	qdel(M)
