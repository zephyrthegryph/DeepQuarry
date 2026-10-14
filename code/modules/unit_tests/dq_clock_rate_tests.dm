// Clock rate: an entity on a scaled clock (CLOCK_BIO here) sees its timers, its deadlines and its cadence run slower, stopped or faster
// than world time, and time already passed is kept across a change (code/engine/time). The rate of a clock is a stat's value; these tests
// drive it through the entity's biological_clock_rate() and bio_clock_rate_changed(), the way a stasis hold on a living mob does.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/om_test_entity/clock_probe
	var/rate

/datum/om_test_entity/clock_probe/timer_clock()
	return CLOCK_BIO

/datum/om_test_entity/clock_probe/biological_clock_rate()
	return rate

/// Sets the probe's clock rate the way the stat layer does: the rate first, then the clock hears of it.
/datum/unit_test/om/proc/clock_probe_rate(datum/om_test_entity/clock_probe/E, new_rate)
	E.rate = new_rate
	bio_clock_rate_changed(E)

/// The probe's record and its clock already exist (a running entity), at the unscaled rate.
/datum/unit_test/om/proc/clock_probe_running(datum/om_test_entity/clock_probe/E)
	scheduler_record_of(E)
	clock_now(E, CLOCK_BIO)

/datum/unit_test/om/clock_rate_scales_timers

/datum/unit_test/om/clock_rate_scales_timers/run_om(list/made)
	var/datum/om_test_entity/clock_probe/fast = entity(made, /datum/om_test_entity/clock_probe)
	var/datum/om_test_entity/clock_probe/slow = entity(made, /datum/om_test_entity/clock_probe)
	var/datum/om_test_entity/clock_probe/stopped = entity(made, /datum/om_test_entity/clock_probe)
	for(var/datum/om_test_entity/clock_probe/E in list(fast, slow, stopped))
		clock_probe_running(E)
	after(fast, 4 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("hit"))
	after(slow, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("hit"))
	after(stopped, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("hit"))
	clock_probe_rate(fast, 2)
	clock_probe_rate(slow, 0.5)
	clock_probe_rate(stopped, 0)
	scheduler_advance(1.5)
	TEST_ASSERT(!("hit" in fast.log), "a double-speed clock has had 3 of its 4 seconds")
	scheduler_advance(0.7)
	TEST_ASSERT("hit" in fast.log, "and finishes the rest in half the time")
	scheduler_advance(1.3)
	TEST_ASSERT(!("hit" in slow.log), "a half-speed clock has had 1.75 of its 2 seconds")
	TEST_ASSERT(!("hit" in stopped.log), "a stopped clock does not move at all")
	scheduler_advance(0.7)
	TEST_ASSERT("hit" in slow.log, "the half-speed timer fires once its clock passed 2 seconds")
	clock_probe_rate(stopped, 1)
	scheduler_advance(2.1)
	TEST_ASSERT("hit" in stopped.log, "a restarted clock finishes its timer")

/datum/unit_test/om/clock_rate_keeps_time_passed

/datum/unit_test/om/clock_rate_keeps_time_passed/run_om(list/made)
	var/datum/om_test_entity/clock_probe/E = entity(made, /datum/om_test_entity/clock_probe)
	clock_probe_running(E)
	var/start = clock_now(E, CLOCK_BIO)
	scheduler_advance(1)
	var/after_one = clock_now(E, CLOCK_BIO)
	TEST_ASSERT(abs(after_one - start - 10) < 0.01, "rate 1: a second of clock time ([after_one - start])")
	clock_probe_rate(E, 2)
	scheduler_advance(1)
	TEST_ASSERT(abs(clock_now(E, CLOCK_BIO) - after_one - 20) < 0.01, "rate 2: two seconds of clock time for one of world time")
	var/after_fast = clock_now(E, CLOCK_BIO)
	clock_probe_rate(E, 0)
	scheduler_advance(3)
	TEST_ASSERT(abs(clock_now(E, CLOCK_BIO) - after_fast) < 0.01, "rate 0: a stopped clock keeps its time")
	clock_probe_rate(E, 0.5)
	scheduler_advance(2)
	TEST_ASSERT(abs(clock_now(E, CLOCK_BIO) - after_fast - 10) < 0.01, "rate 0.5: a second of clock time for two of world time")

#endif
