#ifdef DQ_PERF_ATMOS

TEST_FOCUS(/datum/unit_test/dq_large_atmos_performance_profile)

/datum/unit_test/dq_large_atmos_performance_profile
	priority = -1000

/datum/unit_test/dq_large_atmos_performance_profile/Run()
	var/asset_wait_ticks = 0
	while((length(SSasset_loading.generate_queue) || SSasset_loading.assets_generating || SSasset_loading.last_queue_len) && asset_wait_ticks++ < world.fps * 120)
		stoplag()
	TEST_ASSERT(asset_wait_ticks < world.fps * 120, "Deferred assets did not settle before atmos profiling")
	var/profile_z = world.maxz + 1
	world.maxz = profile_z
	var/list/turf/open/profile_turfs = list()
	#ifdef DQ_PERF_ATMOS_EXTREME
	var/profile_width = min(world.maxx - 2, world.maxy - 2)
	#elif defined(DQ_PERF_ATMOS_HUGE)
	var/profile_width = 96
	#else
	var/profile_width = 48
	#endif
	for(var/x in 2 to profile_width + 1)
		for(var/y in 2 to profile_width + 1)
			var/turf/open/profile_turf = locate(x, y, profile_z)
			profile_turf = profile_turf.ChangeTurf(/turf/simulated/floor)
			profile_turfs += profile_turf

	for(var/turf/open/profile_turf as anything in profile_turfs)
		for(var/datum/gas/gas as anything in profile_turf.air.get_gases())
			profile_turf.air.set_moles(gas, 0)
		if((profile_turf.x + profile_turf.y) % 2)
			profile_turf.air.set_moles(/datum/gas/oxygen, 500)
			profile_turf.air.set_temperature(T20C)
			profile_turf.air_update_turf(FALSE, FALSE)

	// Fixture construction can span several seconds on full-map cases. Start the
	// measurement on a fresh tick so that work is not counted as atmos processing.
	stoplag()
	Master.perf_outliers.Cut()
	Master.perf_worst_tick = list()
	SSprofiler.StartProfiling()
	var/start_time = REALTIMEOFDAY
	var/performance_start_index = Master.perf_tick_usage.len + 1
	var/start_cycle = SSair.times_fired
	var/max_active_turfs = 0
	var/max_seed_turfs = 0
	var/max_retained_turfs = 0
	var/max_pending_turfs = 0
	var/max_snapshot_mixtures = 0
	var/max_published_mixtures = 0
	var/max_compute_cost = 0
	var/max_high_pressure_turfs = 0
	var/max_equalized_turfs = 0
	while(SSair.times_fired < start_cycle + 120)
		stoplag()
		max_active_turfs = max(max_active_turfs, SSair.async_active_turfs)
		max_seed_turfs = max(max_seed_turfs, SSair.async_seed_turfs)
		max_retained_turfs = max(max_retained_turfs, SSair.async_retained_turfs)
		max_pending_turfs = max(max_pending_turfs, SSair.async_pending_turfs)
		max_snapshot_mixtures = max(max_snapshot_mixtures, SSair.async_snapshot_mixtures)
		max_published_mixtures = max(max_published_mixtures, SSair.async_published_mixtures)
		max_compute_cost = max(max_compute_cost, SSair.async_compute_cost)
		max_high_pressure_turfs = max(max_high_pressure_turfs, SSair.high_pressure_turfs)
		max_equalized_turfs = max(max_equalized_turfs, SSair.num_equalize_processed)

	var/elapsed_seconds = max((REALTIMEOFDAY - start_time) * 0.1, 0.1)
	var/list/performance = Master.performance_window(elapsed_seconds, performance_start_index)
	var/list/result = list(
		"target_tps" = world.fps,
		"turfs" = length(profile_turfs),
		"atmos_cycles" = SSair.times_fired - start_cycle,
		"elapsed_seconds" = elapsed_seconds,
		"tick" = performance,
		"max_async_active_turfs" = max_active_turfs,
		"max_async_seed_turfs" = max_seed_turfs,
		"max_async_retained_turfs" = max_retained_turfs,
		"max_async_pending_turfs" = max_pending_turfs,
		"max_snapshot_mixtures" = max_snapshot_mixtures,
		"max_published_mixtures" = max_published_mixtures,
		"max_async_compute_ms" = max_compute_cost,
		"max_high_pressure_turfs" = max_high_pressure_turfs,
		"max_equalized_turfs" = max_equalized_turfs,
		"outliers" = Master.perf_outliers.Copy(),
		"worst_tick" = Master.perf_worst_tick.Copy(),
	)
	log_test("PERF_ATMOS_RESULT [json_encode(result)]")
	SSprofiler.DumpFile()

