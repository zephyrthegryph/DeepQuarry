/// The native system (code/datums/native/system.dm): one frame, one outbox, one read cache; the Rust gas
/// wrappers; the turf temperature seed.

/// A heat body's capacity read through native_read(): the second read in the frame is the cache's, a new frame
/// clears it, and a CHANGED record for the entity would too.
/datum/unit_test/dq_native_read_is_cached_per_frame

/datum/unit_test/dq_native_read_is_cached_per_frame/Run()
	var/datum/system/native/N = native_system()
	var/entity = vg_heat_body_create(1234, T20C, HEAT_TARGET_NONE, 0, 0, TRUE)
	TEST_ASSERT_NOTNULL(entity, "no heat body to read")
	var/key = NATIVE_KEY(VG_KIND_HEATBODY, VG_HEATBODY_FIELD_CAPACITY)
	N.run_frame(0)
	var/misses = N.cache_misses
	var/hits = N.cache_hits
	var/first = native_read(entity, key)
	TEST_ASSERT_EQUAL(first, 1234, "native_read returned [first], not the body's capacity")
	TEST_ASSERT_EQUAL(N.cache_misses, misses + 1, "the first read did not cross the FFI")
	TEST_ASSERT_EQUAL(native_read(entity, key), 1234, "the cached read differs")
	TEST_ASSERT_EQUAL(N.cache_hits, hits + 1, "the second read in the frame was not a cache hit")
	N.run_frame(0)
	native_read(entity, key)
	TEST_ASSERT_EQUAL(N.cache_misses, misses + 2, "a new frame kept the old cache")
	native_read_invalidate(entity)
	native_read(entity, key)
	TEST_ASSERT_EQUAL(N.cache_misses, misses + 3, "invalidating an entity kept its cached value")
	vg_heat_body_release(entity)

/// A frame with nothing to report delivers nothing, and reports what it did.
/datum/unit_test/dq_native_empty_frame_is_quiet

/datum/unit_test/dq_native_empty_frame_is_quiet/Run()
	var/datum/system/native/N = native_system()
	N.drain()
	var/frames = N.frames
	N.drain()
	TEST_ASSERT_EQUAL(N.frames, frames + 1, "a drain did not count as a frame")
	TEST_ASSERT(N.last_records >= 0, "the frame reported a negative record count")
	TEST_ASSERT(isnum(vg_frame_count()) && vg_frame_count() > 0, "Rust counted no frames")

/// A heat watch registered through the generic world watch ports crosses through the frame, as a CROSSED record
/// the native system hands to the watch's owner.
/datum/unit_test/dq_native_heat_watch_crosses_through_the_frame

/datum/unit_test/dq_native_heat_watch_crosses_through_the_frame/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.thermal_conductivity > 0 && candidate.heat_capacity > 0)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no heat-tracked floor")
	var/datum/native_test_listener/listener = new
	var/datum/native_watch/heat/watch = heat_watch_threshold(listener, T, T.get_temperature() + 50, TRUE, TYPE_PROC_REF(/datum/native_test_listener, on_cross))
	TEST_ASSERT_NOTNULL(watch, "the turf watch was refused")
	TEST_ASSERT(watch.is_live(), "the watch holds no Rust subscription")
	vg_world_run_steps(2)
	native_system().drain()
	TEST_ASSERT_EQUAL(listener.crossed, 0, "the watch crossed before the limit")
	T.add_heat(T.heat_capacity * 200)
	vg_world_run_steps(2)
	native_system().drain()
	TEST_ASSERT(listener.crossed >= 1, "the crossing did not reach the owner through the frame")
	qdel(watch)
	TEST_ASSERT(!watch?.is_live(), "a cancelled watch is still live")

/datum/native_test_listener
	var/crossed = 0

/datum/native_test_listener/proc/on_cross(datum/native_watch/watch, reason, source)
	crossed++

/// vg_pump moves what the plan says, conserves moles, and pump_gas() is a wrapper over it.
/datum/unit_test/dq_native_pump_wrapper_conserves_moles

/datum/unit_test/dq_native_pump_wrapper_conserves_moles/Run()
	var/datum/gas_mixture/source = new(1000)
	source.adjust_gas(/datum/gas/oxygen, 200)
	heat_set(source, T20C, HEAT_SOURCE_OTHER)
	var/datum/gas_mixture/sink = new(1000)
	sink.adjust_gas(/datum/gas/oxygen, 50)
	heat_set(sink, T20C, HEAT_SOURCE_OTHER)
	var/total = source.total_moles() + sink.total_moles()
	var/list/plan = vg_pump(source, sink, 40, null, 1, VG_PUMP_PLAN)
	TEST_ASSERT_NOTNULL(plan, "no plan for an available pump")
	TEST_ASSERT_EQUAL(source.total_moles(), 200, "a plan moved gas")
	var/power = pump_gas(null, source, sink, 40, null)
	TEST_ASSERT(power >= 0, "pump_gas refused a movable transfer")
	TEST_ASSERT(abs(sink.total_moles() - 90) < 0.01, "the sink holds [sink.total_moles()], expected 90")
	TEST_ASSERT(abs(source.total_moles() + sink.total_moles() - total) < 0.01, "pump_gas did not conserve moles")
	TEST_ASSERT_EQUAL(pump_gas(null, new /datum/gas_mixture(10), sink, 5, null), -1, "an empty source pumped")

