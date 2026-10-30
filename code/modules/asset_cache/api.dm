// The asset loading system's API (code/modules/asset_cache/asset_loading_service.dm declares the system).
//
//   SSasset_loading.queue_asset(asset)     build `asset` over the following ticks (it fully loads if read first)
//   SSasset_loading.dequeue_asset(asset)   drop `asset` from the queue (it was loaded another way)

/datum/system/asset_loading/proc/queue_asset(datum/asset/queue)
#ifdef DO_NOT_DEFER_ASSETS
	stack_trace("We queued an instance of [queue.type] for lateloading despite not allowing it")
#endif
	generate_queue += queue
	demand()

/datum/system/asset_loading/proc/dequeue_asset(datum/asset/queue)
	generate_queue -= queue
