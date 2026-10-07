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

/// A sensor watches a mixture's pressure through a world threshold watch: quiet while the gas
/// holds steady, and woken at the crossing without polling.
/datum/unit_test/livesim_gas_threshold_watch

/datum/unit_test/livesim_gas_threshold_watch/Run()
	var/datum/world_threshold_subscriber/sub = allocate(/datum/world_threshold_subscriber)
	var/datum/gas_mixture/tank = new(70)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	tank.adjust_gas(/datum/gas/oxygen, 10)
	var/limit = tank.return_pressure() + 500
	var/datum/native_watch/world/watch = om_world_when(sub, COND_ABOVE_H(WORLD_GAS_HANDLE(tank), CH_GAS_PRESSURE, limit, 50), TYPE_PROC_REF(/datum/world_threshold_subscriber, on_cross), LANE_URGENT)
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

/// A holder for the gas_level() capability whose air is a test-set mixture.
/obj/test_gas_holder
	var/datum/gas_mixture/test_air
	var/crowded = FALSE
	var/crossings = 0

TRACKED(/obj/test_gas_holder, crowded)

CAPABILITIES(/obj/test_gas_holder)
	gas_level(into = nameof(crowded), reading = CH_GAS_PRESSURE, above = 600, hysteresis = 50, air = nameof(test_air))
	on_change(nameof(crowded), ENTER, then(PROC_REF(on_cross)))

/obj/test_gas_holder/proc/set_air(datum/gas_mixture/mixture)
	test_air = mixture

/obj/test_gas_holder/proc/on_cross(datum/act/A)
	crossings++

/// The gas_level() capability: armed on the holder's mixture, its var turned at the crossing, and it
/// follows the air to another mixture.
/datum/unit_test/livesim_gas_level_capability

/datum/unit_test/livesim_gas_level_capability/Run()
	var/datum/gas_mixture/first = new(70)
	heat_set(first, T20C, HEAT_SOURCE_OTHER)
	first.adjust_gas(/datum/gas/oxygen, 10)
	var/datum/gas_mixture/second = new(70)
	heat_set(second, T20C, HEAT_SOURCE_OTHER)
	second.adjust_gas(/datum/gas/oxygen, 10)
	var/obj/test_gas_holder/holder = allocate(/obj/test_gas_holder)
	holder.set_air(first)
	gas_level_rearm_all(holder)
	var/datum/capability/lib/gas_level/def = cap_of(holder, CAP_GAS_LEVEL, "crowded")
	TEST_ASSERT_NOTNULL(def, "the holder's table carries the level")
	var/datum/cap_data/gas_level/state = gas_level_data(holder, def)
	TEST_ASSERT_NOTNULL(state, "the level keeps its state in the holder's activation")
	TEST_ASSERT_EQUAL(state.armed_id, first.arena_id(), "armed on the air's mixture")
	SSair.run_gas_frames(2)
	om_test_ticks(3)
	kernel_drain_now()
	TEST_ASSERT(!holder.crowded, "the var is FALSE while the pressure is below the level")
	TEST_ASSERT_EQUAL(holder.crossings, 0, "quiet while the pressure is below the level")
	first.adjust_gas(/datum/gas/nitrogen, 200)
	SSair.run_gas_frames(1)
	OM_TEST_WAIT_UNTIL(holder.crowded, 60)
	kernel_drain_now()
	TEST_ASSERT(holder.crowded, "the crossing turned the var ([first.return_pressure()] kPa, watch [state.watch] live [state.watch?.is_live()], armed [state.armed_id])")
	TEST_ASSERT_EQUAL(holder.crossings, 1, "and the holder's on_change ran once")
	holder.set_air(second)
	gas_level_rearm_all(holder)
	TEST_ASSERT_EQUAL(state.armed_id, second.arena_id(), "re-armed when the air got another mixture")
	TEST_ASSERT(!holder.crowded, "and the var follows the new mixture's reading")
	holder.set_air(null)
	gas_level_rearm_all(holder)
	TEST_ASSERT_NULL(state.watch, "an air with no mixture has no watch")
	qdel(holder)
	qdel(first)
	qdel(second)

#endif
