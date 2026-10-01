// Live simulation: timed cadence grants, the world step length, and gas threshold watches
// (code/datums/om/cadence.dm, code/controllers/subsystems/vg.dm, code/datums/om/world_watch.dm),
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

/datum/unit_test/om/livesim_cadence_grants_stack_and_lapse

/datum/unit_test/om/livesim_cadence_grants_stack_and_lapse/run_om(list/made)
	var/datum/step_cadence/test/C = new
	made += C
	var/datum/om_test_entity/rupture = entity(made)
	var/datum/om_test_entity/breach = entity(made)
	TEST_ASSERT_EQUAL(C.dt_seconds(), CADENCE_BASE_DT, "no grant: the base step")
	om_grant_for(C, GRANT_CADENCE, CADENCE_GAS_BRISK, rupture, 3 SECONDS)
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.25, "a brisk grant shortens the step")
	om_grant_for(C, GRANT_CADENCE, CADENCE_GAS_FAST, breach, 1 SECONDS)
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.1, "the shortest step any live grant names wins")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(C.dt_seconds(), 0.25, "the fast grant lapsed; the brisk one still holds")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(C.dt_seconds(), CADENCE_BASE_DT, "the last grant to lapse restores the base step")
	TEST_ASSERT_EQUAL(C.changes, 4, "the holder heard each change (grant, grant, lapse, lapse)")
	TEST_ASSERT_EQUAL(jointext(C.seen, ","), "0.25,0.1,0.25,0.5", "and read the new step from the store when told")

/datum/unit_test/om/livesim_cadence_grant_dies_with_its_source

/datum/unit_test/om/livesim_cadence_grant_dies_with_its_source/run_om(list/made)
	var/datum/step_cadence/test/C = new
	made += C
	var/datum/om_test_entity/source = entity(made)
	om_grant_for(C, GRANT_CADENCE, CADENCE_GAS_FAST, source, 60 SECONDS)
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

/datum/world_threshold_subscriber/proc/on_cross(datum/native_watch/world/watch, reason, source, source_kind)
	wakes++

/// A sensor watches a mixture's pressure through om_watch_gas(): quiet while the gas
/// holds steady, and woken at the crossing without polling.
/datum/unit_test/livesim_gas_threshold_watch

/datum/unit_test/livesim_gas_threshold_watch/Run()
	var/datum/world_threshold_subscriber/sub = allocate(/datum/world_threshold_subscriber)
	var/datum/gas_mixture/tank = new(70)
	tank.set_temperature(T20C)
	tank.adjust_gas(/datum/gas/oxygen, 10)
	var/limit = tank.return_pressure() + 500
	var/datum/native_watch/world/watch = om_watch_gas(sub, tank, CH_GAS_PRESSURE, WORLD_CMP_ABOVE, limit, TYPE_PROC_REF(/datum/world_threshold_subscriber, on_cross), 50, LANE_URGENT)
	TEST_ASSERT_NOTNULL(watch, "the watch was created")
	SSair.run_gas_frames(2)
	om_test_ticks(3)
	TEST_ASSERT_EQUAL(sub.wakes, 0, "the sensor stays quiet below the threshold")
	tank.adjust_gas(/datum/gas/nitrogen, 200)
	SSair.run_gas_frames(1)
	// The crossing is queued by the frame above, but the wake is delivered by the kernel's urgent phase, which
	// a loaded full-suite world (sharded boots, overrun ticks) can skip for several ticks. Wait for the delivery
	// itself, with a generous bound, instead of assuming six ticks always reach it.
	om_test_wait_for(sub, nameof(sub.wakes))
	TEST_ASSERT(sub.wakes >= 1, "the pressure crossed [limit] kPa ([tank.return_pressure()]) but the watch did not fire; world wake diagnostics: [json_encode(om_world_diagnostics())]")
	TEST_ASSERT_NULL(om_watch_gas(sub, null, CH_GAS_PRESSURE, WORLD_CMP_ABOVE, 1, TYPE_PROC_REF(/datum/world_threshold_subscriber, on_cross)), "no mixture, no watch")
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
	catch // ALLOW(silent_catch): the test asserts that must_be(null) throws
		threw = TRUE
	TEST_ASSERT(threw, "must_be() asserts on null")
	threw = FALSE
	try
		must_be(none, /obj)
	catch // ALLOW(silent_catch): the test asserts that must_be() on the wrong type throws
		threw = TRUE
	TEST_ASSERT(threw, "and on the wrong type")
	TEST_ASSERT_EQUAL(z_of(null), NO_Z, "an atom that is nowhere is on NO_Z")
	TEST_ASSERT(z_of(locate(1, 1, 1)) != NO_Z, "a turf is on its own z")

/// A holder for the watches_gas capability whose "port" is a test-set mixture.
/obj/test_gas_holder
	var/datum/gas_mixture/test_air
	var/crossings = 0

/obj/test_gas_holder/capabilities()
	. = ..()
	. += watches_gas(port = null, when = PRESSURE_ABOVE, level = 600, hysteresis = 50, callback = PROC_REF(on_cross))

/obj/test_gas_holder/proc/set_air(datum/gas_mixture/mixture)
	test_air = mixture // ALLOW(ownership): a test fixture pointing at a mixture the test owns and deletes

/obj/test_gas_holder/gas_at_port(port)
	return test_air

/obj/test_gas_holder/proc/on_cross(datum/native_watch/world/watch, reason, source, source_kind)
	crossings++

/// The watches_gas() capability: armed on the holder's mixture, fired at the crossing, and it
/// follows the port to another mixture.
/datum/unit_test/livesim_watches_gas_capability

/datum/unit_test/livesim_watches_gas_capability/Run()
	var/datum/gas_mixture/first = new(70)
	first.set_temperature(T20C)
	first.adjust_gas(/datum/gas/oxygen, 10)
	var/datum/gas_mixture/second = new(70)
	second.set_temperature(T20C)
	second.adjust_gas(/datum/gas/oxygen, 10)
	var/obj/test_gas_holder/holder = allocate(/obj/test_gas_holder)
	holder.set_air(first)
	gas_watch_rearm(holder)
	var/datum/capability/watches_gas/C
	for(var/datum/capability/watches_gas/found in caps_of(holder))
		C = found
	TEST_ASSERT_NOTNULL(C, "the holder's capabilities() carries the watch")
	var/datum/gas_watch_state/state = holder.cap_data?[C.key]
	TEST_ASSERT_NOTNULL(state, "the watch keeps its state in the holder's cap_data")
	TEST_ASSERT_EQUAL(state.armed_id, first.arena_id(), "armed on the port's mixture")
	SSair.run_gas_frames(2)
	om_test_ticks(3)
	TEST_ASSERT_EQUAL(holder.crossings, 0, "quiet while the pressure is below the level")
	first.adjust_gas(/datum/gas/nitrogen, 200)
	SSair.run_gas_frames(1)
	om_test_ticks(6)
	TEST_ASSERT(holder.crossings >= 1, "the crossing called the holder ([first.return_pressure()] kPa, watch [state.watch] live [state.watch?.is_live()], armed [state.armed_id])")
	holder.set_air(second)
	gas_watch_rearm(holder)
	TEST_ASSERT_EQUAL(state.armed_id, second.arena_id(), "re-armed when the port got another mixture")
	holder.set_air(null)
	gas_watch_rearm(holder)
	TEST_ASSERT_NULL(state.watch, "a port with no mixture has no watch")
	qdel(holder)
	qdel(first)
	qdel(second)

#endif