#endif

/datum/unit_test/dq_lightweight_performance_diagnostics

/datum/unit_test/dq_lightweight_performance_diagnostics/Run()
	TEST_ASSERT(SSprofiler.can_fire, "Compact performance diagnostics were disabled with full AUTO_PROFILE")
	var/list/garbage = SSgarbage.performance_diagnostics()
	var/list/shuttles = SSshuttles.performance_diagnostics()
	var/list/radiation = SSradiation.performance_diagnostics()
	TEST_ASSERT(islist(garbage["queues"]), "Garbage diagnostics omitted queue depths")
	TEST_ASSERT(islist(garbage["top_destroy_types_ms"]), "Garbage diagnostics omitted Destroy cost attribution")
	TEST_ASSERT(islist(shuttles["work"]), "Shuttle diagnostics omitted work counters")
	TEST_ASSERT(islist(shuttles["top_type_cost_ms"]), "Shuttle diagnostics omitted type costs")
	TEST_ASSERT(islist(radiation["queue"]), "Radiation diagnostics omitted queue depth")
	TEST_ASSERT(islist(radiation["top_source_cost_ms"]), "Radiation diagnostics omitted source attribution")
	var/sequence_before = SSprofiler.diagnostic_sequence
	SSprofiler.fire()
	TEST_ASSERT_EQUAL(SSprofiler.diagnostic_sequence, sequence_before + 1, "Compact performance snapshot did not complete")

#ifdef DQ_PERF_MAJOR_EVENTS

TEST_FOCUS(/datum/unit_test/dq_major_event_performance)

/datum/unit_test/dq_major_event_performance
	priority = -1000
	var/turf/open/event_center
	var/list/turf/open/event_turfs

/datum/unit_test/dq_major_event_performance/proc/prepare_fixture(width = 64)
	var/profile_z = world.maxz + 1
	world.maxz = profile_z
	event_turfs = list()
	for(var/x in 2 to width + 1)
		for(var/y in 2 to width + 1)
			var/turf/open/T = locate(x, y, profile_z)
			T = T.ChangeTurf(/turf/simulated/floor)
			event_turfs += T
	event_center = locate(round(width / 2) + 1, round(width / 2) + 1, profile_z)
	stoplag()

/datum/unit_test/dq_major_event_performance/proc/measure_event(name, datum/callback/trigger, atmos_cycles = 60)
	Master.perf_outliers.Cut()
	Master.perf_worst_tick = list()
	var/start_time = REALTIMEOFDAY
	var/performance_start_index = Master.perf_tick_usage.len + 1
	var/start_cycle = SSair.times_fired
	trigger.Invoke()
	while(SSair.times_fired < start_cycle + atmos_cycles)
		stoplag()
	var/elapsed_seconds = max((REALTIMEOFDAY - start_time) * 0.1, 0.1)
	var/list/result = list(
		"name" = name,
		"target_tps" = world.fps,
		"elapsed_seconds" = elapsed_seconds,
		"tick" = Master.performance_window(elapsed_seconds, performance_start_index),
		"outliers" = Master.perf_outliers.Copy(),
		"worst_tick" = Master.perf_worst_tick.Copy(),
	)
	log_test("PERF_MAJOR_EVENT_RESULT [json_encode(result)]")

/datum/unit_test/dq_major_event_performance/proc/trigger_large_explosion()
	explosion(event_center, 8, 16, 24, 32, FALSE, 0)

/datum/unit_test/dq_major_event_performance/proc/trigger_supermatter()
	var/obj/machinery/power/supermatter/SM = new(event_center)
	SM.pull_time = 0
	SM.power = 5000
	SM.explode()

/datum/unit_test/dq_major_event_performance/proc/trigger_mass_fire()
	for(var/turf/open/T as anything in event_turfs)
		if(T.x % 2 || T.y % 2)
			continue
		T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 500, CELL_VOLUME, TRUE)

/datum/unit_test/dq_major_event_performance/proc/trigger_decompression()
	for(var/turf/open/T as anything in event_turfs)
		if(T.x == 2 || T.y == 2)
			T.ChangeTurf(/turf/space)

