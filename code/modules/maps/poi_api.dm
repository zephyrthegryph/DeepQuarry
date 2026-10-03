// The points of interest system's API (code/modules/maps/poi_service.dm declares the system).
//
//   SSpois.enqueue(loader)             a poi loader landmark queues itself; the kernel places it
//   SSpois.allocate_gamma_item(item)   records the live item spawned for gamma loot
//   SSpois.release_gamma_item(item)    forgets it
//   SSpois.gamma_items()               the live gamma loot items (the system's own list: do not edit)

/// Queues a POI loader; the kernel places it (or the boot load does, before initialize()).
/datum/system/pois/proc/enqueue(obj/effect/landmark/poi_loader/loader)
	rel_add(src, nameof(poi_queue), loader)
	wake_work_item(PROC_REF(place_pois))

/// Records `item` as the live item spawned for gamma loot (a deleted item leaves the list by itself).
/datum/system/pois/proc/allocate_gamma_item(obj/item/item)
	rel_add(src, nameof(allocated_gamma_items), item)

/// Forgets `item` as allocated gamma loot.
/datum/system/pois/proc/release_gamma_item(obj/item/item)
	rel_remove(src, nameof(allocated_gamma_items), item)

/// The live items spawned for gamma loot: the system's own list, not to be edited.
/datum/system/pois/proc/gamma_items()
	return allocated_gamma_items
