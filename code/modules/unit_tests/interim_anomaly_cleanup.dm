/// Real base anomaly expiry and neutralization clean up their owned core and countdown.
/datum/unit_test/interim_anomaly_expiry_cleanup/Run()
	test_driver_begin()
	var/obj/effect/anomaly/anomaly = allocate(/obj/effect/anomaly, run_loc_floor_bottom_left, 2 SECONDS)
	var/obj/item/assembly/signaler/anomaly/core = anomaly.anomaly_core
	var/obj/effect/countdown/anomaly/countdown = anomaly.countdown
	TEST_ASSERT(!QDELETED(anomaly), "actual anomaly initializes in a real area")
	TEST_ASSERT(istype(core) && !QDELETED(core), "actual anomaly creates its physical owned core")
	TEST_ASSERT(istype(countdown) && !QDELETED(countdown), "actual anomaly creates its physical owned countdown")
	TEST_ASSERT_EQUAL(core.loc, anomaly, "actual core belongs inside its initialized anomaly")
	TEST_ASSERT_EQUAL(countdown.attached_to, anomaly, "real countdown follows its initialized anomaly")
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(anomaly), "actual anomaly survives until its configured expiry")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(anomaly), "actual lifespan timer consumes its source at the configured deadline")
	TEST_ASSERT(QDELETED(core), "actual expiry deletes the owned core")
	TEST_ASSERT(QDELETED(countdown), "actual expiry deletes the owned countdown")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(anomaly), 0, "actual expiry leaves no source timers")

/datum/unit_test/interim_anomaly_explosion_cleanup/Run()
	var/obj/effect/anomaly/anomaly = allocate(/obj/effect/anomaly, run_loc_floor_bottom_left)
	var/obj/item/assembly/signaler/anomaly/core = anomaly.anomaly_core
	var/obj/effect/countdown/anomaly/countdown = anomaly.countdown
	TEST_ASSERT_EQUAL(anomaly.ex_act(2), FALSE, "actual weaker explosion refuses anomaly deletion")
	TEST_ASSERT(!QDELETED(anomaly) && !QDELETED(core) && !QDELETED(countdown), "weaker actual explosion preserves source and both owned children")
	TEST_ASSERT_EQUAL(anomaly.ex_act(1), TRUE, "actual severe explosion reports successful anomaly deletion")
	TEST_ASSERT(QDELETED(anomaly), "actual severe explosion consumes the exact source")
	TEST_ASSERT(QDELETED(core) && QDELETED(countdown), "actual severe explosion deletes both original owned children")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(anomaly), 0, "actual explosion cancels the original lifespan timer")

/datum/unit_test/interim_anomaly_neutralize_cleanup/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/effect/anomaly/anomaly = allocate(/obj/effect/anomaly, T)
	var/obj/item/assembly/signaler/anomaly/core = anomaly.anomaly_core
	var/obj/effect/countdown/anomaly/countdown = anomaly.countdown
	TEST_ASSERT(istype(core) && !QDELETED(core), "actual neutralization starts with a real physical core")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/effect/smoke)), 0, "actual neutralization destination starts without smoke")
	anomaly.anomalyNeutralize()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(anomaly), "actual neutralization consumes its source anomaly")
	TEST_ASSERT(QDELETED(core), "actual neutralization preserves its existing explicit core-delete policy")
	TEST_ASSERT(QDELETED(countdown), "actual neutralization removes its original owned countdown")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/effect/smoke)), 1, "actual neutralization produces its one real smoke effect")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(anomaly), 0, "actual neutralization cancels its source lifespan timer")
