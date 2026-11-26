/// Allows us to lazyload asset datums
/// Anything inserted here will fully load if directly gotten
/// So this just serves to remove the requirement to load assets fully during init
// Deferred asset generation (was SSasset_loading): queued assets build over the following ticks,
// parked while the queue is empty.
SYSTEM_DEF(asset_loading)
	name = "Asset Loading"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	var/list/datum/asset/generate_queue = list()
	var/assets_generating = 0
	var/max_concurrent_batched_generations = 2
	var/last_queue_len = 0
	/// The cost of draining the queue, logged when it empties (ASSET_LOADING_COST): the main-thread ms of every step, the longest step, and the steps.
	var/drain_ms = 0
	var/drain_max_ms = 0
	var/drain_steps = 0

/datum/system/asset_loading/reactions()
	. = ..()
	. += every(2, PROC_REF(generate_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Builds queued assets until the tick budget runs out; parks the item when the queue (and its cleanup) is done.
/datum/system/asset_loading/proc/generate_step(dt)
	var/started = TICK_USAGE_REAL
	. = generate_queue_step()
	var/step_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	drain_ms += step_ms
	drain_max_ms = max(drain_max_ms, step_ms)
	drain_steps++
	if(. == STEP_PARK && drain_steps)
		log_world("ASSET_LOADING_COST: the queue drained in [drain_steps] step(s), [round(drain_ms, 0.1)] ms on the main thread, the longest step [round(drain_max_ms, 0.1)] ms")
		drain_ms = 0
		drain_max_ms = 0
		drain_steps = 0

/datum/system/asset_loading/proc/generate_queue_step()
	PRIVATE_PROC(TRUE)
	while(length(generate_queue))
		var/datum/asset/to_load = generate_queue[length(generate_queue)]
		if(istype(to_load, /datum/asset/spritesheet_batched) && assets_generating >= max_concurrent_batched_generations)
			return STEP_DONE

		last_queue_len = length(generate_queue)
		// A large sheet builds its input a step at a time: it stays queued until every entry is in.
		var/datum/asset/spritesheet_batched/sheet = to_load
		if(istype(sheet) && !sheet.entries_created)
			var/built = FALSE
			try
				built = sheet.build_entries(budgeted = TRUE)
			catch(var/exception/fault)
				generate_queue.len--
				sheet.realize_failed()
				dq_report_caught(fault, "spritesheet [sheet.name] ([sheet.type]): build_entries()")
				continue
			if(!built)
				return STEP_YIELD
		generate_queue.len--

		to_load.queued_generation()

		if(KERNEL_OVER_BUDGET)
			return STEP_YIELD

	// We just emptied the queue
	if(last_queue_len && !length(generate_queue) && !assets_generating)
		last_queue_len = 0
#ifdef BENCHMARK
		benchmark_rust_mark("asset loading: queue done")
#endif
		// Clean up cached icons, freeing memory.
		rustg_iconforge_cleanup()
#ifdef BENCHMARK
		benchmark_rust_mark("asset loading: iconforge cleaned")
#endif
	return has_work() ? STEP_DONE : STEP_PARK

/datum/system/asset_loading/proc/has_work()
	return length(generate_queue) || last_queue_len

/// Wakes the generation item after work was queued.
/datum/system/asset_loading/proc/demand()
	wake_work_item(PROC_REF(generate_step))
