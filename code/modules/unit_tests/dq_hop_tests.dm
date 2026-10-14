// Hop kinds: the container hop (code/tests/engine/hop_fixtures.dm). A stat or an on_change hook that reads a var of the thing it lies in hears
// that var change, and hears itself being moved to another container or out of the world.

/datum/unit_test/dq_hop_container_stat

/datum/unit_test/dq_hop_container_stat/Run()
	var/obj/hop_crate/a = allocate(/obj/hop_crate)
	var/obj/hop_crate/b = allocate(/obj/hop_crate)
	var/obj/hop_lamp/L = allocate(/obj/hop_lamp)
	TEST_ASSERT_EQUAL(L.hop_level, 1, "on the floor: no crate, level 1")
	L.forceMove(a)
	TEST_ASSERT_EQUAL(L.hop_level, 1, "moved into an unlit crate: still 1")
	a.set_hop_lit(TRUE)
	stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT_EQUAL(L.hop_level, 5, "the crate it lies in was lit: the stat followed")
	L.forceMove(b)
	TEST_ASSERT_EQUAL(L.hop_level, 1, "moved to an unlit crate: the stat re-read its container")
	a.set_hop_lit(FALSE)
	a.set_hop_lit(TRUE)
	stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT_EQUAL(L.hop_level, 1, "the old crate is no longer its business")
	b.set_hop_lit(TRUE)
	stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT_EQUAL(L.hop_level, 5, "the new crate is")
	L.moveToNullspace()
	TEST_ASSERT_EQUAL(L.hop_level, 1, "taken out of the world: no container")
	L.forceMove(a)
	TEST_ASSERT_EQUAL(L.hop_level, 5, "and back into a lit one")

/datum/unit_test/dq_hop_container_on_change

/datum/unit_test/dq_hop_container_on_change/Run()
	var/obj/hop_crate/a = allocate(/obj/hop_crate)
	var/obj/hop_crate/b = allocate(/obj/hop_crate)
	var/obj/hop_lamp/L = allocate(/obj/hop_lamp)
	L.forceMove(a)
	test_drain()
	var/base = L.hop_heard
	a.set_hop_lit(TRUE)
	test_drain()
	TEST_ASSERT_EQUAL(L.hop_heard, base + 1, "the crate's var changed: the hook heard it")
	L.forceMove(b)
	test_drain()
	TEST_ASSERT_EQUAL(L.hop_heard, base + 2, "moved to a crate whose var differs: the move re-read the far var")
	a.set_hop_lit(FALSE)
	test_drain()
	TEST_ASSERT_EQUAL(L.hop_heard, base + 2, "a write on the old crate is not the lamp's business")
	b.set_hop_lit(TRUE)
	test_drain()
	TEST_ASSERT_EQUAL(L.hop_heard, base + 3, "the new crate is watched")

/datum/unit_test/dq_hop_ckey_is_published_from_login_and_logout

/datum/unit_test/dq_hop_ckey_is_published_from_login_and_logout/Run()
	var/mob/hop_keyed/M = allocate(/mob/hop_keyed)
	test_drain()
	var/base = M.hop_key_heard
	M.ckey = "hoptestkey" // a key arriving without a client, as a disconnected player's mob keeps its key
	M.ckey_changed()
	test_drain()
	TEST_ASSERT_EQUAL(M.hop_key_heard, base + 1, "a key arriving or leaving publishes ckey to the hook that reads it")
	M.ckey = null
