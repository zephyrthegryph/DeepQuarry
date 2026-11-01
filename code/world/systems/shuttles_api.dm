// The shuttle system's API (code/controllers/subsystems/shuttles.dm declares the system).
//
//   SSshuttles.register_docking_program(tag, program) / unregister_docking_program(tag)   docking controller programs by tag
//   SSshuttles.register_shuttle(shuttle) / unregister_shuttle(shuttle)                    a shuttle joins or leaves the registry
//   SSshuttles.start_processing_shuttle(shuttle) / stop_processing_shuttle(shuttle)       the per-tick process list
//   SSshuttles.note_shuttle_areas(area)                                                   areas of a shuttle built by hand
//   SSshuttles.queue_sector_init(sector)                                                  queues a sector for init and runs the queues
//   SSshuttles.set_block_init_queue(blocked)                                              holds the init queues during a map load (the generated setter)
//   shuttles_*()                                                                          reads (code/contracts/accessors/accessors.dm)

/datum/system/shuttles/proc/register_docking_program(tag, datum/embedded_program/docking/program)
	docking_registry[tag] = ref_token(program)

/datum/system/shuttles/proc/unregister_docking_program(tag)
	docking_registry -= tag

/datum/system/shuttles/proc/register_shuttle(datum/shuttle/shuttle)
	shuttles[shuttle.name] = shuttle

/// Drops a shuttle from the registry and its movement log.
/datum/system/shuttles/proc/unregister_shuttle(datum/shuttle/shuttle)
	shuttles -= shuttle.name
	rel_remove(src, nameof(process_shuttles), shuttle)
	shuttle_logs -= shuttle

/datum/system/shuttles/proc/start_processing_shuttle(datum/shuttle/shuttle)
	rel_add(src, nameof(process_shuttles), shuttle)

/datum/system/shuttles/proc/stop_processing_shuttle(datum/shuttle/shuttle)
	rel_remove(src, nameof(process_shuttles), shuttle)

/datum/system/shuttles/proc/note_shuttle_areas(area/shuttle_area)
	shuttle_areas |= shuttle_area

/// The time the last landmark registered (a multi-destination shuttle rebuilds its cache when this passes its own).
/datum/system/shuttles/proc/landmark_registration_time()
	return last_landmark_registration_time

/// Queues a sector for its waypoint init, then runs the init queues.
/datum/system/shuttles/proc/queue_sector_init(obj/effect/overmap/visitable/sector)
	LAZYADD(sectors_to_initialize, sector)
	process_init_queues()
