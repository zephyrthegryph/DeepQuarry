// Live simulation: timed cadence grants, the world step length, and gas threshold watches
// (code/engine/cadence.dm, code/controllers/subsystems/vg.dm, code/engine/time/world_watches.dm),
// and the null-safety helpers (code/_helpers/null_safety.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A cadence holder that counts its changes instead of retuning SSvg.
/datum/step_cadence/test
	var/changes = 0
	/// dt_seconds() as the holder was told of the change: the store already holds the new value.
	var/list/seen

/datum/step_cadence/test/cadence_changed()
	changes++
	LAZYADD(seen, dt_seconds())

/datum/unit_test/engine/livesim_cadence_grants_stack_and_lapse

/datum/unit_test/engine/livesim_cadence_grants_stack_and_lapse/run_engine(list/made)
	var/datum/step_cadence/test/C = new
	made += C
	var/datum/engine_test_entity/rupture = entity(made)
	var/datum/engine_test_entity/breach = entity(made)
	TEST_ASSERT_EQUAL(C.dt_seconds(), CADENCE_BASE_DT, "no grant: the base step")
	hold(C, STAT_CADENCE_HOLDS, 1, rupture, lasts = 3 SECONDS, key = CADENCE_GAS_BRISK)
	act_drain_point() // the holder's on_change reaction runs at the next drain point
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.25, "a brisk grant shortens the step")
	hold(C, STAT_CADENCE_HOLDS, 1, breach, lasts = 1 SECONDS, key = CADENCE_GAS_FAST)
	act_drain_point()
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.1, "the shortest step any live grant names wins")
	scheduler_advance(2)
	act_drain_point()
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.25, "the fast grant lapsed; the brisk one still holds")
	scheduler_advance(2)
	act_drain_point()
	TEST_ASSERT_EQUAL(C.dt_seconds(), CADENCE_BASE_DT, "the last grant to lapse restores the base step")
	TEST_ASSERT_EQUAL(C.changes, 4, "the holder heard each change (grant, grant, lapse, lapse)")
	TEST_ASSERT_EQUAL(jointext(C.seen, ","), "0.25,0.1,0.25,0.5", "and read the new step from the store when told")

/datum/unit_test/engine/livesim_cadence_grant_dies_with_its_source

/datum/unit_test/engine/livesim_cadence_grant_dies_with_its_source/run_engine(list/made)
	var/datum/step_cadence/test/C = new
	made += C
	var/datum/engine_test_entity/source = entity(made)
	hold(C, STAT_CADENCE_HOLDS, 1, source, lasts = 60 SECONDS, key = CADENCE_GAS_FAST)
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.1, "granted")
	qdel(source)
	TEST_ASSERT_EQUAL(C.dt_seconds(), CADENCE_BASE_DT, "a grant never outlives its source")

/datum/unit_test/livesim_world_step_length

/datum/unit_test/livesim_world_step_length/Run()
	var/before = SSvg.current_dt
	TEST_ASSERT_EQUAL(vg_world_set_dt(0.25), 0.25, "vg_world_set_dt reports the step now in effect")
	TEST_ASSERT_EQUAL(vg_world_set_dt(0), 0.25, "a non-positive step is refused and the current one is kept")
	TEST_ASSERT_EQUAL(vg_world_set_dt(-1), 0.25, "so is a negative one")
	SSvg.set_step_dt(0.1)
	TEST_ASSERT_EQUAL(SSvg.current_dt, 0.1, "set_cadence retunes the world step")
	SSvg.set_step_dt(before)
	TEST_ASSERT_EQUAL(SSvg.current_dt, before, "restored")
	TEST_ASSERT_EQUAL(vg_world_set_dt(before), before, "and Rust is back on the base step")

/datum/world_threshold_subscriber
	var/wakes = 0

/datum/world_threshold_subscriber/proc/on_cross(band, was)
	wakes++

/// A sensor senses a mixture's pressure against a level: quiet while the gas
/// holds steady, and woken at the crossing without polling.
/datum/unit_test/livesim_gas_threshold_watch

/datum/unit_test/livesim_gas_threshold_watch/Run()
	var/datum/world_threshold_subscriber/sub = allocate(/datum/world_threshold_subscriber)
	var/datum/gas_mixture/tank = new(70)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	tank.adjust_gas(/datum/gas/oxygen, 10)
	var/limit = tank.return_pressure() + 500
	var/datum/sense_sub/watch = sense_gas(sub, TYPE_PROC_REF(/datum/world_threshold_subscriber, on_cross), tank, CH_GAS_PRESSURE, list(limit), hysteresis = 50)
	TEST_ASSERT_NOTNULL(watch, "the watch was created")
	SSair.run_gas_frames(2)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(sub.wakes, 0, "the sensor stays quiet below the threshold")
	tank.adjust_gas(/datum/gas/nitrogen, 200)
	SSair.run_gas_frames(1)
	dq_sense_test_deliver()
	TEST_ASSERT(sub.wakes >= 1, "the pressure crossed [limit] kPa ([tank.return_pressure()]) but the sensing did not fire")
	qdel(watch)
	qdel(tank)

/// A null object for the test: "none" with a defined behaviour.
/datum/null_object/test_none

/datum/unit_test/null_safety_helpers

/datum/unit_test/null_safety_helpers/Run()
	var/datum/null_object/none = null_object_of(/datum/null_object/test_none)
	TEST_ASSERT_NOTNULL(none, "a null object is created on first use")
	TEST_ASSERT_EQUAL(none, null_object_of(/datum/null_object/test_none), "and shared after that")
	TEST_ASSERT(is_null_object(none), "is_null_object() recognises it")
	TEST_ASSERT(!is_null_object(src), "and nothing else")
	qdel(none)
	TEST_ASSERT(!QDELETED(none), "a null object refuses deletion")
	TEST_ASSERT_EQUAL(type_or_null_object(null, /obj, /datum/null_object/test_none), none, "a missing value becomes the null object")
	TEST_ASSERT_EQUAL(type_or_null_object(src, /datum/unit_test, /datum/null_object/test_none), src, "a value of the right type passes through")
	TEST_ASSERT_EQUAL(must_be(src, /datum/unit_test), src, "must_be() returns a value of the right type")
	var/threw = FALSE
	try
		must_be(null, /datum/unit_test)
	catch
		threw = TRUE
	TEST_ASSERT(threw, "must_be() asserts on null")
	threw = FALSE
	try
		must_be(none, /obj)
	catch
		threw = TRUE
	TEST_ASSERT(threw, "and on the wrong type")
	TEST_ASSERT_EQUAL(z_of(null), NO_Z, "an atom that is nowhere is on NO_Z")
	TEST_ASSERT(z_of(locate(1, 1, 1)) != NO_Z, "a turf is on its own z")

#endif
