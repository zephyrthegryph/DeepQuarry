// Sensing (code/domains/verdigris/sense.dm, verdigris/ffi/src/sense.rs): a holder hears a Rust-owned value move to another band, and only that.
// The Rust half is proven in Rust (crossings up and down, hysteresis, removal, many watchers on a cell); these prove the declared form end to
// end and count the FFI calls it takes.

/// Sends the queued sensing commands and delivers what the next Rust frame reports, without letting time pass.
/proc/dq_sense_test_deliver()
	SSsense.flush(0)
	vg_world_run_steps(2)
	native_system().drain()
	kernel_drain_now()

/// The FFI calls to bind `name` so far (verdigris_metrics_list() reads the always-on per-bind counters).
/proc/dq_sense_test_calls(name)
	var/list/metrics = verdigris_metrics_list()
	return metrics["ffi.calls.[name]"] || 0

/// A holder that senses the temperature of the mixture a test hands it (hot: at or over T20C + 30), and its moles against limits it keeps (edited by the test).
/obj/test_sense_holder
	var/datum/gas_mixture/watched_air
	var/list/mole_limits = list(5, 20)
	var/list/heard_temperature = list()
	var/list/heard_moles = list()

CAPABILITIES(/obj/test_sense_holder)
	sensed(id = "temperature", reading = CH_GAS_TEMPERATURE, bands = list(T20C + 30), changed = PROC_REF(temperature_heard), air = nameof(watched_air))
	sensed(id = "moles", reading = CH_GAS_MOLES, bands_from = PROC_REF(limits_of), changed = PROC_REF(moles_heard), air = nameof(watched_air))

/obj/test_sense_holder/proc/temperature_heard(band, was)
	heard_temperature += list(list(band, was))

/obj/test_sense_holder/proc/moles_heard(band, was)
	heard_moles += list(list(band, was))

/obj/test_sense_holder/proc/limits_of(reading)
	return mole_limits

/// A holder over `air`, armed and delivered.
/datum/unit_test/proc/sense_test_holder(datum/gas_mixture/air)
	var/obj/test_sense_holder/holder = allocate(/obj/test_sense_holder)
	holder.set_watched_air(air)
	sensed_rearm_all(holder)
	dq_sense_test_deliver()
	return holder

/datum/unit_test/proc/sense_test_tank(moles, temperature)
	var/datum/gas_mixture/tank = allocate(/datum/gas_mixture, 70)
	tank.adjust_gas(/datum/gas/nitrogen, moles)
	heat_set(tank, temperature, HEAT_SOURCE_OTHER)
	return tank

/// A band change reaches the handler as (band, was), once per crossing, in each direction, and a move inside a band says nothing.
/datum/unit_test/dq_sense_hears_band_crossings

/datum/unit_test/dq_sense_hears_band_crossings/Run()
	var/datum/gas_mixture/tank = sense_test_tank(10, T20C)
	var/obj/test_sense_holder/holder = sense_test_holder(tank)
	TEST_ASSERT_EQUAL(length(holder.heard_temperature), 0, "arming on the band DM read said something")
	TEST_ASSERT_EQUAL(sensed_band(holder, "temperature"), 0, "the cool tank is band 0")
	heat_set(tank, T20C + 10, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard_temperature), 0, "a move inside the band was reported")
	heat_set(tank, T20C + 60, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard_temperature), 1, "the crossing up was not reported once")
	TEST_ASSERT_EQUAL(holder.heard_temperature[1][1], 1, "band after the crossing up")
	TEST_ASSERT_EQUAL(holder.heard_temperature[1][2], 0, "band before the crossing up")
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard_temperature), 2, "the crossing down was not reported")
	TEST_ASSERT_EQUAL(holder.heard_temperature[2][1], 0, "band after the crossing down")

/// A change between the holder's read and the arming (the batch is sent a frame later) is told at the first frame instead of being lost.
/datum/unit_test/dq_sense_closes_the_read_then_arm_race

/datum/unit_test/dq_sense_closes_the_read_then_arm_race/Run()
	var/datum/gas_mixture/tank = sense_test_tank(10, T20C)
	var/obj/test_sense_holder/holder = allocate(/obj/test_sense_holder)
	holder.set_watched_air(tank)
	sensed_rearm_all(holder) // reads band 0, queues the registration
	heat_set(tank, T20C + 60, HEAT_SOURCE_OTHER) // before the batch is sent
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard_temperature), 1, "the change after the read was lost")
	TEST_ASSERT_EQUAL(holder.heard_temperature[1][1], 1, "told the band it is in")

/// Many holders armed in one frame cost one vg_sense_commit, share a threshold set per cell, and no world watch is registered for them.
/datum/unit_test/dq_sense_registers_in_one_batch

