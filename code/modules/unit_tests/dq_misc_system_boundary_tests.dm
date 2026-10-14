// Owner APIs preserve roster identity, ordering, mutation and nested initialization state.

/datum/unit_test/dq_misc_shuttle_boundary
/datum/unit_test/dq_misc_shuttle_boundary/Run()
	var/datum/system/shuttles/original_shuttles = SSshuttles
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_shuttles), original_shuttles)
	var/datum/system/shuttles/owner = own(new /datum/system/shuttles)
	SSshuttles = original_shuttles
	var/datum/embedded_program/docking/program = own(new /datum/embedded_program/docking)
	owner.register_docking_program("boundary-dock", program)
	TEST_ASSERT_EQUAL(owner.docking_program("boundary-dock"), program, "Docking lookup changed program identity")
	owner.unregister_docking_program("boundary-dock")
	TEST_ASSERT_NULL(owner.docking_program("boundary-dock"), "Unregister left the docking handle indexed")
	owner.register_docking_program("boundary-dock", program)
	qdel(program)
	TEST_ASSERT_NULL(owner.docking_program("boundary-dock"), "Deleted docking program still resolves")
	owner.block_init_queue = FALSE
	var/outer = owner.hold_initialization_queue()
	var/inner = owner.hold_initialization_queue()
	TEST_ASSERT(!outer && inner, "Nested map loads did not capture their previous blocking state")
	owner.restore_initialization_queue(inner)
	TEST_ASSERT(owner.block_init_queue, "Inner map load unblocked its outer loader")
	owner.restore_initialization_queue(outer)
	TEST_ASSERT(!owner.block_init_queue, "Outer map load did not restore the original open queue")
	var/datum/shuttle/shuttle = own(new /datum/shuttle/unit_test_active_set)
	shuttle.name = "B6 private shuttle"
	owner.register_shuttle(shuttle)
	owner.start_processing_shuttle(shuttle)
	owner.start_processing_shuttle(shuttle)
	TEST_ASSERT_EQUAL(owner.shuttles[shuttle.name], shuttle, "Shuttle registration changed identity")
	TEST_ASSERT_EQUAL(length(owner.process_shuttles), 1, "Processing relation inserted a duplicate shuttle")
	owner.stop_processing_shuttle(shuttle)
	TEST_ASSERT_EQUAL(length(owner.process_shuttles), 0, "Stopped shuttle remained in the processing relation")
	owner.shuttle_logs[shuttle] = "boundary log"
	owner.unregister_shuttle(shuttle)
	TEST_ASSERT_NULL(owner.shuttles[shuttle.name], "Unregister retained the named shuttle")
	TEST_ASSERT_NULL(owner.shuttle_logs[shuttle], "Unregister retained the shuttle log")
	var/list/areas = list(get_area(run_loc_floor_bottom_left))
	owner.register_shuttle_areas(areas)
	owner.register_shuttle_areas(areas)
	TEST_ASSERT_EQUAL(length(owner.shuttle_areas), 1, "Shuttle area union lost its set semantics")
	TEST_ASSERT(!owner.landmark_registry_changed_since(owner.last_landmark_registration_time), "Equal registry stamp triggered a cache rebuild")

