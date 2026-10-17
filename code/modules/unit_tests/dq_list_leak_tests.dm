// List leak regressions: creating and deleting an instance must not leave per-entity lists behind in a global. BYOND gives every list an id
// out of one pool (about 16M); a list a deleted thing's bookkeeping still holds is never freed, and a full-tree sweep (one instance of
// thousands of types) ran the pool dry ("bad list" everywhere, the world hung). The soak benchmark (code/modules/benchmarks/soak.dm)
// measures list ids, memory and census growth over minutes.

/// The staleness sweep's clean-check snapshots (strict builds) are keyed by entity and leave with it: one list of lists per checked stat
/// and draw of every entity ever made is what ran the list pool dry in a full look sweep.
/datum/unit_test/dq_staleness_good_forgotten

/datum/unit_test/dq_staleness_good_forgotten/Run()
	var/turf/T = test_floor()
	var/before = length(GLOB.staleness_good)
	for(var/i in 1 to 40)
		var/mob/living/carbon/human/H = new(T)
		staleness_track(H)
		refresh_flush()
		staleness_check_entity(H, "list leak test")
		var/ref = REF(H)
		qdel(H)
		TEST_ASSERT(isnull(GLOB.staleness_good[ref]), "a destroyed entity left its clean-check snapshots in GLOB.staleness_good")
		TEST_ASSERT(isnull(GLOB.staleness_served[ref]), "a destroyed entity left GLOB.staleness_served rows")
		TEST_ASSERT(isnull(GLOB.derived_ignored[ref]), "a destroyed entity left GLOB.derived_ignored names")
	TEST_ASSERT_EQUAL(length(GLOB.staleness_good), before, "GLOB.staleness_good grew over create/delete cycles")
