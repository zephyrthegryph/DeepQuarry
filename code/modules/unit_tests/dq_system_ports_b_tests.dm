// Phase 1S, worker B: the second half of the world services, ported to systems (SYSTEM_DEF). One focused test per
// system, on the helpers of dq_system_ports_a_tests.dm (assert_system_ported, assert_work_declared): the system is the
// registered singleton, it booted, its declared work is a kernel work item with the cadence the service had, and its
// step does the service's job through the step protocol.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Player tips: every 5 minutes during the game.
/datum/unit_test/dq_system_player_tips

/datum/unit_test/dq_system_player_tips/Run()
	assert_system_ported(SSplayer_tips, /datum/system/player_tips)
	assert_work_declared(SSplayer_tips, nameof(/datum/system/player_tips/proc/send_tips), 5 MINUTES, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSplayer_tips.periodic_runlevels, RUNLEVEL_GAME, "tips are sent outside the game")

/// POIs: boots after the holomaps, parks while the queue is empty, a loader that enqueues itself wakes the item and the
/// step places it; gamma loot items are a relation list reached through the api.
/datum/unit_test/dq_system_pois

/datum/unit_test/dq_system_pois/Run()
	assert_system_ported(SSpois, /datum/system/pois)
	TEST_ASSERT(/datum/system/holomaps in SSpois.needs, "the POI boot load must follow the holomaps")
	var/datum/work_item/W = assert_work_declared(SSpois, nameof(/datum/system/pois/proc/place_pois), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSpois.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "POIs lost their lobby runlevel")
	TEST_ASSERT_EQUAL(SSpois.place_pois(0), STEP_PARK, "an idle POI step must park")
	W.parked = TRUE
	var/obj/effect/landmark/poi_loader/loader = allocate(/obj/effect/landmark/poi_loader)
	TEST_ASSERT(loader in SSpois.vars["poi_queue"], "a poi loader did not queue itself")
	TEST_ASSERT(!W.parked, "enqueue() did not wake the parked POI item")
	TEST_ASSERT_EQUAL(SSpois.place_pois(0), STEP_DONE, "a POI step with a queued loader must finish")
	TEST_ASSERT(!(loader in SSpois.vars["poi_queue"]), "the POI step left the loader queued")
	TEST_ASSERT(!SSpois.vars["loading"], "the POI step left the system loading with no job pending")
	TEST_ASSERT_EQUAL(SSpois.place_pois(0), STEP_PARK, "a drained POI queue must park again")
	var/obj/item/gamma = allocate(/obj/item)
	SSpois.allocate_gamma_item(gamma)
	TEST_ASSERT(gamma in SSpois.gamma_items(), "allocate_gamma_item() did not record the item")
	SSpois.release_gamma_item(gamma)
	TEST_ASSERT(!(gamma in SSpois.gamma_items()), "release_gamma_item() did not forget the item")
	W.parked = FALSE

/// Star movement: every tick in the game, parked while nothing is queued, woken by toggle_move_stars(), parked again once
/// the queued movement is done.
/datum/unit_test/dq_system_starmover

/datum/unit_test/dq_system_starmover/Run()
	assert_system_ported(SSstarmover, /datum/system/starmover)
	var/datum/work_item/W = assert_work_declared(SSstarmover, nameof(/datum/system/starmover/proc/move_stars), 1, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSstarmover.periodic_runlevels, RUNLEVELS_DEFAULT, "star movement runs in the lobby")
	TEST_ASSERT_EQUAL(SSstarmover.move_stars(0), STEP_PARK, "an idle star mover must park")
	W.parked = TRUE
	SSstarmover.toggle_move_stars(run_loc_floor_bottom_left.z, null)
	TEST_ASSERT(!W.parked, "toggle_move_stars() did not wake the parked item")
	TEST_ASSERT_EQUAL(length(SSstarmover.vars["zqueue"]), 1, "the movement was not queued")
	var/result = SSstarmover.move_stars(0)
	for(var/i in 1 to 50) // a test tick is always over budget: the step yields until the z-level is done
		if(result != STEP_YIELD)
			break
		result = SSstarmover.move_stars(0)
	TEST_ASSERT_EQUAL(result, STEP_PARK, "a finished movement must park the item")
	TEST_ASSERT_EQUAL(length(SSstarmover.vars["zqueue"]), 0, "the star mover kept a finished movement")
	W.parked = FALSE

