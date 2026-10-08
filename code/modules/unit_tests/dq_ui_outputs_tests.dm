// The window output lane (doc/rewrite/final_api.html section 7 "outputs, reads, phase R" and section 13 "ui_data(A)"): a window updates because
// its host's ui_data(A) re-runs when something it reads changes, once per frame, and its status (interactive, update-only, closed) is re-checked
// when something that decides it publishes a key. Nothing is called by hand: no SStgui.update_uis(), no changed() mark, no OM wake.

/// A window host with a tracked var its ui_data() shows.
/datum/dq_ui_out_host
	var/shown = 0
	var/other = 0

TRACKED(/datum/dq_ui_out_host, shown)
TRACKED(/datum/dq_ui_out_host, other)

/datum/dq_ui_out_host/ui_data(datum/act/eval/A)
	return list("shown" = shown)

/// A host that declares what its window reads: a write of anything else does not push.
/datum/dq_ui_out_host/exact

/datum/dq_ui_out_host/exact/derived()
	. = ..()
	. += ui_from(nameof(shown))

/// A window stand-in that keeps the real push path (status, then data) and counts what the framework did to it.
/datum/tgui/dq_ui_counter
	var/status_checks = 0
	var/data_sends = 0
	var/status_sends = 0
	var/closed_by_status = 0

/datum/tgui/dq_ui_counter/process_status()
	status_checks++
	return FALSE

/datum/tgui/dq_ui_counter/ui_participants_alive()
	return !QDELETED(user) && !QDELETED(src_object())

/datum/tgui/dq_ui_counter/send_update(custom_data, force)
	data_sends++

/datum/tgui/dq_ui_counter/send_status_update()
	status_sends++

/datum/tgui/dq_ui_counter/close(can_be_suspended = TRUE, logout = FALSE)
	closing = TRUE
	closed_by_status++

/// What the kernel does in a frame, in the order that matters here: the refresh drain marks windows, the observers run, phase R pushes.
/proc/dq_ui_frame()
	refresh_flush()
	rx_drain()
	ui_push_flush()

/// Several tracked writes in one frame: the window is pushed once, however many of its reads changed.
/datum/unit_test/dq_ui_outputs_tracked_write_pushes_once

/datum/unit_test/dq_ui_outputs_tracked_write_pushes_once/Run()
	var/datum/dq_ui_out_host/host = new
	var/datum/tgui/dq_ui_probe/probe = new
	LAZYADD(host.open_tguis, probe)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 0, "nothing changed: nothing is pushed")
	host.set_shown(1)
	host.set_shown(2)
	host.set_shown(3)
	host.set_other(1)
	TEST_ASSERT_EQUAL(probe.pushes, 0, "a write pushes nothing by itself: the push belongs to phase R")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 1, "four writes in a frame: one push")
	TEST_ASSERT_EQUAL(probe.last_owed, UI_PUSH_DATA, "a data push")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 1, "a quiet frame pushes nothing")
	host.set_shown(3)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 1, "a write that changed nothing pushes nothing")
	host.set_shown(4)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 2, "the next change is the next push")
	var/list/data = host.ui_data(null)
	TEST_ASSERT_EQUAL(data["shown"], 4, "and ui_data() is what it shows")
	LAZYREMOVE(host.open_tguis, probe)

/// A host that declares what its window reads pushes for those and nothing else; a window on another host is not touched.
/datum/unit_test/dq_ui_outputs_reads_decide_the_push

/datum/unit_test/dq_ui_outputs_reads_decide_the_push/Run()
	var/datum/dq_ui_out_host/exact/host = new
	var/datum/dq_ui_out_host/bystander = new
	var/datum/tgui/dq_ui_probe/probe = new
	var/datum/tgui/dq_ui_probe/far_probe = new
	LAZYADD(host.open_tguis, probe)
	LAZYADD(bystander.open_tguis, far_probe)
	dq_ui_frame()
	host.set_other(5)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 0, "a var the window does not read does not push it")
	host.set_shown(5)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, 1, "a var it reads does")
	TEST_ASSERT_EQUAL(far_probe.pushes, 0, "and another host's window hears nothing")
	LAZYREMOVE(host.open_tguis, probe)
	LAZYREMOVE(bystander.open_tguis, far_probe)