/datum/unit_test/dq_sense_registers_in_one_batch/Run()
	dq_sense_test_deliver()
	var/commits_before = dq_sense_test_calls("sense_commit")
	var/watches_before = dq_sense_test_calls("world_watch_band") + dq_sense_test_calls("world_watch_threshold") + dq_sense_test_calls("world_watch_changed")
	var/list/live_before = vg_sense_live()
	var/datum/gas_mixture/shared = sense_test_tank(10, T20C)
	var/list/holders = list()
	for(var/i in 1 to 12)
		var/obj/test_sense_holder/holder = allocate(/obj/test_sense_holder)
		holder.set_watched_air(i <= 8 ? shared : sense_test_tank(10, T20C))
		sensed_rearm_all(holder)
		holders += holder
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(dq_sense_test_calls("sense_commit") - commits_before, 1, "twelve holders (two sensings each) took more than one commit")
	TEST_ASSERT_EQUAL(dq_sense_test_calls("world_watch_band") + dq_sense_test_calls("world_watch_threshold") + dq_sense_test_calls("world_watch_changed") - watches_before, 0, "sensing registered a world watch")
	var/list/live = vg_sense_live()
	// 5 distinct mixtures x 2 channels = 10 sets; 12 holders x 2 sensings = 24 registrations.
	TEST_ASSERT_EQUAL(live[1] - live_before[1], 10, "one set per (cell, channel)")
	TEST_ASSERT_EQUAL(live[2] - live_before[2], 24, "one registration per sensing")
	// Eight holders on one mixture all hear one crossing.
	heat_set(shared, T20C + 60, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	var/heard = 0
	for(var/i in 1 to 8)
		var/obj/test_sense_holder/holder = holders[i]
		heard += length(holder.heard_temperature)
	TEST_ASSERT_EQUAL(heard, 8, "eight watchers on one cell did not each hear the crossing once")
	for(var/obj/test_sense_holder/holder as anything in holders)
		qdel(holder)
	dq_sense_test_deliver()
	var/list/after = vg_sense_live()
	TEST_ASSERT_EQUAL(after[1], live_before[1], "the sets of destroyed holders were not dropped")
	TEST_ASSERT_EQUAL(after[2], live_before[2], "the registrations of destroyed holders were not dropped")

/// A limit that is edited is registered again through the batch: the new levels replace the old ones.
/datum/unit_test/dq_sense_relevels_when_a_limit_is_edited

/datum/unit_test/dq_sense_relevels_when_a_limit_is_edited/Run()
	var/datum/gas_mixture/tank = sense_test_tank(10, T20C)
	var/obj/test_sense_holder/holder = sense_test_holder(tank)
	TEST_ASSERT_EQUAL(sensed_band(holder, "moles"), 1, "10 mol is over the first limit (5), under the second (20)")
	holder.mole_limits = list(30, 40)
	sensed_relevel(holder, "moles")
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(sensed_band(holder, "moles"), 0, "the band under the new limits is read at once: the caller who changed them knows it")
	TEST_ASSERT_EQUAL(length(holder.heard_moles), 0, "re-registering told the handler of a change its caller made")
	tank.adjust_gas(/datum/gas/nitrogen, 25)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard_moles), 1, "35 mol crosses the first new limit")
	TEST_ASSERT_EQUAL(holder.heard_moles[1][1], 1, "between the new limits")
	TEST_ASSERT_EQUAL(holder.heard_moles[1][2], 0, "from under both")

/// Pointing the holder's air at another mixture moves its registrations in one batch.
/datum/unit_test/dq_sense_follows_its_mixture

/datum/unit_test/dq_sense_follows_its_mixture/Run()
	var/datum/gas_mixture/cool = sense_test_tank(10, T20C)
	var/datum/gas_mixture/hot = sense_test_tank(10, T20C + 80)
	var/obj/test_sense_holder/holder = sense_test_holder(cool)
	holder.set_watched_air(hot)
	sensed_rearm_all(holder)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(sensed_band(holder, "temperature"), 1, "the hot mixture is band 1")
	var/before = length(holder.heard_temperature)
	heat_set(cool, T20C + 90, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard_temperature), before, "the mixture the holder left still reports to it")
	heat_set(hot, T20C, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(holder.heard_temperature[length(holder.heard_temperature)][1], 0, "the mixture it follows now reports")

/// A holder that senses the air of the turf it stands on.
/obj/test_sense_room
	var/list/heard = list()

CAPABILITIES(/obj/test_sense_room)
	sensed(id = "temperature", reading = CH_GAS_TEMPERATURE, bands = list(T20C + 30), changed = PROC_REF(room_heard))

/obj/test_sense_room/proc/room_heard(band, was)
	heard += list(list(band, was))

/// A turf's air lives in the Rust turf field (another watch port than a machine's own mixture): a crossing there reaches the holder the same way.
/datum/unit_test/dq_sense_hears_a_turfs_air

/datum/unit_test/dq_sense_hears_a_turfs_air/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/test_sense_room/holder = allocate(/obj/test_sense_room, T)
	sensed_rearm_all(holder)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(sensed_band(holder, "temperature"), 0, "standard air is band 0")
	heat_set(T.air, T20C + 60, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard), 1, "heating the turf's air past the level was not reported once")
	TEST_ASSERT_EQUAL(holder.heard[1][1], 1, "band after")
	heat_set(T.air, T20C, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(holder.heard), 2, "cooling it back was not reported")