/// The crew transfer: boots after atoms, checks every second during the game, keeps a hard end it answers through the api.
/datum/unit_test/dq_system_transfer

/datum/unit_test/dq_system_transfer/Run()
	assert_system_ported(SStransfer, /datum/system/transfer)
	TEST_ASSERT(/datum/system/atoms in SStransfer.needs, "the transfer system boots after atoms")
	assert_work_declared(SStransfer, nameof(/datum/system/transfer/proc/check_transfer), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SStransfer.periodic_runlevels, RUNLEVEL_GAME, "transfer votes are checked outside the game")
	TEST_ASSERT(isnum(SStransfer.get_hard_end()), "get_hard_end() must answer a number")
	TEST_ASSERT(SStransfer.get_hard_end() > 0, "the shift has no hard end")

/// A vote that counts its ticks and ends when told to.
/datum/vote/dq_probe
	vote_type_text = "probe"
	var/ticks = 0
	var/finish = FALSE

/datum/vote/dq_probe/start(mob/user)
	return

/datum/vote/dq_probe/tick()
	ticks++
	if(finish)
		qdel(src)

/// Votes: parked while none runs, start_vote() makes the vote the running one and wakes the item, a tick reaches the vote,
/// and a vote that ends is forgotten so the item parks again.
/datum/unit_test/dq_system_vote

/datum/unit_test/dq_system_vote/Run()
	assert_system_ported(SSvote, /datum/system/vote)
	var/datum/work_item/W = assert_work_declared(SSvote, nameof(/datum/system/vote/proc/tick_vote), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSvote.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "votes tick outside the lobby and game")
	TEST_ASSERT_NULL(SSvote.get_active_vote(), "a vote is already running")
	TEST_ASSERT_EQUAL(SSvote.tick_vote(0), STEP_PARK, "with no vote the item must park")
	W.parked = TRUE
	var/datum/vote/dq_probe/V = new
	SSvote.start_vote(V)
	TEST_ASSERT_EQUAL(SSvote.get_active_vote(), V, "start_vote() did not make the vote the running one")
	TEST_ASSERT(!W.parked, "start_vote() did not wake the parked item")
	TEST_ASSERT_EQUAL(SSvote.tick_vote(0), STEP_DONE, "a tick with a running vote keeps the item running")
	TEST_ASSERT_EQUAL(V.ticks, 1, "the tick did not reach the vote")
	V.finish = TRUE
	TEST_ASSERT_EQUAL(SSvote.tick_vote(0), STEP_PARK, "a vote that ended must park the item")
	TEST_ASSERT_NULL(SSvote.get_active_vote(), "an ended vote is still the running one")
	W.parked = FALSE

/// Time tracking: boots after the database, samples every 10 s in every runlevel, a disabled sampler does nothing.
/datum/unit_test/dq_system_time_track

/datum/unit_test/dq_system_time_track/Run()
	assert_system_ported(SStime_track, /datum/system/time_track)
	TEST_ASSERT(/datum/system/dbcore in SStime_track.needs, "time tracking boots after the database")
	assert_work_declared(SStime_track, nameof(/datum/system/time_track/proc/sample_time), 10 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SStime_track.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "time tracking lost its lobby runlevel")
	var/disabled = SStime_track.disabled
	SStime_track.disabled = TRUE
	TEST_ASSERT_EQUAL(SStime_track.sample_time(0), STEP_DONE, "a disabled sampler must finish at once")
	SStime_track.disabled = disabled
	TEST_ASSERT(isnum(SStime_track.time_dilation_current), "the time dilation reading is not a number")

