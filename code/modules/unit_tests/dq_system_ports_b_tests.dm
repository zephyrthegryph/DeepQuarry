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

/// A callable a test can queue as a runechat message: counts its runs.
/datum/dq_runechat_probe
	var/runs = 0

/datum/dq_runechat_probe/proc/finish()
	runs++

/// Runechat: delivered every tick during the game, parked while the queue is empty, woken by a queued message, and a
/// message that went away first is dropped.
/datum/unit_test/dq_system_runechat

/datum/unit_test/dq_system_runechat/Run()
	assert_system_ported(SSrunechat, /datum/system/runechat)
	var/datum/work_item/W = assert_work_declared(SSrunechat, nameof(/datum/system/runechat/proc/deliver_messages), 1, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSrunechat.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "runechat delivers outside the game")
	TEST_ASSERT_EQUAL(SSrunechat.deliver_messages(0), STEP_PARK, "an empty runechat queue must park")
	var/datum/dq_runechat_probe/probe = new
	W.parked = TRUE
	var/list/message = SSrunechat.enqueue(probe, TYPE_PROC_REF(/datum/dq_runechat_probe, finish))
	TEST_ASSERT(!W.parked, "enqueue() did not wake the parked item")
	SSrunechat.dequeue(message)
	TEST_ASSERT_EQUAL(length(SSrunechat.vars["message_queue"]), 0, "dequeue() left the message queued")
	SSrunechat.enqueue(message[1], message[2], message[3])
	var/result = SSrunechat.deliver_messages(0)
	for(var/i in 1 to 20)
		if(result != STEP_YIELD)
			break
		result = SSrunechat.deliver_messages(0)
	TEST_ASSERT_EQUAL(result, STEP_PARK, "a drained queue must park the item")
	TEST_ASSERT_EQUAL(probe.runs, 1, "the queued message was not delivered once")
	W.parked = FALSE
	qdel(probe)

/// The vis overlay cache: expires unused overlays every minute on the background lane; add and remove go through the api.
/datum/unit_test/dq_system_vis_overlays

/datum/unit_test/dq_system_vis_overlays/Run()
	assert_system_ported(SSvis_overlays, /datum/system/vis_overlays)
	assert_work_declared(SSvis_overlays, nameof(/datum/system/vis_overlays/proc/expire_overlays), 1 MINUTE, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SSvis_overlays.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "overlay expiry runs outside the game")
	var/obj/item/thing = allocate(/obj/item)
	var/obj/effect/overlay/vis/first = thing.add_vis_overlay("dq_probe", layer = 1, plane = 1, dir = 2)
	TEST_ASSERT_NOTNULL(first, "add_vis_overlay() made no overlay")
	TEST_ASSERT(first in thing.vis_contents, "the overlay was not added to the thing's vis contents")
	var/obj/effect/overlay/vis/second = thing.add_vis_overlay("dq_probe", layer = 1, plane = 1, dir = 2)
	TEST_ASSERT_EQUAL(second, first, "an identical overlay must come from the cache")
	thing.remove_vis_overlay(first)
	TEST_ASSERT(!(first in thing.vis_contents), "remove_vis_overlay() left the overlay in the vis contents")
	// Called outside a kernel tick, the sweep may find the budget already spent and yield after each
	// item (KERNEL_OVER_BUDGET); it resumes where it left off, so it must finish within one call per entry.
	var/result = SSvis_overlays.expire_overlays(0)
	var/calls = 1
	while(result == STEP_YIELD && calls < 100000)
		result = SSvis_overlays.expire_overlays(0)
		calls++
	TEST_ASSERT_EQUAL(result, STEP_DONE, "an expiry sweep must finish (after [calls] call(s))")

/// Turf cascade: parked until start_cascade(), which wakes it; only one cascade at a time; stopping resets it.
/datum/unit_test/dq_system_turf_cascade

/datum/unit_test/dq_system_turf_cascade/Run()
	assert_system_ported(SSturf_cascade, /datum/system/turf_cascade)
	var/datum/work_item/W = assert_work_declared(SSturf_cascade, nameof(/datum/system/turf_cascade/proc/grow_cascade), 2, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSturf_cascade.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "the cascade grows outside the game")
	TEST_ASSERT_EQUAL(SSturf_cascade.grow_cascade(0), STEP_PARK, "an idle cascade must park")
	W.parked = TRUE
	SSturf_cascade.start_cascade(run_loc_floor_bottom_left, /turf/simulated/floor/plating)
	TEST_ASSERT(!W.parked, "start_cascade() did not wake the parked item")
	TEST_ASSERT(SSturf_cascade.has_work(), "a started cascade has work")
	SSturf_cascade.start_cascade(run_loc_floor_top_right, /turf/simulated/wall)
	TEST_ASSERT_EQUAL(length(SSturf_cascade.vars["remaining_turf"]), 1, "a second cascade started while one was running")
	SSturf_cascade.stop_cascade()
	TEST_ASSERT(!SSturf_cascade.has_work(), "stop_cascade() left the cascade running")
	TEST_ASSERT_EQUAL(SSturf_cascade.grow_cascade(0), STEP_PARK, "a stopped cascade must park")
	W.parked = FALSE

