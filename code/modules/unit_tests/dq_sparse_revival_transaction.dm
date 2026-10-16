// Observe the real guard while preserving the actual parent stat transition.
/mob/living/carbon/human/dq_revival_guard_probe
	var/revival_transitions = 0
	var/revival_guard_seen = FALSE

/mob/living/carbon/human/dq_revival_guard_probe/set_stat(new_stat)
	if(stat == DEAD && new_stat != DEAD)
		revival_transitions++
		revival_guard_seen = sparse_get_or(src, revival_in_progress, FALSE)
	return ..()

/datum/unit_test/dq_sparse_revival_transaction
/datum/unit_test/dq_sparse_revival_transaction/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/mob/living/carbon/human/dq_revival_guard_probe/H = allocate(/mob/living/carbon/human/dq_revival_guard_probe, test_floor())
	var/mob/living/carbon/human/peer = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(!sparse_get_or(H, revival_in_progress, FALSE), "an ordinary live human is not in a revival transaction")
	TEST_ASSERT(H.death(), "real death establishes the guarded DEAD state")
	TEST_ASSERT_EQUAL(H.stat, DEAD, "the actual human became dead")
	TEST_ASSERT_EQUAL(H.return_from_death("sparse transaction regression", src), TRUE, "the real revival pathway passes the actual DEAD-transition guard")
	TEST_ASSERT_EQUAL(H.revival_transitions, 1, "the real virtual set_stat path ran exactly once")
	TEST_ASSERT(H.revival_guard_seen, "the guard is enabled during the actual parent transition")
	TEST_ASSERT_EQUAL(H.stat, CONSCIOUS, "the real parent transition restored consciousness")
	TEST_ASSERT(!sparse_get_or(H, revival_in_progress, FALSE), "the guard is released after revival returns")
	TEST_ASSERT(!sparse_has(H, revival_in_progress), "completed transactions leave no sparse guard allocation")
	TEST_ASSERT(!sparse_get_or(peer, revival_in_progress, FALSE), "a different human never acquires the transaction guard")
	TEST_ASSERT_EQUAL(H.return_from_death("repeat regression", src), "not dead", "the real eligibility requirement still rejects repeated revival")
	TEST_ASSERT_EQUAL(H.revival_transitions, 1, "refusal does not enter the guarded transition")
