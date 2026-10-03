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

#endif