/datum/unit_test/dq_major_event_performance/Run()
	var/asset_wait_ticks = 0
	while((length(SSasset_loading.generate_queue) || SSasset_loading.assets_generating || SSasset_loading.last_queue_len) && asset_wait_ticks++ < world.fps * 120)
		stoplag()
	TEST_ASSERT(asset_wait_ticks < world.fps * 120, "Deferred assets did not settle before major-event profiling")

	#ifndef DQ_PERF_MAJOR_STRESS_ONLY
	prepare_fixture()
	measure_event("large_explosion", CALLBACK(src, PROC_REF(trigger_large_explosion)))
	prepare_fixture()
	measure_event("supermatter_explosion", CALLBACK(src, PROC_REF(trigger_supermatter)))
	#endif

	#ifndef DQ_PERF_ONLY_DECOMPRESSION
	prepare_fixture()
	for(var/turf/open/T as anything in event_turfs)
		T.air.set_moles(/datum/gas/oxygen, 300)
		T.air.set_moles(/datum/gas/plasma, 100)
		T.air.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 100)
		T.air_update_turf(FALSE, FALSE)
	measure_event("mass_fire", CALLBACK(src, PROC_REF(trigger_mass_fire)))
	#endif

	prepare_fixture()
	for(var/turf/open/T as anything in event_turfs)
		T.air.set_moles(/datum/gas/oxygen, 500)
		T.air.set_temperature(T20C)
		T.air_update_turf(FALSE, FALSE)
	measure_event("decompression", CALLBACK(src, PROC_REF(trigger_decompression)))

#endif

#ifdef DQ_PERF_GENERATION

/datum/unit_test/dq_generation_performance_profile/proc/memory_snapshot(label, cycle)
	var/list/gc_queues = list()
	var/list/gc_types = list()
	for(var/queue_index in 1 to length(SSgarbage.queues))
		var/list/queue = SSgarbage.queues[queue_index]
		gc_queues += length(queue)
		for(var/list/queue_entry as anything in queue)
			if(length(queue_entry) < GC_QUEUE_ITEM_INDEX_COUNT)
				continue
			var/datum/queued = queue_entry[GC_QUEUE_ITEM_REF]
			if(!queued)
				continue
			var/type_name = "[queued.type]"
			gc_types[type_name] = (gc_types[type_name] || 0) + 1
	var/list/top_gc_types = list()
	for(var/type_name in gc_types)
		var/count = gc_types[type_name]
		var/insert_at = 1
		while(insert_at <= length(top_gc_types) && gc_types[top_gc_types[insert_at]] >= count)
			insert_at++
		top_gc_types.Insert(insert_at, type_name)
		if(length(top_gc_types) > 20)
			top_gc_types.Cut(21)
	var/list/top_gc_counts = list()
	for(var/type_name in top_gc_types)
		top_gc_counts[type_name] = gc_types[type_name]
	var/list/snapshot = list(
		"label" = label,
		"cycle" = cycle,
		"world_maxz" = world.maxz,
		"world_contents" = length(world.contents),
		"gc_queues" = gc_queues,
		"gc_total_gcs" = SSgarbage.totalgcs,
		"gc_total_dels" = SSgarbage.totaldels,
		"gc_top_types" = top_gc_counts,
		"machines_all" = length(SSmachines.all_machines),
		"machines_processing" = length(SSmachines.processing_machines),
		"expedition_sites" = length(SSexpedition.sites),
		"expedition_free_z" = length(SSexpedition.free_z),
		"auxmos" = SSair.auxmos_diagnostics(),
	)
	log_test("PERF_GENERATION_MEMORY [json_encode(snapshot)]")

TEST_FOCUS(/datum/unit_test/dq_generation_performance_profile)

/datum/unit_test/dq_generation_performance_profile
	priority = -1000
	var/datum/expedition_site/profile_site
	var/profile_generation_done = FALSE

/datum/unit_test/dq_generation_performance_profile/proc/run_profile_generation(seed, list/diagnostics)
	profile_site = SSexpedition.generate_debug_station(seed, diagnostics)
	profile_generation_done = TRUE