/// scrub_gas() through vg_scrub moves only the filtered gas.
/datum/unit_test/dq_native_scrub_wrapper_takes_only_the_filtered_gas

/datum/unit_test/dq_native_scrub_wrapper_takes_only_the_filtered_gas/Run()
	var/datum/gas_mixture/source = new(1000)
	source.adjust_gas(/datum/gas/oxygen, 100)
	source.adjust_gas(/datum/gas/carbon_dioxide, 50)
	heat_set(source, T20C, HEAT_SOURCE_OTHER)
	var/datum/gas_mixture/sink = new(1000)
	heat_set(sink, T20C, HEAT_SOURCE_OTHER)
	var/power = scrub_gas(null, list(GAS_CO2), source, sink, null, null)
	TEST_ASSERT(power >= 0, "scrub_gas refused")
	TEST_ASSERT(abs(sink.get_moles(/datum/gas/carbon_dioxide) - 50) < 0.1, "the sink holds [sink.get_moles(/datum/gas/carbon_dioxide)] CO2, expected 50")
	TEST_ASSERT_EQUAL(sink.get_moles(/datum/gas/oxygen), 0, "the scrubber took oxygen")

/// A pipe heat exchange with an open turf conserves energy between the two mixtures.
/datum/unit_test/dq_native_thermal_exchange_moves_heat_between_mixtures

/datum/unit_test/dq_native_thermal_exchange_moves_heat_between_mixtures/Run()
	var/datum/gas_mixture/hot = new(70)
	hot.adjust_gas(/datum/gas/nitrogen, 50)
	heat_set(hot, T0C + 300, HEAT_SOURCE_OTHER)
	var/datum/gas_mixture/cold = new(2500)
	cold.adjust_gas(/datum/gas/nitrogen, 80)
	heat_set(cold, T20C, HEAT_SOURCE_OTHER)
	var/energy = hot.thermal_energy() + cold.thermal_energy()
	var/heat = vg_thermal_exchange(hot, cold, 70, 0.5, 0, 0)
	TEST_ASSERT(heat > 0, "no heat left the hot mixture")
	TEST_ASSERT(hot.return_temperature() < T0C + 300, "the hot side did not cool")
	TEST_ASSERT(cold.return_temperature() > T20C, "the cold side did not warm")
	TEST_ASSERT(abs(hot.thermal_energy() + cold.thermal_energy() - energy) < 1, "the exchange did not conserve energy")

/// A turf's temperature has one live source: the heat field. The seed is only what a new cell starts at.
/datum/unit_test/dq_native_turf_temperature_is_the_heat_fields

/datum/unit_test/dq_native_turf_temperature_is_the_heat_fields/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.thermal_conductivity > 0 && candidate.heat_capacity > 0)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no heat-tracked floor")
	var/seed = T.initial_temperature
	var/before = T.get_temperature()
	T.add_heat(T.heat_capacity * 10)
	TEST_ASSERT(T.get_temperature() > before, "add_heat did not raise the field's temperature")
	TEST_ASSERT_EQUAL(T.initial_temperature, seed, "add_heat rewrote the seed: a DM copy of the live temperature is back")
	T.add_heat(-T.heat_capacity * 10)

// ---------------------------------------------------------------- delivery seam to the reactions

/// A datum reacting to Rust-owned values by their `native("...")` names.
/datum/native_rx_fx
	var/list/changes = list()
	var/list/notes = list()
	var/list/crossings = list()

/datum/native_rx_fx/reactions()
	. = ..()
	. += on_change(native("native_rx_value"), PROC_REF(on_value))
	. += on_notice(/datum/notice/native, PROC_REF(on_native_notice))
	. += on_cross(native("native_rx_level"), list(10, 20), PROC_REF(on_level), urgent = TRUE)

/datum/native_rx_fx/proc/on_value(list/keys)
	changes += list(keys.Copy())

/datum/native_rx_fx/proc/on_native_notice(datum/notice/native/N)
	notes += list(list(N.kind, N.data))

/datum/native_rx_fx/proc/on_level(band, previous)
	crossings += list(list(band, previous))

/// Something else that reads no native value.
/datum/native_rx_deaf

/// A CHANGED record's key, named for `native()`, reaches on_change handlers through publish_change; an entity that
/// nobody reads is not published; the OM bridge still raises the channel.
/datum/unit_test/dq_native_change_publishes_through_reactions

