// Exercise actual virtual animation entry points; no host interpolation assumptions.
/mob/dq_floating_probe
	var/float_starts = 0
	var/float_stops = 0

/mob/dq_floating_probe/start_floating()
	float_starts++
	return ..()

/mob/dq_floating_probe/stop_floating()
	float_stops++
	return ..()

/datum/unit_test/dq_mob_floating_sparse
/datum/unit_test/dq_mob_floating_sparse/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/mob/dq_floating_probe/M = allocate(/mob/dq_floating_probe, test_floor())
	var/mob/dq_floating_probe/peer = allocate(/mob/dq_floating_probe, test_floor())
	TEST_ASSERT_EQUAL(sparse_get_or(M, is_floating, 0), 0, "fresh mobs retain the original inactive default")
	TEST_ASSERT_EQUAL(sparse_get_or(M, floatiness, 0), 0, "fresh mobs retain the original numeric request default")
	M.make_floating(2.5)
	TEST_ASSERT_EQUAL(sparse_get_or(M, floatiness, 0), 2.5, "numeric requests remain exact, not booleanized")
	TEST_ASSERT_EQUAL(sparse_get_or(M, is_floating, 0), 1, "real parent start records the active animation")
	TEST_ASSERT_EQUAL(M.float_starts, 1, "first request dispatches the real virtual start once")
	M.make_floating(-3)
	TEST_ASSERT_EQUAL(sparse_get_or(M, floatiness, 0), -3, "a repeated nonzero request retains its new numeric value")
	TEST_ASSERT_EQUAL(M.float_starts, 1, "repeated requests never restart an active animation")
	TEST_ASSERT_EQUAL(M.float_stops, 0, "repeated nonzero requests never stop it")
	TEST_ASSERT_EQUAL(sparse_get_or(peer, is_floating, 0), 0, "peer animation state is independent")
	TEST_ASSERT_EQUAL(sparse_get_or(peer, floatiness, 0), 0, "peer requests are independent")
	M.make_floating(0)
	TEST_ASSERT_EQUAL(M.float_stops, 1, "zero dispatches the real virtual stop exactly once")
	TEST_ASSERT_EQUAL(sparse_get_or(M, is_floating, 0), 0, "real parent stop clears active state")
	TEST_ASSERT(!sparse_has(M, is_floating), "zero active state releases its sparse slot")
	TEST_ASSERT(!sparse_has(M, floatiness), "zero request releases its sparse slot")
	M.make_floating(0)
	TEST_ASSERT_EQUAL(M.float_stops, 1, "repeated zero is idempotent")
	var/turf/space/space
	for(var/turf/space/candidate in world)
		space = candidate
		break
	TEST_ASSERT_NOTNULL(space, "the actual test map supplies a real space turf")
	M.forceMove(space)
	M.set_anchored(FALSE)
	M.update_floating()
	TEST_ASSERT_EQUAL(M.float_starts, 2, "real space update starts the actual floating path")
	TEST_ASSERT_EQUAL(sparse_get_or(M, floatiness, 0), 1, "space requests the original numeric one")
	M.set_anchored(TRUE)
	M.update_floating()
	TEST_ASSERT_EQUAL(M.float_stops, 2, "actual anchoring stops the animation through update_floating")
	TEST_ASSERT_EQUAL(sparse_get_or(M, floatiness, 0), 0, "anchoring clears the outstanding float request")
	TEST_ASSERT_EQUAL(sparse_get_or(M, is_floating, 0), 0, "anchoring clears the active animation")
	M.set_anchored(FALSE)
	M.update_floating()
	TEST_ASSERT_EQUAL(M.float_starts, 3, "unanchoring in space recovers real floating")
	M.make_floating(0)
	TEST_ASSERT_EQUAL(M.float_stops, 3, "fixture stops its actual host animation before teardown")
