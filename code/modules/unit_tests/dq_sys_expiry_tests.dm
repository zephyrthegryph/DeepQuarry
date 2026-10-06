// Expiry (code/__defines/sys_expiry.dm) and FOR_REAL_CONTENTS (code/__defines/containment.dm),
// doc/rewrite/systems.md sections 17 and 18.

/datum/om_test_entity/var/test_until = 0
/datum/om_test_entity/var/test_started = 0

/// World-clock expiry: set, left, active, extend, clear, elapsed.
/datum/unit_test/sys_expiry_world_clock

/datum/unit_test/sys_expiry_world_clock/Run()
	var/datum/om_test_entity/E = new
	TEST_ASSERT(!EXPIRY_ACTIVE(E, test_until, CLOCK_WORLD), "a never-set expiry is not active")
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_WORLD), 0, "a never-set expiry has nothing left")
	EXPIRY_SET(E, test_until, 5 SECONDS, CLOCK_WORLD)
	TEST_ASSERT_EQUAL(E.test_until, world.time + 5 SECONDS, "EXPIRY_SET stores the world.time it ends at")
	TEST_ASSERT(EXPIRY_ACTIVE(E, test_until, CLOCK_WORLD), "a set expiry is active")
	TEST_ASSERT(!EXPIRY_EXPIRED(E, test_until, CLOCK_WORLD), "a set expiry is not expired")
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_WORLD), 5 SECONDS, "EXPIRY_LEFT reads the time left")
	EXPIRY_EXTEND(E, test_until, 1 SECONDS, CLOCK_WORLD)
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_WORLD), 5 SECONDS, "EXPIRY_EXTEND never shortens")
	EXPIRY_EXTEND(E, test_until, 9 SECONDS, CLOCK_WORLD)
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_WORLD), 9 SECONDS, "EXPIRY_EXTEND lengthens")
	EXPIRY_CLEAR(E, test_until)
	TEST_ASSERT(EXPIRY_EXPIRED(E, test_until, CLOCK_WORLD), "a cleared expiry is expired")
	E.test_started = world.time - 3 SECONDS
	TEST_ASSERT_EQUAL(ELAPSED(E, test_started, CLOCK_WORLD), 3 SECONDS, "ELAPSED reads time since the stamp")
	TEST_ASSERT_EQUAL(ELAPSED_SINCE(E, world.time - 2, CLOCK_WORLD), 2, "ELAPSED_SINCE reads a raw point")
	TEST_ASSERT(BEFORE(E, world.time + 1, CLOCK_WORLD), "BEFORE: a future point")
	TEST_ASSERT_EQUAL(LEFT_UNTIL(E, world.time - 4, CLOCK_WORLD), 0, "LEFT_UNTIL is 0 for a past point")
	qdel(E)

/// Own-clock expiry follows the datum's OM timer clock: it stops while suspended.
/datum/unit_test/om/sys_expiry_own_clock

/datum/unit_test/om/sys_expiry_own_clock/run_om(list/made)
	var/datum/om_test_entity/bio/E = entity(made, /datum/om_test_entity/bio)
	EXPIRY_SET(E, test_until, 4 SECONDS, CLOCK_OWN)
	EXPIRY_STAMP(E, test_started, CLOCK_OWN)
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_OWN), 4 SECONDS, "own-clock expiry starts full")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_OWN), 3 SECONDS, "own clock advances with the scheduler")
	TEST_ASSERT_EQUAL(ELAPSED(E, test_started, CLOCK_OWN), 1 SECONDS, "own-clock ELAPSED")
	hold(E, STAT_SUSPENDED, TRUE, E)
	scheduler_advance(5)
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(E, test_until, CLOCK_OWN), 3 SECONDS, "suspension stops the own clock")
	TEST_ASSERT(EXPIRY_ACTIVE(E, test_until, CLOCK_OWN), "still active after a suspended wait")
	release(E, STAT_SUSPENDED, E)
	scheduler_advance(3.5)
	TEST_ASSERT(EXPIRY_EXPIRED(E, test_until, CLOCK_OWN), "expires once its own clock has run out")
	TEST_ASSERT_EQUAL(expiry_clock_now(null), world.time, "a null holder reads the world clock")

/// FOR_REAL_CONTENTS walks what is materialized and leaves latent entries latent.
/datum/unit_test/sys_for_real_contents_no_materialize

/datum/unit_test/sys_for_real_contents_no_materialize/Run()
	var/obj/item/storage/box/B = allocate(/obj/item/storage/box, run_loc_floor_bottom_left)
	var/obj/item/paper/P = new(B)
	var/latent_before = B.has_latent() ? B.latent_count() : 0
	var/list/seen = list()
	FOR_REAL_CONTENTS(var/obj/item/I as anything, B)
		seen += I
	TEST_ASSERT(P in seen, "FOR_REAL_CONTENTS sees a real content")
	TEST_ASSERT_EQUAL(B.has_latent() ? B.latent_count() : 0, latent_before, "walking materialized nothing")
	for(var/atom/movable/AM as anything in seen)
		TEST_ASSERT_EQUAL(AM.loc, B, "only direct, real contents are walked")