/datum/unit_test/dq_misc_media_boundary
/datum/unit_test/dq_misc_media_boundary/Run()
	var/datum/system/media_tracks/original_media_tracks = SSmedia_tracks
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_media_tracks), original_media_tracks)
	var/datum/system/media_tracks/owner = own(new /datum/system/media_tracks)
	SSmedia_tracks = original_media_tracks
	var/datum/track/first = own(new /datum/track("first-url", "First", 2 SECONDS))
	var/datum/track/second = own(new /datum/track("second-url", "Second", 3 SECONDS))
	rel_add(owner, nameof(owner.all_tracks), first)
	rel_add(owner, nameof(owner.all_tracks), second)
	rel_add(owner, nameof(owner.jukebox_tracks), second)
	rel_add(owner, nameof(owner.casino_tracks), first)
	var/list/catalog = owner.tracks_for_jukebox(TRUE)
	TEST_ASSERT_EQUAL(catalog[1], first, "Unrestricted catalog lost the first track or its identity")
	TEST_ASSERT_EQUAL(catalog[2], second, "Unrestricted catalog changed track order")
	catalog.Cut()
	TEST_ASSERT_EQUAL(length(owner.tracks_for_jukebox(TRUE)), 2, "Consumer mutation cleared the private track roster")
	TEST_ASSERT_EQUAL(owner.tracks_for_jukebox()[1], second, "Restricted selection exposed an unlisted track")
	TEST_ASSERT_EQUAL(owner.tracks_for_casino()[1], first, "Casino selection changed track identity")
	TEST_ASSERT(!owner.has_lobby_tracks(), "Empty lobby claimed to have a track")
	rel_add(owner, nameof(owner.lobby_tracks), second)
	TEST_ASSERT(owner.has_lobby_tracks(), "Lobby availability did not observe a new track")

/datum/persistent/paintings/boundary_valid/CheckTokenSanity(list/token)
	return TRUE

/datum/unit_test/dq_misc_persistence_boundary
/datum/unit_test/dq_misc_persistence_boundary/Run()
	var/datum/system/persistence/original_persistence = SSpersistence
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_persistence), original_persistence)
	var/datum/system/persistence/owner = own(new /datum/system/persistence)
	SSpersistence = original_persistence
	var/list/first = list("persistence_id" = "left", "md5" = "first")
	var/list/second = list("persistence_id" = "right", "md5" = "second")
	owner.append_painting(first)
	owner.append_painting(second)
	owner.append_painting(first)
	TEST_ASSERT_EQUAL(owner.painting_count(), 3, "Painting append collapsed repeated token identities")
	TEST_ASSERT_EQUAL(owner.painting_record_at(1), first, "Painting lookup copied the token itself")
	var/list/snapshot = owner.painting_records()
	snapshot.Cut()
	TEST_ASSERT_EQUAL(owner.painting_count(), 3, "Consumer snapshot exposed the private painting roster")
	owner.prepare_painting_selection()
	var/list/candidates = owner.unpicked_paintings_for("left")
	TEST_ASSERT_EQUAL(length(candidates), 2, "Category selection dropped token multiplicity")
	TEST_ASSERT_EQUAL(candidates[1], first, "Category selection copied token identity")
	owner.discard_unpicked_painting(first)
	TEST_ASSERT_EQUAL(length(owner.unpicked_paintings_for("left")), 0, "Discard did not remove all equal token references")
	TEST_ASSERT(owner.has_unpicked_paintings(), "Discard removed another category's token")
	TEST_ASSERT(owner.remove_painting(first), "Painting removal failed to report a removed token")
	TEST_ASSERT_EQUAL(owner.painting_count(), 1, "Painting removal retained a duplicate token or removed another one")
	TEST_ASSERT_EQUAL(owner.painting_record_at(1), second, "Painting removal changed the surviving token")
	var/list/files = owner.remove_paintings_with_hash("second")
	TEST_ASSERT_EQUAL(files[1], "data/persistent/paintings/right/second.png", "Painting deletion returned the wrong persisted filename")
	TEST_ASSERT_EQUAL(owner.painting_count(), 0, "Hash deletion left a matching painting")
	var/datum/persistent/paintings/validator = own(new /datum/persistent/paintings/boundary_valid)
	first["age"] = 2
	owner.load_painting_records(list(first), validator)
	TEST_ASSERT_EQUAL(first["age"], 3, "Loading did not age the original token through the validator")
	TEST_ASSERT_EQUAL(owner.painting_record_at(1), first, "Loading copied validated token identity")

