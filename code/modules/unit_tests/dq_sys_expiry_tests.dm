// Expiry (code/__defines/time_now.dm) and FOR_REAL_CONTENTS (code/__defines/containment.dm),
// doc/rewrite/systems.md sections 17 and 18.

/datum/om_test_entity/var/test_until = 0
/datum/om_test_entity/var/test_started = 0

/// World-clock expiry: set, left, active, extend, clear, elapsed.
/datum/unit_test/sys_expiry_world_clock

/datum/unit_test/sys_expiry_world_clock/Run()
	var/datum/om_test_entity/E = new
	TEST_ASSERT(!COOLDOWN_RUNNING(E, test_until), "a never-set expiry is not active")
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT(E, test_until), 0, "a never-set expiry has nothing left")
	COOLDOWN_START(E, test_until, 5 SECONDS)
	TEST_ASSERT_EQUAL(E.test_until, world.time + 5 SECONDS, "COOLDOWN_START stores the world.time it ends at")
	TEST_ASSERT(COOLDOWN_RUNNING(E, test_until), "a set expiry is active")
	TEST_ASSERT(!COOLDOWN_LAPSED(E, test_until), "a set expiry is not expired")
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT(E, test_until), 5 SECONDS, "COOLDOWN_TIMELEFT reads the time left")
	COOLDOWN_EXTEND(E, test_until, 1 SECONDS)
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT(E, test_until), 5 SECONDS, "COOLDOWN_EXTEND never shortens")
	COOLDOWN_EXTEND(E, test_until, 9 SECONDS)
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT(E, test_until), 9 SECONDS, "COOLDOWN_EXTEND lengthens")
	COOLDOWN_RESET(E, test_until)
	TEST_ASSERT(COOLDOWN_LAPSED(E, test_until), "a cleared expiry is expired")
	E.test_started = world.time - 3 SECONDS
	TEST_ASSERT_EQUAL(ELAPSED(E, test_started, CLOCK_WORLD), 3 SECONDS, "ELAPSED reads time since the stamp")
	qdel(E)

/// Own-clock expiry follows the datum's OM timer clock: it stops while suspended.
/datum/unit_test/om/sys_expiry_own_clock

/datum/unit_test/om/sys_expiry_own_clock/run_om(list/made)
	var/datum/om_test_entity/bio/E = entity(made, /datum/om_test_entity/bio)
	COOLDOWN_START_OWN(E, test_until, 4 SECONDS)
	STAMP(E, test_started, CLOCK_OWN)
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT_OWN(E, test_until), 4 SECONDS, "own-clock expiry starts full")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT_OWN(E, test_until), 3 SECONDS, "own clock advances with the scheduler")
	TEST_ASSERT_EQUAL(ELAPSED(E, test_started, CLOCK_OWN), 1 SECONDS, "own-clock ELAPSED")
	hold(E, STAT_SUSPENDED, TRUE, E)
	scheduler_advance(5)
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT_OWN(E, test_until), 3 SECONDS, "suspension stops the own clock")
	TEST_ASSERT(COOLDOWN_RUNNING_OWN(E, test_until), "still active after a suspended wait")
	release(E, STAT_SUSPENDED, E)
	scheduler_advance(3.5)
	TEST_ASSERT(COOLDOWN_LAPSED_OWN(E, test_until), "expires once its own clock has run out")
	TEST_ASSERT_EQUAL(own_clock_now(null), world.time, "a null holder reads the world clock")

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

/datum/om_test_entity/var/list/test_keyed

/// TIME_NOW is the one clock read; the strict pair differs from FINISHED only at the tick the end is reached; keyed cooldowns prune themselves.
/datum/unit_test/sys_time_now_and_keyed_cooldowns

/datum/unit_test/sys_time_now_and_keyed_cooldowns/Run()
	var/datum/om_test_entity/E = new
	TEST_ASSERT_EQUAL(TIME_NOW(CLOCK_WORLD), world.time, "TIME_NOW on the world clock is world.time")
	TEST_ASSERT_EQUAL(TIME_NOW(CLOCK_OWN, E), own_clock_now(E), "TIME_NOW on the own clock reads the owner's timer clock")
	E.test_until = world.time
	TEST_ASSERT(COOLDOWN_LAPSED(E, test_until), "an end equal to now has lapsed")
	TEST_ASSERT(!COOLDOWN_RUNNING(E, test_until), "and is no longer running")
	TEST_ASSERT(!COOLDOWN_FINISHED(E, test_until), "COOLDOWN_FINISHED holds one tick longer, at end == now")
	TEST_ASSERT(COOLDOWN_KEYED_FINISHED(E, test_keyed, "a"), "a key never started is finished")
	TEST_ASSERT(!COOLDOWN_KEYED_RUNNING(E, test_keyed, "a"), "and not running")
	COOLDOWN_KEYED_START(E, test_keyed, "a", 5 SECONDS)
	TEST_ASSERT(COOLDOWN_KEYED_RUNNING(E, test_keyed, "a"), "a started key runs")
	TEST_ASSERT_EQUAL(COOLDOWN_KEYED_END(E, test_keyed, "a"), world.time + 5 SECONDS, "its end is now plus the duration")
	TEST_ASSERT(COOLDOWN_KEYED_FINISHED(E, test_keyed, "b"), "another key is unaffected")
	E.test_keyed["stale"] = world.time - 1 SECOND
	COOLDOWN_KEYED_START(E, test_keyed, "b", 1 SECOND)
	TEST_ASSERT(!("stale" in E.test_keyed), "starting a key prunes the lapsed ones")
	TEST_ASSERT(("a" in E.test_keyed) && ("b" in E.test_keyed), "and keeps the running ones")
	qdel(E)
