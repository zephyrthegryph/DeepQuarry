// TGUI push model and client session: pushes are coalesced, data pushes carry the slim
// config, and asset flushes are released by the client's ack (or a timeout), not by polling.

/// A tgui that counts the pushes it is asked to make, instead of touching a window.
/datum/tgui/dq_test_probe
	var/probe_pushes = 0

/datum/tgui/dq_test_probe/process(force = FALSE)
	probe_pushes++

/datum/om_test_entity/proc/asset_cb(amount)
	ticks += amount

/datum/unit_test/om/tgui_update_uis_coalesces
/datum/unit_test/om/tgui_update_uis_coalesces/run_om(list/made)
	test_driver_begin()
	var/datum/om_test_entity/host = entity(made)
	var/mob/user = new /mob
	var/datum/tgui/dq_test_probe/ui = new(user, host, "Probe")
	SStgui.on_open(ui)
	SStgui.update_uis(host)
	SStgui.update_uis(host)
	SStgui.update_uis(host)
	TEST_ASSERT_EQUAL(ui.probe_pushes, 0, "update_uis() does not push inline")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(ui.probe_pushes, 1, "three update_uis() calls make one push in the next presentation phase")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(ui.probe_pushes, 1, "nothing is pushed again while nothing asked")
	SStgui.update_uis(host)
	SStgui.update_uis(host)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(ui.probe_pushes, 2, "a second burst is again one push")
	SStgui.update_uis(host, ui)
	TEST_ASSERT_EQUAL(ui.probe_pushes, 3, "the acting UI is pushed inline")
	SStgui.on_close(ui)
	qdel(ui)
	qdel(user)
	test_driver_end()

/datum/unit_test/om/tgui_data_push_uses_slim_config
/datum/unit_test/om/tgui_data_push_uses_slim_config/run_om(list/made)
	var/datum/om_test_entity/host = entity(made)
	var/mob/user = new /mob
	var/datum/tgui/ui = new(user, host, "Probe", "Probe title")
	var/list/payload = ui.get_payload(with_data = TRUE)
	var/list/config = payload["config"]
	TEST_ASSERT_EQUAL(config["title"], "Probe title", "the slim config carries the title")
	TEST_ASSERT(!isnull(config["status"]), "the slim config carries the status")
	TEST_ASSERT(isnull(config["window"]), "the slim config has no window block")
	TEST_ASSERT(isnull(config["client"]), "the slim config has no client block")
	TEST_ASSERT(isnull(config["interface"]), "the slim config has no interface block")
	qdel(ui)
	qdel(user)

/datum/unit_test/om/client_session_ack_releases_waiter
/datum/unit_test/om/client_session_ack_releases_waiter/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/client_session/session = new(null)
	var/job = session.flush_assets(E, TYPE_PROC_REF(/datum/om_test_entity, asset_cb), 5)
	TEST_ASSERT_EQUAL(E.ticks, 0, "the waiter does not run before the ack")
	TEST_ASSERT_NULL(session.confirm_asset_arrival("[job]"), "a valid ack is consumed")
	TEST_ASSERT_EQUAL(E.ticks, 5, "the ack runs the waiter")
	TEST_ASSERT(session.confirm_asset_arrival("[job]"), "a repeated ack is rejected")
	TEST_ASSERT(session.confirm_asset_arrival("9999"), "an ack for a job never sent is rejected")
	TEST_ASSERT_EQUAL(E.ticks, 5, "the waiter runs once")
	scheduler_advance(6)
	TEST_ASSERT_EQUAL(E.ticks, 5, "the timeout of an acked job does nothing")
	qdel(session)

/datum/unit_test/om/client_session_timeout_releases_waiter
/datum/unit_test/om/client_session_timeout_releases_waiter/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/client_session/session = new(null)
	session.flush_assets(E, TYPE_PROC_REF(/datum/om_test_entity, asset_cb), 3)
	scheduler_advance(4)
	TEST_ASSERT_EQUAL(E.ticks, 0, "still waiting inside the timeout")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(E.ticks, 3, "a client that never answers releases the waiter at the timeout")
	qdel(session)