/// update_uis() and request_push() are requests, not pushes: fifty in a frame are one delivery, and a re-run of the interact is owed.
/datum/unit_test/dq_ui_outputs_requests_coalesce

/datum/unit_test/dq_ui_outputs_requests_coalesce/Run()
	var/datum/tgui/dq_ui_probe/probe = new
	for(var/i in 1 to 50)
		probe.request_push()
	TEST_ASSERT_EQUAL(probe.pushes, 0, "a request delivers nothing by itself")
	ui_push_flush()
	TEST_ASSERT_EQUAL(probe.pushes, 1, "fifty requests: one delivery")
	TEST_ASSERT(probe.last_owed & UI_PUSH_INTERACT, "an update_uis() request owes a re-run of the interact")
	probe.request_push(FALSE)
	ui_push_flush()
	TEST_ASSERT_EQUAL(probe.pushes, 2, "a data request is the next delivery")
	TEST_ASSERT_EQUAL(probe.last_owed, UI_PUSH_DATA, "and owes data only")

/// The user's ability to act (STAT_CAN_ACT) decides a window's status: losing it re-checks the status once, in phase R.
/datum/unit_test/dq_ui_outputs_can_act_rechecks_status

/datum/unit_test/dq_ui_outputs_can_act_rechecks_status/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/host = allocate(/obj/item, T)
	var/datum/cause = allocate(/datum)
	var/datum/tgui/dq_ui_counter/ui = new(user, host, "Probe")
	ui.status_watch()
	dq_ui_frame()
	var/before = ui.status_checks
	hold(user, STAT_CAN_ACT, null, cause)
	TEST_ASSERT_EQUAL(ui.status_checks, before, "a hold re-checks nothing by itself")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(ui.status_checks, before + 1, "losing the ability to act re-checks the status once")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(ui.status_checks, before + 1, "and not again while it holds")
	release(user, STAT_CAN_ACT, cause)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(ui.status_checks, before + 2, "getting it back re-checks it too")
	TEST_ASSERT_EQUAL(ui.data_sends, 0, "a status change is not a data push")
	ui.status_unwatch()
	qdel(ui)

/// Walking, and picking something up, are status events too; many in one frame are one check.
/datum/unit_test/dq_ui_outputs_movement_and_hands_recheck_status

/datum/unit_test/dq_ui_outputs_movement_and_hands_recheck_status/Run()
	var/turf/T = dq_containment_floor()
	var/turf/near = get_step(T, EAST)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/host = allocate(/obj/item, T)
	var/obj/item/tool = allocate(/obj/item, T)
	var/datum/tgui/dq_ui_counter/ui = new(user, host, "Probe")
	ui.status_watch()
	dq_ui_frame()
	var/before = ui.status_checks
	user.forceMove(near)
	user.forceMove(T)
	user.forceMove(near)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(ui.status_checks, before + 1, "three steps in a frame: one check")
	before = ui.status_checks
	host.forceMove(near)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(ui.status_checks, before + 1, "the host moving is a check")
	before = ui.status_checks
	user.put_in_active_hand(tool)
	dq_ui_frame()
	TEST_ASSERT(ui.status_checks > before, "picking something up re-checks the status")
	TEST_ASSERT(ui.status_checks <= before + 1, "once")
	ui.status_unwatch()
	user.forceMove(T)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(ui.status_checks, before + 1, "a window that stopped watching hears nothing")
	qdel(ui)

/// The window holds its host relevant while it is open, and lets go when it closes.
/datum/unit_test/dq_ui_outputs_window_holds_host_relevant

/datum/unit_test/dq_ui_outputs_window_holds_host_relevant/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/host = allocate(/obj/item, T)
	var/datum/tgui/dq_ui_counter/ui = new(user, host, "Probe")
	TEST_ASSERT_NOTEQUAL(stat_value(host, STAT_RELEVANCE), RELEVANCE_WATCHED, "closed: not held")
	ui.status_watch()
	TEST_ASSERT_EQUAL(stat_value(host, STAT_RELEVANCE), RELEVANCE_WATCHED, "open: the host is watched")
	ui.status_unwatch()
	TEST_ASSERT_NOTEQUAL(stat_value(host, STAT_RELEVANCE), RELEVANCE_WATCHED, "closed again: released")
	qdel(ui)