/// The cascade walks its lists by index: a step converts the turf it started on, takes its neighbours into the waiting list, and leaves the cursor at rest.
/datum/unit_test/dq_system_turf_cascade_steps

/datum/unit_test/dq_system_turf_cascade_steps/Run()
	var/turf/start = test_floor()
	var/original = start.type
	SSturf_cascade.vars["next_group_time"] = 0
	SSturf_cascade.start_cascade(start, /turf/simulated/floor/plating)
	TEST_ASSERT(SSturf_cascade.has_work(), "a started cascade has work")
	var/steps = 0
	while(SSturf_cascade.grow_cascade(0) == STEP_YIELD && steps++ < 50)
		continue
	var/turf/after_step = locate(start.x, start.y, start.z)
	var/converted = after_step.type == /turf/simulated/floor/plating
	var/waiting = length(SSturf_cascade.vars["remaining_turf"])
	var/cursor = SSturf_cascade.vars["run_at"]
	SSturf_cascade.stop_cascade()
	after_step.ChangeTurf(original)
	TEST_ASSERT(converted, "the first step converted the turf the cascade started on")
	TEST_ASSERT(waiting > 0, "and queued its neighbours to convert next")
	TEST_ASSERT_EQUAL(cursor, 0, "a finished step leaves the index cursor at rest")
	TEST_ASSERT_EQUAL(SSturf_cascade.vars["run_at"], 0, "stopping resets it too")

/// Radio: boots after atoms, owns the frequencies; devices join and leave through the api and an emptied frequency goes.
/datum/unit_test/dq_system_radio

/datum/unit_test/dq_system_radio/Run()
	assert_system_ported(SSradio, /datum/system/radio)
	TEST_ASSERT(/datum/system/atoms in SSradio.needs, "the radio system boots after atoms")
	TEST_ASSERT_NOTNULL(GLOB.autospeaker, "the global announcer was not set up at boot")
	var/frequency = 1337
	var/obj/item/device = allocate(/obj/item)
	var/datum/radio_frequency/joined = SSradio.add_object(device, frequency, RADIO_CHAT)
	TEST_ASSERT_NOTNULL(joined, "add_object() answered no frequency")
	TEST_ASSERT_EQUAL(SSradio.return_frequency(frequency), joined, "return_frequency() answered a different datum")
	TEST_ASSERT(device in joined.devices[RADIO_CHAT], "the device did not join its filter")
	SSradio.remove_object(device, frequency)
	TEST_ASSERT_NULL(SSradio.frequencies["[frequency]"], "an emptied frequency was kept")

/// Radiation: pulses are queued through the api, a step drains them, a disabled system queues none, and a step goes in the
/// game and the postgame.
/datum/unit_test/dq_system_radiation

/datum/unit_test/dq_system_radiation/Run()
	assert_system_ported(SSradiation, /datum/system/radiation)
	assert_work_declared(SSradiation, nameof(/datum/system/radiation/proc/radiation_step), 0.5 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSradiation.periodic_runlevels, RUNLEVELS_DEFAULT, "radiation runs in the lobby")
	TEST_ASSERT(SSradiation.is_enabled(), "radiation is disabled")
	TEST_ASSERT(islist(SSradiation.performance_diagnostics()), "performance_diagnostics() must answer a list")
	TEST_ASSERT_EQUAL(SSradiation.radiation_step(0), STEP_DONE, "an idle radiation step must finish")
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT(SSradiation.irradiate(target, 0), "irradiate() refused a plain target")

/// Planets: boot after mapping, apply queued sun and temperature updates every 2 s on the background lane, park when there is
/// nothing to apply and wake on queued work.
/datum/unit_test/dq_system_planets

/datum/unit_test/dq_system_planets/Run()
	assert_system_ported(SSplanets, /datum/system/planets)
	TEST_ASSERT(/datum/system/mapping in SSplanets.needs, "planets boot after mapping")
	var/datum/work_item/W = assert_work_declared(SSplanets, nameof(/datum/system/planets/proc/apply_updates), 2 SECONDS, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SSplanets.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "planet updates run outside the game")
	TEST_ASSERT_EQUAL(SSplanets.apply_updates(0), STEP_PARK, "an idle planet system must park")
	W.parked = TRUE
	SSplanets.wake_updates()
	TEST_ASSERT(W.parked, "waking with nothing queued must leave the item parked")
	TEST_ASSERT(islist(SSplanets.planets), "the planet list is not a list")
	TEST_ASSERT(SSplants.initialized, "the plant system is set up by the planet system's initialize()")
	W.parked = FALSE