/datum/unit_test/dq_misc_catalog_boundary
/datum/unit_test/dq_misc_catalog_boundary/Run()
	var/datum/system/nerdle/original_nerdle = SSnerdle
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_nerdle), original_nerdle)
	var/datum/system/nerdle/nerdle = own(new /datum/system/nerdle)
	SSnerdle = original_nerdle
	nerdle.report_winner_or_loser(3)
	nerdle.report_winner_or_loser(1, TRUE)
	var/list/histogram = nerdle.attempt_histogram()
	TEST_ASSERT_EQUAL(histogram[3], 1, "Nerdle histogram lost a three-guess win")
	TEST_ASSERT_EQUAL(histogram[7], 1, "Nerdle histogram did not route losses to the seventh bucket")
	histogram[3] = 9
	TEST_ASSERT_EQUAL(nerdle.attempt_histogram()[3], 1, "Histogram mutation changed private round totals")
	var/datum/system/plants/original_plants = SSplants
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_plants), original_plants)
	var/datum/system/plants/plants = own(new /datum/system/plants)
	SSplants = original_plants
	var/datum/seed/seed = own(new /datum/seed)
	plants.seeds["boundary-seed"] = seed
	TEST_ASSERT_EQUAL(plants.seed_named("boundary-seed"), seed, "Seed lookup changed registered seed identity")
	TEST_ASSERT_NULL(plants.seed_named("missing"), "Seed lookup invented an unknown line")
	var/datum/system/xenoarch/original_xenoarch = SSxenoarch
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_xenoarch), original_xenoarch)
	var/datum/system/xenoarch/xenoarch = own(new /datum/system/xenoarch)
	SSxenoarch = original_xenoarch
	var/turf/target = run_loc_floor_bottom_left
	rel_add(xenoarch, nameof(xenoarch.artifact_spawning_turfs), target)
	var/list/candidates = xenoarch.artifact_spawn_candidates()
	TEST_ASSERT_EQUAL(candidates[1], target, "Artifact candidate lookup changed turf identity")
	candidates.Cut()
	TEST_ASSERT_EQUAL(length(xenoarch.artifact_spawn_candidates()), 1, "Popping an artifact candidate cleared the private roster")
	var/datum/system/antag/original_antag = SSantag
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_antag), original_antag)
	var/datum/system/antag/antag = own(new /datum/system/antag)
	SSantag = original_antag
	TEST_ASSERT(antag.has_antagonist_catalog(), "An allocated empty antagonist table was treated as absent")
	antag.all_antag_types = null
	TEST_ASSERT(!antag.has_antagonist_catalog(), "A missing antagonist table was treated as allocated")

/datum/unit_test/dq_misc_controls_boundary
/datum/unit_test/dq_misc_controls_boundary/Run()
	var/datum/system/dbcore/original_dbcore = SSdbcore
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_dbcore), original_dbcore)
	var/datum/system/dbcore/db = own(new /datum/system/dbcore)
	SSdbcore = original_dbcore
	db.configure_query_concurrency(4)
	TEST_ASSERT_EQUAL(db.query_concurrency_limit(), 4, "SQL concurrency configuration did not reach the job limit")
	var/datum/system/nightshift/original_nightshift = SSnightshift
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_nightshift), original_nightshift)
	var/datum/system/nightshift/night = own(new /datum/system/nightshift)
	SSnightshift = original_nightshift
	night.configure_automatic_nightshift(FALSE)
	TEST_ASSERT(!night.automatic, "Manual nightshift failed to disable automatic scheduling")
	night.configure_automatic_nightshift(TRUE)
	TEST_ASSERT(night.automatic, "Automatic nightshift did not restore scheduling")
	var/datum/system/motiontracker/original_motiontracker = SSmotiontracker
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_motiontracker), original_motiontracker)
	var/datum/system/motiontracker/tracker = own(new /datum/system/motiontracker)
	SSmotiontracker = original_motiontracker
	TEST_ASSERT(tracker.toggle_echo_visibility(), "First visibility toggle failed to hide echoes")
	TEST_ASSERT(!tracker.toggle_echo_visibility(), "Second visibility toggle failed to reveal echoes")
	var/datum/system/events/original_events = SSevents
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_events), original_events)
	var/datum/system/events/events = own(new /datum/system/events)
	SSevents = original_events
	events.enable_round_end_report()
	TEST_ASSERT(events.report_at_round_end, "Event report request did not enable the round-end report")
	var/datum/event_manager_panel/panel = own(new /datum/event_manager_panel)
	var/datum/event_manager_panel/other = own(new /datum/event_manager_panel)
	rel_set(events, nameof(events.tgui_event_manager_panel), panel)
	events.forget_manager_panel(other)
	TEST_ASSERT_EQUAL(events.tgui_event_manager_panel, panel, "A different panel released the active event manager")
	events.forget_manager_panel(panel)
	TEST_ASSERT_NULL(events.tgui_event_manager_panel, "The active panel did not release its owner slot")