/datum/unit_test/dq_generation_performance_profile/Run()
	var/asset_wait_ticks = 0
	while((length(SSasset_loading.generate_queue) || SSasset_loading.assets_generating || SSasset_loading.last_queue_len) && asset_wait_ticks++ < world.fps * 120)
		stoplag()
	TEST_ASSERT(asset_wait_ticks < world.fps * 120, "Deferred assets did not settle before generation profiling")
	#ifdef DQ_PERF_GENERATION_SOAK
	var/profile_cycles = 3
	#else
	var/profile_cycles = 1
	#endif
	for(var/profile_cycle in 1 to profile_cycles)
		memory_snapshot("begin", profile_cycle)
		log_test("PERF_GENERATION_BEGIN cycle=[profile_cycle]")
		var/start_time = REALTIMEOFDAY
		Master.perf_outliers.Cut()
		Master.perf_worst_tick = list()
		var/performance_start_index = Master.perf_tick_usage.len + 1
		var/list/diagnostics = list()
		profile_site = null
		profile_generation_done = FALSE
		INVOKE_ASYNC(src, PROC_REF(run_profile_generation), 900252288, diagnostics)
		while(!profile_generation_done)
			stoplag()
		var/datum/expedition_site/site = profile_site
		var/elapsed_seconds = max((REALTIMEOFDAY - start_time) * 0.1, 0.1)
		var/list/result = list(
			"cycle" = profile_cycle,
			"target_tps" = world.fps,
			"success" = !!site,
			"elapsed_seconds" = elapsed_seconds,
			"tick" = Master.performance_window(elapsed_seconds, performance_start_index),
			"diagnostics" = diagnostics,
			"outliers" = Master.perf_outliers.Copy(),
			"worst_tick" = Master.perf_worst_tick.Copy(),
		)
		log_test("PERF_GENERATION_RESULT [json_encode(result)]")
		memory_snapshot("generated", profile_cycle)
		if(!site)
			break
		SSexpedition.release_site(site, "generation performance profile")
		log_test("PERF_GENERATION_RELEASED cycle=[profile_cycle]")
		memory_snapshot("released", profile_cycle)
		var/teardown_wait_ticks = 0
		while((length(SSexpedition.teardown_z) || !length(SSexpedition.free_z)) && teardown_wait_ticks++ < world.fps * 180)
			stoplag()
		TEST_ASSERT(teardown_wait_ticks < world.fps * 180, "Expedition teardown did not return its z-level to the reuse pool")
		var/release_start_cycle = SSair.times_fired
		while(SSair.times_fired < release_start_cycle + 60)
			stoplag()
		memory_snapshot("post_release", profile_cycle)
		log_test("PERF_GENERATION_POST_RELEASE cycle=[profile_cycle]")

#endif

#ifdef DQ_PERF_ATMOS_BASELINE

TEST_FOCUS(/datum/unit_test/dq_atmos_performance_baseline)

/datum/unit_test/dq_atmos_performance_baseline
	priority = -1000

/datum/unit_test/dq_atmos_performance_baseline/Run()
	var/asset_wait_ticks = 0
	while((length(SSasset_loading.generate_queue) || SSasset_loading.assets_generating || SSasset_loading.last_queue_len) && asset_wait_ticks++ < world.fps * 120)
		stoplag()
	TEST_ASSERT(asset_wait_ticks < world.fps * 120, "Deferred assets did not settle before baseline profiling")
	Master.perf_outliers.Cut()
	Master.perf_worst_tick = list()
	SSprofiler.StartProfiling()
	var/start_time = REALTIMEOFDAY
	var/performance_start_index = Master.perf_tick_usage.len + 1
	var/start_cycle = SSair.times_fired
	var/max_active_turfs = 0
	var/max_seed_turfs = 0
	var/max_retained_turfs = 0
	var/max_pending_turfs = 0
	var/max_snapshot_mixtures = 0
	var/max_compute_cost = 0
	while(SSair.times_fired < start_cycle + 120)
		stoplag()
		max_active_turfs = max(max_active_turfs, SSair.async_active_turfs)
		max_seed_turfs = max(max_seed_turfs, SSair.async_seed_turfs)
		max_retained_turfs = max(max_retained_turfs, SSair.async_retained_turfs)
		max_pending_turfs = max(max_pending_turfs, SSair.async_pending_turfs)
		max_snapshot_mixtures = max(max_snapshot_mixtures, SSair.async_snapshot_mixtures)
		max_compute_cost = max(max_compute_cost, SSair.async_compute_cost)

	var/elapsed_seconds = max((REALTIMEOFDAY - start_time) * 0.1, 0.1)
	var/list/result = list(
		"target_tps" = world.fps,
		"atmos_cycles" = SSair.times_fired - start_cycle,
		"elapsed_seconds" = elapsed_seconds,
		"tick" = Master.performance_window(elapsed_seconds, performance_start_index),
		"max_async_active_turfs" = max_active_turfs,
		"max_async_seed_turfs" = max_seed_turfs,
		"max_async_retained_turfs" = max_retained_turfs,
		"max_async_pending_turfs" = max_pending_turfs,
		"max_snapshot_mixtures" = max_snapshot_mixtures,
		"max_async_compute_ms" = max_compute_cost,
		"outliers" = Master.perf_outliers.Copy(),
		"worst_tick" = Master.perf_worst_tick.Copy(),
	)
	log_test("PERF_ATMOS_BASELINE_RESULT [json_encode(result)]")
	SSprofiler.DumpFile()

#endif