/// Plants: a lazy system outside the boot DAG with the seed tables, growing plants join the registry and the growth lane
/// through the api.
/datum/unit_test/dq_system_plants

/datum/unit_test/dq_system_plants/Run()
	TEST_ASSERT(!SSplants.boots_in_dag(), "a lazy system must stay out of the boot DAG")
	TEST_ASSERT(!(SSplants in kernel_boot_systems()), "the lazy plant system is a boot node")
	TEST_ASSERT_EQUAL(SSplants.ready(), SSplants, "ready() must return the system")
	assert_system_ported(SSplants, /datum/system/plants)
	TEST_ASSERT(length(SSplants.seeds), "the plant system has no seeds")
	TEST_ASSERT(length(SSplants.gene_tag_masks), "the plant system has no gene masks")
	var/lines = length(SSplants.seeds)
	var/datum/seed/random = SSplants.create_random_seed(TRUE)
	TEST_ASSERT_NOTNULL(random, "create_random_seed() made no seed")
	TEST_ASSERT_EQUAL(length(SSplants.seeds), lines + 1, "the random seed was not filed")
	SSplants.seeds -= random.name
	qdel(random)

/// Sounds: a lazy system, channels are reserved for a datum and freed with it, random channels come from the free ones and the
/// talk sound table is built.
/datum/unit_test/dq_system_sounds

/datum/unit_test/dq_system_sounds/Run()
	TEST_ASSERT(!SSsounds.boots_in_dag(), "a lazy system must stay out of the boot DAG")
	TEST_ASSERT(!(SSsounds in kernel_boot_systems()), "the lazy sound system is a boot node")
	TEST_ASSERT_EQUAL(SSsounds.ready(), SSsounds, "ready() must return the system")
	assert_system_ported(SSsounds, /datum/system/sounds)
	TEST_ASSERT(length(SSsounds.talk_sound_sets()), "the sound system has no talk sounds")
	TEST_ASSERT(islist(SSsounds.talk_sound("beep-boop")), "the default talk sound set is missing")
	TEST_ASSERT(SSsounds.random_available_channel(), "the sound system handed out no channel")
	TEST_ASSERT(istext(SSsounds.random_available_channel_text()), "the textual channel is not text")
	var/left = SSsounds.available_channels_left()
	var/datum/holder = allocate(/datum)
	var/channel = SSsounds.reserve_sound_channel(holder)
	TEST_ASSERT(channel, "no channel was reserved for the datum")
	TEST_ASSERT(SSsounds.vars["reserved_channels"]["[channel]"], "the reserved channel is not recorded")
	SSsounds.free_datum_channels(holder)
	TEST_ASSERT_NULL(SSsounds.vars["reserved_channels"]["[channel]"], "freeing the datum's channels left the reservation")
	TEST_ASSERT_EQUAL(SSsounds.available_channels_left(), left, "reserving and freeing changed the free channel count")

/// Transcore: boots after mapping, scans every 3 minutes in the game on the background lane, the databases answer by key and
/// by mind name through the api.
/datum/unit_test/dq_system_transcore

/datum/unit_test/dq_system_transcore/Run()
	assert_system_ported(SStranscore, /datum/system/transcore)
	TEST_ASSERT(/datum/system/mapping in SStranscore.needs, "transcore boots after mapping")
	assert_work_declared(SStranscore, nameof(/datum/system/transcore/proc/scan_step), 3 MINUTES, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SStranscore.periodic_runlevels, RUNLEVEL_GAME, "transcore scans outside the game")
	TEST_ASSERT(length(SStranscore.databases), "transcore has no databases")
	TEST_ASSERT_EQUAL(SStranscore.db_by_key(null), SStranscore.default_db, "the null key must answer the default database")
	TEST_ASSERT_EQUAL(SStranscore.db_by_key("default"), SStranscore.default_db, "the default key must answer the default database")
	TEST_ASSERT_NULL(SStranscore.db_by_mind_name("dq nobody"), "an unknown mind has no database")
	var/result = SStranscore.scan_step(0)
	for(var/i in 1 to 50) // a test tick is always over budget: the scan yields between records
		if(result != STEP_YIELD)
			break
		result = SStranscore.scan_step(0)
	TEST_ASSERT_EQUAL(result, STEP_DONE, "the transcore scan did not finish")

