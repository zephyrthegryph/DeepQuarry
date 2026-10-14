/// Docking registrations retain handles; deletion of the program invalidates lookup.
/datum/system/shuttles/proc/register_docking_program(tag, datum/embedded_program/docking/program)
	docking_registry[tag] = entity_handle(program)

/datum/system/shuttles/proc/unregister_docking_program(tag)
	docking_registry -= tag

/// Temporarily hold initialization while a map loader is constructing its bounds.
/datum/system/shuttles/proc/hold_initialization_queue()
	var/previous = block_init_queue
	block_init_queue = TRUE
	return previous

/datum/system/shuttles/proc/restore_initialization_queue(previous)
	block_init_queue = previous

/datum/system/shuttles/proc/queue_sector_initialization(obj/effect/overmap/visitable/sector)
	LAZYADD(sectors_to_initialize, sector)

/datum/system/shuttles/proc/register_shuttle_areas(list/areas)
	shuttle_areas |= areas

/datum/system/shuttles/proc/register_shuttle(datum/shuttle/shuttle)
	shuttles[shuttle.name] = shuttle

/datum/system/shuttles/proc/unregister_shuttle(datum/shuttle/shuttle)
	shuttles -= shuttle.name
	rel_remove(src, nameof(process_shuttles), shuttle)
	shuttle_logs -= shuttle

/datum/system/shuttles/proc/start_processing_shuttle(datum/shuttle/shuttle)
	return rel_add(src, nameof(process_shuttles), shuttle)

/datum/system/shuttles/proc/stop_processing_shuttle(datum/shuttle/shuttle)
	return rel_remove(src, nameof(process_shuttles), shuttle)

/datum/system/shuttles/proc/landmark_registry_changed_since(timestamp)
	return timestamp < last_landmark_registration_time