/datum/unit_test/dq_native_change_publishes_through_reactions/Run()
	native_key_name_add(4242, "native_rx_value")
	var/datum/native_rx_fx/F = allocate(/datum/native_rx_fx)
	var/datum/native_rx_deaf/D = allocate(/datum/native_rx_deaf)
	TEST_ASSERT(native_publish_change(F, 4242), "the change was refused")
	TEST_ASSERT_EQUAL(length(F.changes), 0, "handlers wait for the drain")
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.changes), 1, "the named change did not reach on_change")
	TEST_ASSERT_EQUAL(F.changes[1][1], "native_rx_value", "the handler heard the wrong key")
	native_publish_change(F, 4243) // no name: nobody reads it
	native_publish_change(D, 4242)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.changes), 1, "an unnamed key published")
	TEST_ASSERT(!READERS(D, "native_rx_value"), "a datum that reads nothing has a reader")

/// A native notice is a /datum/notice/native: heard by on_notice handlers of the entity, allocated only when wanted.
/datum/unit_test/dq_native_notice_publishes_through_publish

/datum/unit_test/dq_native_notice_publishes_through_publish/Run()
	var/datum/native_rx_fx/F = allocate(/datum/native_rx_fx)
	var/datum/native_rx_deaf/D = allocate(/datum/native_rx_deaf)
	TEST_ASSERT(WANTS(F, /datum/notice/native), "the reaction did not make the notice wanted")
	TEST_ASSERT(!WANTS(D, /datum/notice/native), "a deaf datum wants native notices")
	native_publish_notice(F, 7, list(1, 2, 3))
	TEST_ASSERT_EQUAL(length(F.notes), 1, "the notice was not delivered")
	TEST_ASSERT_EQUAL(F.notes[1][1], 7, "the notice kind is wrong")
	TEST_ASSERT_EQUAL(length(F.notes[1][2]), 3, "the notice fields are wrong")
	native_publish_notice(D, 7, list(1))
	TEST_ASSERT(!length(D.rx?.listeners), "an unwanted notice reached a deaf datum")

/// A watch declared for a reaction delivers through rx_crossed: the first sight is a baseline, a band change
/// delivers (urgent: at once) with the previous band, the same band again does not; a watch of no reaction still
/// calls its owner's callback.
/datum/unit_test/dq_native_crossed_delivers_through_rx_crossed

/datum/unit_test/dq_native_crossed_delivers_through_rx_crossed/Run()
	var/datum/native_rx_fx/F = allocate(/datum/native_rx_fx)
	var/datum/rx_table/T = rx_table_of(F)
	var/list/crossing = T.crosses["native_rx_level"]
	TEST_ASSERT_EQUAL(length(crossing), 1, "the on_cross reaction is not in the table under its native key")
	var/datum/native_watch/W = new(F, TYPE_PROC_REF(/datum/native_rx_fx, on_level))
	native_watch_for_reaction(W, crossing[1])
	TEST_ASSERT(native_crossed(W, 0, list()), "the crossing was refused")
	TEST_ASSERT_EQUAL(length(F.crossings), 0, "the first sight delivered")
	native_crossed(W, 2, list())
	kernel().run_urgent(WORK_TEST_LIMIT) // an urgent crossing is a kernel request (phase U)
	TEST_ASSERT_EQUAL(length(F.crossings), 1, "an urgent band change did not deliver")
	TEST_ASSERT_EQUAL(F.crossings[1][1], 2, "wrong band")
	TEST_ASSERT_EQUAL(F.crossings[1][2], 0, "wrong previous band")
	native_crossed(W, 2, list())
	kernel().run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 1, "the same band delivered twice")
	qdel(W)
	var/datum/native_watch/plain = new(F, TYPE_PROC_REF(/datum/native_rx_fx, on_level))
	native_crossed(plain, 3, list(5))
	TEST_ASSERT_EQUAL(length(F.crossings), 2, "a non-reaction watch did not call its own callback")
	qdel(plain)

/// The kernel's phase N runs the native system's frame exactly once per tick, however often it is asked.
/datum/unit_test/dq_native_kernel_frame_once_per_tick

/datum/unit_test/dq_native_kernel_frame_once_per_tick/Run()
	var/datum/time_scheduler/sched = kernel().sched
	TEST_ASSERT_NOTNULL(sched, "the kernel has no scheduler")
	var/datum/system/native/N = native_system()
	var/saved_time = sched.manual_time
	sched.manual_time = null
	sched.world_step_tick = -1
	var/frames = N.frames
	native_frame(world.tick_lag, NATIVE_WAKE_BUDGET)
	native_frame(world.tick_lag, NATIVE_WAKE_BUDGET)
	TEST_ASSERT_EQUAL(N.frames, frames + 1, "two calls in one tick ran [N.frames - frames] frames")
	sched.world_step_tick -= 1 // the next tick
	native_frame(world.tick_lag * 3, NATIVE_WAKE_BUDGET)
	TEST_ASSERT_EQUAL(N.frames, frames + 2, "the next tick did not run a frame")
	sched.manual_time = 5
	sched.world_step_tick = -1
	native_frame(world.tick_lag, NATIVE_WAKE_BUDGET)
	TEST_ASSERT_EQUAL(N.frames, frames + 2, "a scheduler on injected time ran a frame")
	sched.manual_time = saved_time
