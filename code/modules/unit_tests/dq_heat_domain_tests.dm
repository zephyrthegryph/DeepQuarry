// The heat domain (M4, verdigris/domains/heat) through its DM API. Each test
// takes over a few turfs' heat cells, runs heat frames to completion with
// vg_heat_debug_run_frames(), restores the cells, then asserts.

/// Makes `T` an isolated solid cell (no air coupling) at `temperature`.
/proc/heat_test_solid(turf/T, capacity, conductivity, temperature, emissivity = THERMAL_EMISSIVITY_DEFAULT)
	vg_heat_set_turf(T, HEAT_CELL_SOLID, capacity, conductivity, emissivity, temperature, FALSE)
	T.set_temperature(temperature)

/// A floor with air whose east neighbour is also a floor, for heat tests (the
/// test map has no unit-test landmarks).
///
/// Each caller gets its own untouched pair: several heat unit tests call this
/// independently and mutate whatever pair they get back, and restoring a
/// mutated cell doesn't always leave `heat_has_air()` reporting exactly what
/// it did before. Reusing a pair another test already touched therefore made
/// the match — and so the pass/fail outcome — depend on unit test run order.
/// A per-run "already handed out" set keeps every test's pair disjoint from
/// every other test's, regardless of order.
/proc/heat_test_turf()
	var/static/list/handed_out = list()
	for(var/turf/simulated/floor/T in world)
		if(handed_out[T])
			continue
		var/turf/simulated/floor/east = get_step(T, EAST)
		if(!istype(east) || handed_out[east])
			continue
		if(T.heat_has_air() && east.heat_has_air())
			handed_out[T] = TRUE
			handed_out[east] = TRUE
			return T

/// Gives `T` its own heat cell back, at room temperature.
/proc/heat_test_restore(turf/T)
	T.update_heat_cell()
	T.set_temperature(T20C)

/datum/unit_test/dq_heat_hot_wall_conducts_to_its_neighbour

/datum/unit_test/dq_heat_hot_wall_conducts_to_its_neighbour/Run()
	var/turf/hot = heat_test_turf()
	var/turf/cold = get_step(hot, EAST)
	TEST_ASSERT_NOTNULL(cold, "no turf east of the test corner")
	heat_test_solid(hot, 10000, 0.05, 500)
	heat_test_solid(cold, 10000, 0.05, 300)
	vg_heat_debug_run_frames(20)
	var/hot_after = hot.get_temperature()
	var/cold_after = cold.get_temperature()
	heat_test_restore(hot)
	heat_test_restore(cold)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(hot_after < 480, "the hot cell did not cool ([hot_after] K)")
	TEST_ASSERT(cold_after > 320, "the cold neighbour did not warm ([cold_after] K)")
	TEST_ASSERT(hot_after > cold_after, "conduction overshot ([hot_after] K vs [cold_after] K)")
	// Equal capacities: the cold cell cannot gain more than the hot one lost (other
	// neighbours, such as walls, may take heat too; exact conservation is tested in Rust).
	TEST_ASSERT((500 - hot_after) + 0.5 >= (cold_after - 300), "the neighbour gained more than was lost ([hot_after] + [cold_after] K)")

/datum/unit_test/dq_heat_space_cools_an_exposed_wall

/datum/unit_test/dq_heat_space_cools_an_exposed_wall/Run()
	var/turf/wall = heat_test_turf()
	var/turf/void = get_step(wall, EAST)
	TEST_ASSERT_NOTNULL(void, "no turf east of the test corner")
	heat_test_solid(wall, 5000, 0.05, 900, 1)
	vg_heat_set_turf(void, HEAT_CELL_SPACE, 7000, 0, 0, TCMB, FALSE)
	vg_heat_debug_run_frames(30)
	var/after = wall.get_temperature()
	// The other faces are 1 J/K floors: only radiation can take this much heat.
	heat_test_restore(void)
	heat_test_restore(wall)
	vg_heat_debug_run_frames(1)
	// σT⁴ at 900 K is ~37 kW: about 7 K/s at first for 5000 J/K.
	TEST_ASSERT(after < 800, "an exposed 900 K wall only cooled to [after] K in 30 s")
	TEST_ASSERT(after > T20C, "radiation overshot the sky temperature ([after] K)")

/datum/unit_test/dq_heat_body_is_created_on_divergence_and_relaxes

/datum/unit_test/dq_heat_body_is_created_on_divergence_and_relaxes/Run()
	var/obj/item/I = allocate(/obj/item/tool/wrench, heat_test_turf())
	var/ambient = I.get_temperature()
	TEST_ASSERT_NULL(I.heat_body, "an item at ambient temperature already has a heat body")
	var/list/properties = I.thermal_properties()
	I.add_heat(properties[THERMAL_CAPACITY] * 50)
	TEST_ASSERT_NOTNULL(I.heat_body, "add_heat did not create a heat body")
	var/start = I.get_temperature()
	TEST_ASSERT(abs(start - (ambient + 50)) < 1, "the body started at [start] K, not [ambient + 50] K")
	vg_heat_debug_run_frames(60)
	var/later = I.get_temperature()
	TEST_ASSERT(later < start - 0.5, "the body did not relax ([start] K -> [later] K)")
	TEST_ASSERT(later > ambient, "the body passed its surroundings ([later] K < [ambient] K)")
	I.release_heat_body()
	TEST_ASSERT_NULL(I.heat_body, "release kept the handle")
	TEST_ASSERT(abs(I.get_temperature() - I.get_ambient_temperature()) < 0.01, "a released item does not read its surroundings")

/datum/heat_test_subscriber
	var/wakes = 0
	var/crossings = 0

/datum/heat_test_subscriber/on_heat_wake(watch, reason, source)
	wakes++

/datum/heat_test_subscriber/on_heat_crossing(watch, payload, entered, generation)
	crossings++

/datum/unit_test/dq_heat_threshold_watches_wake_subscribers

/datum/unit_test/dq_heat_threshold_watches_wake_subscribers/Run()
	var/turf/T = heat_test_turf()
	TEST_ASSERT_NOTNULL(T, "no floor to test on")
	heat_test_solid(T, 1000, 0.05, T20C)
	var/datum/heat_test_subscriber/listener = new
	var/watch = listener.heat_watch_threshold(T, 400)
	var/set_watch = listener.heat_watch_set(T)
	heat_watch_set_add(set_watch, 1, 1, 350)
	vg_heat_debug_run_frames(2)
	SSair.dispatch_heat_wakes()
	var/before = listener.wakes
	T.add_heat(1000 * 150)
	vg_heat_debug_run_frames(2)
	SSair.dispatch_heat_wakes()
	var/after = listener.wakes
	var/crossings = listener.crossings
	heat_unwatch(watch)
	heat_unwatch(set_watch)
	listener.heat_unsubscribe()
	heat_test_restore(T)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT_NOTNULL(watch, "the threshold watch was rejected")
	TEST_ASSERT_EQUAL(before, 0, "the watch fired before the turf was heated")
	TEST_ASSERT(after >= 1, "heating the turf past 400 K did not wake the subscriber")
	TEST_ASSERT_EQUAL(crossings, 1, "the ThresholdSet entry did not report its crossing")
