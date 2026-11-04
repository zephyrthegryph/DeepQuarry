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

/datum/system/asset_loading/reactions()
	. = ..()
	. += every(2, PROC_REF(generate_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Builds queued assets until the tick budget runs out; parks the item when the queue (and its cleanup) is done.
/datum/system/asset_loading/proc/generate_step(dt)
	while(length(generate_queue))
		var/datum/asset/to_load = generate_queue[length(generate_queue)]
		if(istype(to_load, /datum/asset/spritesheet_batched) && assets_generating >= max_concurrent_batched_generations)
			return STEP_DONE

		last_queue_len = length(generate_queue)
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
