// The one door for Rust -> DM change delivery.
//
// Every Rust drain (typed world events, gas-dependency observations, world
// watches, heat wakes, and the power polls that still exist) ends in one of two
// calls here, so what reaches capabilities, looks and UI pushes is fed one way:
//
//   native_changed(target, channel, source)  the drain raises `channel` on `target`
//                                            (om_changed) and counts the delivery.
//   native_fired(source)                     the drain delivered a watch callback that
//                                            runs owner code; counted, nothing raised.
//
// New Rust-facing code must not add another path: declare a watch and let its
// `channel` raise here, or call native_changed() from the drain.

/// Deliveries per NATIVE_SRC_* since boot (null reads as 0). Read with native_delivery_stats().
GLOBAL_LIST_INIT(native_deliveries, new /list(NATIVE_SRC_COUNT))

/// Raises `channel` on `target` because a Rust drain reported a change. Returns TRUE when raised.
/proc/native_changed(datum/target, channel, source = NATIVE_SRC_OTHER)
	if(!channel || QDELETED(target))
		return FALSE
	GLOB.native_deliveries[source]++
	entity_raise_change(target, channel)
	return TRUE

/// Counts a Rust drain delivering a callback to owner code (no channel to raise).
/proc/native_fired(source = NATIVE_SRC_OTHER)
	GLOB.native_deliveries[source]++

/// Delivery counts by source name, for the stat panel and the profiler.
/proc/native_delivery_stats()
	var/static/list/names = list("gas_event", "gas_watch", "world_watch", "heat", "power", "other")
	var/list/stats = list()
	for(var/i in 1 to NATIVE_SRC_COUNT)
		stats["dm.deliveries.[names[i]]"] = GLOB.native_deliveries[i] || 0
	return stats
