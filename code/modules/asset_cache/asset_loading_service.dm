/// Allows us to lazyload asset datums
/// Anything inserted here will fully load if directly gotten
/// So this just serves to remove the requirement to load assets fully during init
// Deferred asset generation (was SSasset_loading): queued assets build over the following ticks,
// parked while the queue is empty.
GLOBAL_DATUM_INIT(asset_loading_service, /datum/world_service/asset_loading, new)

/datum/world_service/asset_loading
	name = "Asset Loading"
	lane = /datum/om/behaviour/world/asset_loading
	on_demand = TRUE
	var/list/datum/asset/generate_queue = list()
	var/assets_generating = 0
	var/max_concurrent_batched_generations = 2
	var/last_queue_len = 0

/datum/world_service/asset_loading/service_step(resumed)
	while(length(generate_queue))
		var/datum/asset/to_load = generate_queue[length(generate_queue)]
		if(istype(to_load, /datum/asset/spritesheet_batched) && assets_generating >= max_concurrent_batched_generations)
			return TRUE

		last_queue_len = length(generate_queue)
		generate_queue.len--

		to_load.queued_generation()

		if(TICK_CHECK)
			return FALSE

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
	return TRUE

/datum/world_service/asset_loading/has_work()
	return length(generate_queue) || last_queue_len

/datum/world_service/asset_loading/proc/queue_asset(datum/asset/queue)
#ifdef DO_NOT_DEFER_ASSETS
	stack_trace("We queued an instance of [queue.type] for lateloading despite not allowing it")
#endif
	generate_queue += queue
	demand()

/datum/world_service/asset_loading/proc/dequeue_asset(datum/asset/queue)
	generate_queue -= queue

/// asset_loading (was SSasset_loading).
/datum/om/behaviour/world/asset_loading
	name = "world: asset_loading"
	every = 2
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/asset_loading/service()
	return GLOB.asset_loading_service

REF_STATIC(/datum/world_service/asset_loading, list("generate_queue"))