/// Stat panels: every 4 ticks in the lobby and the game, a pass with no clients finishes.
/datum/unit_test/dq_system_statpanels

/datum/unit_test/dq_system_statpanels/Run()
	assert_system_ported(SSstatpanels, /datum/system/statpanels)
	assert_work_declared(SSstatpanels, nameof(/datum/system/statpanels/proc/refresh_tabs), 4, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSstatpanels.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "stat panels lost their lobby runlevel")
	var/fires = SSstatpanels.num_fires
	TEST_ASSERT_EQUAL(SSstatpanels.refresh_tabs(0), STEP_DONE, "a pass with no clients must finish")
	TEST_ASSERT_EQUAL(SSstatpanels.num_fires, fires + 1, "the pass did not count itself")

/// Research: boots after mapping, adds income and runs the research queue every second, serves nodes and designs by id (the
/// error placeholder when unknown) and registers techwebs through the api.
/datum/unit_test/dq_system_research

/datum/unit_test/dq_system_research/Run()
	assert_system_ported(SSresearch, /datum/system/research)
	TEST_ASSERT(/datum/system/mapping in SSresearch.needs, "research boots after mapping")
	assert_work_declared(SSresearch, nameof(/datum/system/research/proc/income_step), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSresearch.periodic_runlevels, RUNLEVELS_DEFAULT, "research income runs in the lobby")
	TEST_ASSERT(length(SSresearch.techweb_nodes), "research has no nodes")
	TEST_ASSERT(length(SSresearch.techweb_designs), "research has no designs")
	var/node_id = SSresearch.techweb_nodes[1]
	TEST_ASSERT_EQUAL(SSresearch.techweb_node_by_id(node_id), SSresearch.techweb_nodes[node_id], "techweb_node_by_id() did not answer the node")
	TEST_ASSERT_EQUAL(SSresearch.techweb_node_by_id("dq_missing"), SSresearch.error_node, "an unknown node must answer the error node")
	TEST_ASSERT_EQUAL(SSresearch.techweb_design_by_id("dq_missing"), SSresearch.error_design, "an unknown design must answer the error design")
	var/datum/techweb/web = locate_in_list(SSresearch.techwebs, /datum/techweb/science)
	TEST_ASSERT_NOTNULL(web, "the science techweb is not registered")
	TEST_ASSERT_EQUAL(SSresearch.register_techweb(web), web, "register_techweb() must answer the web")
	TEST_ASSERT_EQUAL(SSresearch.income_step(0), STEP_DONE, "an income step must finish")

/// Supply: boots after mapping, one market and payroll pass every 20 s, packs built at boot, the price helpers answer.
/datum/unit_test/dq_system_supply

/datum/unit_test/dq_system_supply/Run()
	assert_system_ported(SSsupply, /datum/system/supply)
	TEST_ASSERT(/datum/system/mapping in SSsupply.needs, "supply boots after mapping")
	assert_work_declared(SSsupply, nameof(/datum/system/supply/proc/supply_step), 20 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSsupply.periodic_runlevels, RUNLEVELS_DEFAULT, "the supply cycle runs in the lobby")
	TEST_ASSERT(length(SSsupply.supply_pack), "supply has no packs")
	var/pack_name = SSsupply.supply_pack[1]
	var/datum/supply_pack/pack = SSsupply.supply_pack[pack_name]
	TEST_ASSERT_EQUAL(SSsupply.pack_price(pack), max(1, round(pack.cost * 50)), "pack_price() lost its conversion")
	TEST_ASSERT_EQUAL(SSsupply.export_revenue(4), 4 * 50, "export_revenue() lost its conversion")

/// Server metrics: boots with no needs, samples every METRICS_SAMPLE_INTERVAL on the background lane, an idle sample step
/// finishes, events are buffered through the api only while recording.
/datum/unit_test/dq_system_server_metrics

/datum/unit_test/dq_system_server_metrics/Run()
	assert_system_ported(SSserver_metrics, /datum/system/server_metrics)
	assert_work_declared(SSserver_metrics, nameof(/datum/system/server_metrics/proc/sample_step), METRICS_SAMPLE_INTERVAL, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SSserver_metrics.periodic_runlevels, RUNLEVELS_DEFAULT, "metrics sample in the lobby")
	TEST_ASSERT(length(SSserver_metrics.sources), "metrics have no sources")
	TEST_ASSERT(isnum(SSserver_metrics.boot_realtime), "the boot time was not taken in preinit()")
	TEST_ASSERT_EQUAL(SSserver_metrics.sample_step(0), STEP_DONE, "an idle metrics step must finish")

#endif
