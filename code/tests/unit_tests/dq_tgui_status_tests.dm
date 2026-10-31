// The tgui transport does not poll: a window's status is re-checked when something that decides it changes
// (the user or the host moves, the user's stat/status/client/conditions change, a participant is deleted), a
// window that never reports ready is closed by one timer, and the recurring autoupdate work exists only while
// a window autoupdates.

/// A window with no browser: its status is the user's range to the host and consciousness, and it records what
/// the transport did to it instead of talking to a client.
/datum/tgui/dq_status_probe
	var/probe_closed = 0
	var/probe_sent = 0
	var/probe_range = 1

/datum/tgui/dq_status_probe/ui_participants_alive()
	if(QDELETED(user) || QDELETED(src_object()))
		close()
		return FALSE
	return TRUE

/datum/tgui/dq_status_probe/process_status()
	var/prev_status = status
	if(user.stat)
		status = STATUS_DISABLED
	else if(get_dist(user, src_object()) > probe_range)
		status = STATUS_CLOSE
	else
		status = STATUS_INTERACTIVE
	return prev_status != status

/datum/tgui/dq_status_probe/send_status_update()
	probe_sent++

/datum/tgui/dq_status_probe/close(can_be_suspended = TRUE, logout = FALSE)
	if(closing)
		return
	closing = TRUE
	probe_closed++

/// What the kernel does between a change and the next frame: the observers run at the drain, the queued checks in phase R.
/proc/dq_status_settle()
	rx_drain()
	ui_push_flush()

/datum/unit_test/om/tgui_status_user_leaving_range_closes
/datum/unit_test/om/tgui_status_user_leaving_range_closes/run_om(list/made)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/far = locate(start.x + 4, start.y, start.z)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/obj/item/host = allocate(/obj/item, start)
	var/datum/tgui/dq_status_probe/ui = new(user, host, "Probe")
	ui.status_watch()
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.probe_closed, 0, "a user next to the host keeps the window")
	user.forceMove(far)
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.probe_closed, 1, "walking out of range closes the window without any poll")
	qdel(ui)

/datum/unit_test/om/tgui_status_host_moving_closes
/datum/unit_test/om/tgui_status_host_moving_closes/run_om(list/made)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/far = locate(start.x + 4, start.y, start.z)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/obj/item/host = allocate(/obj/item, start)
	var/datum/tgui/dq_status_probe/ui = new(user, host, "Probe")
	ui.status_watch()
	host.forceMove(far)
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.probe_closed, 1, "the host being carried away closes the window")
	qdel(ui)

/datum/unit_test/om/tgui_status_unconscious_user_is_told
/datum/unit_test/om/tgui_status_unconscious_user_is_told/run_om(list/made)
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/obj/item/host = allocate(/obj/item, start)
	var/datum/tgui/dq_status_probe/ui = new(user, host, "Probe")
	ui.status_watch()
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.probe_sent, 0, "nothing changed: nothing is sent")
	user.set_stat(UNCONSCIOUS)
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.status, STATUS_DISABLED, "knocked out: the window is disabled")
	TEST_ASSERT_EQUAL(ui.probe_sent, 1, "the new status is sent once")
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.probe_sent, 1, "and not again while it holds")
	qdel(ui)

/datum/unit_test/om/tgui_status_deleted_user_closes
/datum/unit_test/om/tgui_status_deleted_user_closes/run_om(list/made)
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/obj/item/host = allocate(/obj/item, start)
	var/datum/tgui/dq_status_probe/ui = new(user, host, "Probe")
	ui.status_watch()
	qdel(user)
	dq_status_settle()
	TEST_ASSERT_EQUAL(ui.probe_closed, 1, "deleting the user closes the window")
	qdel(ui)

/datum/unit_test/om/tgui_ping_timeout_closes_zombie
/datum/unit_test/om/tgui_ping_timeout_closes_zombie/run_om(list/made)
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/obj/item/host = allocate(/obj/item, start)
	var/datum/tgui/dq_status_probe/zombie = new(user, host, "Probe")
	var/datum/tgui/dq_status_probe/answered = new(user, host, "Probe")
	zombie.arm_ping_timeout()
	answered.arm_ping_timeout()
	answered.on_message("ping/reply", list(), list())
	scheduler_advance(TGUI_PING_TIMEOUT / 10 + 1)
	TEST_ASSERT_EQUAL(zombie.probe_closed, 1, "a window that never reported ready is closed by its timer")
	TEST_ASSERT_EQUAL(answered.probe_closed, 0, "a window that answered cancelled its timer")
	qdel(zombie)
	qdel(answered)

/// An idle server runs no tgui work: with no autoupdating window the work item is parked and the system never fires.
/datum/unit_test/tgui_idle_has_no_fires

/datum/unit_test/tgui_idle_has_no_fires/Run()
	var/datum/work_item/W = kernel().work_by_key["[/datum/system/tgui]:refresh_autoupdating"]
	TEST_ASSERT(W, "the autoupdate pass is a registered work item")
	TEST_ASSERT(!length(SStgui.autoupdating), "no window is autoupdating")
	sleep(3 SECONDS)
	TEST_ASSERT(W.parked, "with nothing autoupdating the item parks itself")
	var/before = SStgui.times_fired
	sleep(5 SECONDS)
	TEST_ASSERT_EQUAL(SStgui.times_fired, before, "an idle tgui system does not fire")

/// An autoupdate window still refreshes, and the work parks again once it closes.
/// A pass-counting window that stays interactive: a test mob has no client, whose real status is CLOSE the moment any event
/// re-checks it, and this test is about the autoupdate cadence, not the status.
/datum/tgui/dq_test_probe/interactive/process_status()
	status = STATUS_INTERACTIVE
	return FALSE

/datum/unit_test/tgui_autoupdate_still_refreshes

/datum/unit_test/tgui_autoupdate_still_refreshes/Run()
	var/datum/work_item/W = kernel().work_by_key["[/datum/system/tgui]:refresh_autoupdating"]
	var/mob/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/host = allocate(/obj/item, run_loc_floor_bottom_left)
	var/datum/tgui/dq_test_probe/interactive/ui = new(user, host, "Probe")
	SStgui.on_open(ui)
	ui.set_autoupdate(TRUE)
	TEST_ASSERT(ui in SStgui.autoupdating, "an open autoupdate window joins the pass")
	sleep(3 SECONDS)
	TEST_ASSERT(ui.probe_pushes >= 2, "the autoupdate window was refreshed repeatedly ([ui.probe_pushes])")
	SStgui.on_close(ui)
	TEST_ASSERT(!length(SStgui.autoupdating), "a closed window leaves the pass")
	sleep(3 SECONDS)
	TEST_ASSERT(W.parked, "the pass parks again once nothing autoupdates")
	qdel(ui)