/datum/unit_test/dq_misc_flight_radiation_boundary
/datum/unit_test/dq_misc_flight_radiation_boundary/Run()
	var/datum/system/flight/original_flight = SSflight
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_flight), original_flight)
	var/datum/system/flight/flight = own(new /datum/system/flight)
	SSflight = original_flight
	var/datum/flight_destination/destination = new
	destination.id = "boundary-destination"
	rel_add(flight, nameof(flight.destinations), destination, destination.id)
	var/obj/target = allocate(/obj, run_loc_floor_bottom_left)
	flight.index_destination_target(target, destination.id)
	TEST_ASSERT_EQUAL(flight.destination_by_id(destination.id), destination, "Destination lookup changed identity")
	TEST_ASSERT_EQUAL(flight.destination_for_target(target), destination, "Destination target indexing did not update lookup")
	var/datum/flight_port/port = new
	port.id = "boundary-port"
	rel_add(flight, nameof(flight.ports), port, port.id)
	TEST_ASSERT_EQUAL(flight.port_by_id(port.id), port, "Port lookup changed identity")
	TEST_ASSERT_NULL(flight.port_by_id("missing"), "Port lookup invented an unknown port")
	var/datum/system/radiation/original_radiation = SSradiation
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_radiation), original_radiation)
	var/datum/system/radiation/radiation = own(new /datum/system/radiation)
	SSradiation = original_radiation
	radiation.queue_shielding_update(run_loc_floor_bottom_left)
	radiation.queue_shielding_update(run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(length(radiation.dirty_turfs), 1, "Repeated shielding updates lost keyed set semantics")
	TEST_ASSERT_EQUAL(radiation.dirty_turfs[run_loc_floor_bottom_left], TRUE, "Shielding update did not mark its turf dirty")

/datum/unit_test/dq_misc_profile_boundary
/datum/unit_test/dq_misc_profile_boundary/Run()
	var/datum/system/explosions/original_explosions = SSexplosions
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_explosions), original_explosions)
	var/datum/system/explosions/explosions = allocate(/datum/system/explosions)
	SSexplosions = original_explosions
	explosions.configure_atom_type_profiling(TRUE)
	TEST_ASSERT(explosions.profile_atom_types, "Benchmark profiling reaches the real explosion attribution flag")
	explosions.configure_atom_type_profiling(FALSE)
	TEST_ASSERT(!explosions.profile_atom_types, "Disabling attribution clears the same live flag")
	var/datum/system/behaviours/original_behaviours = SSbehaviours
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_behaviours), original_behaviours)
	var/datum/system/behaviours/behaviours = allocate(/datum/system/behaviours)
	SSbehaviours = original_behaviours
	set_var(behaviours, nameof(behaviours.fire_cost), 4.25)
	set_var(behaviours, nameof(behaviours.ticks), 7)
	set_var(behaviours, nameof(behaviours.tick_overrun), 0.5)
	var/list/snapshot = behaviours.performance_snapshot()
	TEST_ASSERT_EQUAL(snapshot["fire_cost"], 4.25, "Profiler retains actual scheduler cost")
	TEST_ASSERT_EQUAL(snapshot["ticks"], 7, "Profiler retains actual legacy tick count")
	TEST_ASSERT_EQUAL(snapshot["tick_overrun"], 0.5, "Profiler retains actual overrun rather than substituting zero")
	snapshot["ticks"] = 99
	TEST_ASSERT_EQUAL(behaviours.performance_snapshot()["ticks"], 7, "Diagnostic snapshot edits do not mutate scheduler counters")