// ---------------------------------------------------------------- the air alarm

/// An air alarm in a sealed room wakes its scan when the room's air crosses a band its limits cut, and not for a move inside one; editing a limit
/// registers the new levels.
/datum/unit_test/dq_sense_air_alarm_wakes_on_its_bands

/datum/unit_test/dq_sense_air_alarm_wakes_on_its_bands/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/machinery/alarm/A = allocate(/obj/machinery/alarm, T)
	A.set_grid_power(TRUE)
	A.set_broken_condition(FALSE)
	sensed_rearm_all(A)
	dq_sense_test_deliver()
	var/datum/cap_data/sensed/data = sensed_data(A, cap_of(A, CAP_SENSED, "temperature"), FALSE)
	TEST_ASSERT_NOTNULL(data?.armed_levels, "the alarm senses the room's temperature")
	TEST_ASSERT(((A.TLV["temperature"][3]) in data.armed_levels), "its upper yellow limit is a level")
	// Settled: nothing pending, the signature of the air as it is.
	A.last_signature = A.observed_signature()
	A.set_scanning(FALSE)
	heat_set(T.air, T20C + 0.2, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT(!A.scanning, "a move inside every band woke the scan")
	heat_set(T.air, T0C + 50, HEAT_SOURCE_OTHER) // past the upper yellow limit (T0C + 40)
	dq_sense_test_deliver()
	TEST_ASSERT(A.scanning, "the room crossing a limit did not wake the scan")
	// An edited limit is registered again.
	A.set_scanning(FALSE)
	var/list/band = A.TLV["temperature"].Copy()
	band[3] = T0C + 55
	A.set_TLV_at("temperature", band)
	A.rescan() // what the threshold button does after an edit
	dq_sense_test_deliver()
	data = sensed_data(A, cap_of(A, CAP_SENSED, "temperature"), FALSE)
	TEST_ASSERT(((T0C + 55) in data.armed_levels), "the edited limit was not registered")
	TEST_ASSERT(!((T0C + 40) in data.armed_levels), "the old limit is still registered")

/// The guarantee the sensing keeps: a heat write to a pipe network's region, which reaches Rust without any DM write to the mixture, still moves
/// the band, in both directions.
/datum/unit_test/dq_sense_hears_pipe_region_heat

/datum/unit_test/dq_sense_hears_pipe_region_heat/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run")
	var/turf/A = run[1]
	var/turf/B = run[2]
	var/direction = get_dir(A, B)
	var/obj/machinery/atmospherics/pipe/simple/P1 = allocate(/obj/machinery/atmospherics/pipe/simple, A)
	var/obj/machinery/atmospherics/pipe/simple/P2 = allocate(/obj/machinery/atmospherics/pipe/simple, B)
	for(var/obj/machinery/atmospherics/pipe/simple/P as anything in list(P1, P2))
		P.set_dir(direction | REVERSE_DIR(direction))
		P.initialize_directions = P.dir
	P1.atmos_init()
	P2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(P1, P2))
	var/datum/gas_mixture/pipe_air = P1.parent?.air
	TEST_ASSERT_NOTNULL(pipe_air, "the pipes have no pipeline air")
	pipe_air.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(pipe_air, T20C, HEAT_SOURCE_OTHER)
	var/obj/test_sense_holder/holder = sense_test_holder(pipe_air)
	TEST_ASSERT_EQUAL(sensed_band(holder, "temperature"), 0, "a cool pipe region started hot")
	heat_add(pipe_air, pipe_air.heat_capacity() * 60, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(sensed_band(holder, "temperature"), 1, "heat_add() on a pipe region did not move the band ([pipe_air.return_temperature()] K)")
	heat_set(pipe_air, T20C, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(sensed_band(holder, "temperature"), 0, "cooling a pipe region did not move the band back ([pipe_air.return_temperature()] K)")