/// Server housekeeping: boots after the garbage system, one pass every SERVER_MAINT_INTERVAL ticks, finishes with no clients.
/datum/unit_test/dq_system_server_maint

/datum/unit_test/dq_system_server_maint/Run()
	assert_system_ported(SSserver_maint, /datum/system/server_maint)
	TEST_ASSERT(/datum/system/garbage in SSserver_maint.needs, "server maintenance boots after the garbage system")
	assert_work_declared(SSserver_maint, nameof(/datum/system/server_maint/proc/maintain), 6, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSserver_maint.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "server maintenance lost its lobby runlevel")
	TEST_ASSERT(length(SSserver_maint.lists_to_clear), "the lists to clear were not set up at boot")
	var/saved = SSserver_maint.cleanup_ticker
	TEST_ASSERT_EQUAL(SSserver_maint.maintain(0), STEP_DONE, "a maintenance pass with no clients must finish")
	TEST_ASSERT_EQUAL(SSserver_maint.cleanup_ticker, saved + 1, "the maintenance pass did not advance its list clearing")
	SSserver_maint.cleanup_ticker = saved

/// Solars: a pass every minute during the game; with no controllers it finishes, and an angle query in space is the sun's.
/datum/unit_test/dq_system_solars

/datum/unit_test/dq_system_solars/Run()
	assert_system_ported(SSsolars, /datum/system/solars)
	assert_work_declared(SSsolars, nameof(/datum/system/solars/proc/update_solars), 1 MINUTE, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSsolars.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "solars update outside the game")
	var/result = SSsolars.update_solars(0)
	for(var/i in 1 to 50) // a test tick is always over budget: the pass yields between controllers
		if(result != STEP_YIELD)
			break
		result = SSsolars.update_solars(0)
	TEST_ASSERT_EQUAL(result, STEP_DONE, "the solar pass did not finish")
	TEST_ASSERT_EQUAL(SSsolars.get_solar_angle(null), GLOB.sun.angle, "a turf-less angle query must answer the sun's angle")

/// Xenoarch: boots after atoms, has no periodic work, placed its digsites and artifacts at boot.
/datum/unit_test/dq_system_xenoarch

/datum/unit_test/dq_system_xenoarch/Run()
	assert_system_ported(SSxenoarch, /datum/system/xenoarch)
	TEST_ASSERT(/datum/system/atoms in SSxenoarch.needs, "xenoarch boots after atoms")
	TEST_ASSERT_NULL(dq_system_work(SSxenoarch, nameof(/datum/system/xenoarch/proc/continual_generation)), "xenoarch has no periodic work")
	TEST_ASSERT(islist(SSxenoarch.artifact_spawning_turfs), "the artifact turf list is not a list")
	TEST_ASSERT(islist(SSxenoarch.digsite_spawning_turfs), "the digsite turf list is not a list")

/// The skybox: lazy (outside the boot DAG), built on the first ready(), caches the per-z skybox.
/datum/unit_test/dq_system_skybox

/datum/unit_test/dq_system_skybox/Run()
	TEST_ASSERT(!SSskybox.boots_in_dag(), "a lazy system must stay out of the boot DAG")
	TEST_ASSERT(!(SSskybox in kernel_boot_systems()), "the lazy skybox system is a boot node")
	TEST_ASSERT_EQUAL(SSskybox.ready(), SSskybox, "ready() must return the system")
	assert_system_ported(SSskybox, /datum/system/skybox)
	TEST_ASSERT_EQUAL(length(SSskybox.dust_cache), 26, "the dust appearances were not built")
	TEST_ASSERT(SSskybox.normal_space, "the normal space appearance was not built")
	var/z = run_loc_floor_bottom_left.z
	var/sky = SSskybox.get_skybox(z)
	TEST_ASSERT_NOTNULL(sky, "get_skybox() built nothing for the test z-level")
	TEST_ASSERT_EQUAL(SSskybox.get_skybox(z), sky, "get_skybox() did not cache the skybox")

#endif