/datum/unit_test/dq_misc_shuttle_added_boundary
	var/notices = 0
	var/datum/shuttle/observed_shuttle

/datum/unit_test/dq_misc_shuttle_added_boundary/proc/shuttle_added(datum/act/notice/A)
	var/datum/notice/observer_shuttle_added/event = A
	notices++
	observed_shuttle = event.shuttle

/datum/unit_test/dq_misc_shuttle_added_boundary/Run()
	var/datum/system/shuttles/original_shuttles = SSshuttles
	defer_cleanup(null, GLOBAL_PROC_REF(dq_b6_restore_shuttles), original_shuttles)
	var/datum/system/shuttles/owner = allocate(/datum/system/shuttles)
	SSshuttles = original_shuttles
	observe(SSshuttles, /datum/notice/observer_shuttle_added, src, then(PROC_REF(shuttle_added)))
	defer_cleanup(null, GLOBAL_PROC_REF(unobserve), SSshuttles, /datum/notice/observer_shuttle_added, src)
	var/datum/shuttle/shuttle = owner.initialize_shuttle(/datum/shuttle/unit_test_active_set)
	TEST_ASSERT_NOTNULL(shuttle, "The real initializer constructs a concrete deferred shuttle")
	own(shuttle)
	TEST_ASSERT_EQUAL(notices, 1, "The moved override publishes exactly once on the historical global source")
	TEST_ASSERT_EQUAL(observed_shuttle, shuttle, "Observers receive the initializer's actual return datum")
	owner.initialize_shuttle(/datum/shuttle)
	TEST_ASSERT_EQUAL(notices, 1, "An abstract category does not emit a shuttle-added notice")

// SYSTEM_DEF.New replaces the SS global even for a test clone. Save before
// construction, restore immediately, and retain cleanup for constructor failure.

/proc/dq_b6_restore_antag(datum/system/antag/original)
	SSantag = original

/proc/dq_b6_restore_behaviours(datum/system/behaviours/original)
	SSbehaviours = original

/proc/dq_b6_restore_dbcore(datum/system/dbcore/original)
	SSdbcore = original

/proc/dq_b6_restore_events(datum/system/events/original)
	SSevents = original

/proc/dq_b6_restore_explosions(datum/system/explosions/original)
	SSexplosions = original

/proc/dq_b6_restore_flight(datum/system/flight/original)
	SSflight = original

/proc/dq_b6_restore_media_tracks(datum/system/media_tracks/original)
	SSmedia_tracks = original

/proc/dq_b6_restore_motiontracker(datum/system/motiontracker/original)
	SSmotiontracker = original

/proc/dq_b6_restore_nerdle(datum/system/nerdle/original)
	SSnerdle = original

/proc/dq_b6_restore_nightshift(datum/system/nightshift/original)
	SSnightshift = original

/proc/dq_b6_restore_persistence(datum/system/persistence/original)
	SSpersistence = original

/proc/dq_b6_restore_plants(datum/system/plants/original)
	SSplants = original

/proc/dq_b6_restore_radiation(datum/system/radiation/original)
	SSradiation = original

/proc/dq_b6_restore_shuttles(datum/system/shuttles/original)
	SSshuttles = original

/proc/dq_b6_restore_xenoarch(datum/system/xenoarch/original)
	SSxenoarch = original
