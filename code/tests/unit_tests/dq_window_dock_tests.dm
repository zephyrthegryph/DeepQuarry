// The window dock (doc/rewrite/proposals/window_system.md, code/library/ui/window_dock/window_dock.dm): a docked window off screen gets
// no data, a shown one catches up, the saved layout says which interfaces dock, and the panel's ids route only to the client's own
// docked windows.

/// A window with no browser whose status always holds: it counts the full updates it is sent.
/datum/tgui/dq_dock_probe
	var/probe_full = 0

/datum/tgui/dq_dock_probe/ui_participants_alive()
	return TRUE

/datum/tgui/dq_dock_probe/process_status()
	status = STATUS_INTERACTIVE
	return FALSE

/datum/tgui/dq_dock_probe/send_full_update(custom_data, force)
	if(view_hidden)
		view_stale = TRUE
		return
	probe_full++

/datum/tgui/dq_dock_probe/close(can_be_suspended = TRUE, logout = FALSE)
	closing = TRUE

/datum/unit_test/dq_window_dock_hidden_gets_no_push
/datum/unit_test/dq_window_dock_hidden_gets_no_push/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/host = allocate(/obj/item, run_loc_floor_bottom_left)
	var/datum/tgui/dq_dock_probe/ui = new(user, host, "Probe")
	ui.docked = TRUE
	ui.dock_hide(TRUE)
	var/before = GLOB.ui_push_count
	TEST_ASSERT(!ui.push_coalesced(UI_PUSH_DATA), "a hidden window's data push does not go out")
	TEST_ASSERT(!ui.push_coalesced(UI_PUSH_INTERACT), "nor does a re-run of its interact")
	TEST_ASSERT_EQUAL(GLOB.ui_push_count, before, "no ui_data() ran for it")
	TEST_ASSERT(ui.view_stale, "it is owed an update")
	ui.send_full_update()
	TEST_ASSERT_EQUAL(ui.probe_full, 0, "a full update waits too")
	ui.dock_hide(FALSE)
	TEST_ASSERT_EQUAL(ui.probe_full, 1, "shown again, it gets one full update")
	TEST_ASSERT(!ui.view_stale, "and owes nothing")
	ui.dock_hide(FALSE)
	TEST_ASSERT_EQUAL(ui.probe_full, 1, "showing a shown window sends nothing")
	ui.dock_hide(TRUE)
	ui.dock_hide(FALSE)
	TEST_ASSERT_EQUAL(ui.probe_full, 1, "hidden and shown with nothing owed: nothing sent")
	qdel(ui)

/datum/unit_test/dq_window_dock_saved_layout
/datum/unit_test/dq_window_dock_saved_layout/Run()
	var/list/wanted = window_dock_wanted(@'{"APC":{"dock":true,"group":"g1"},"Vending":{"dock":false,"group":"g2"},"Junk":4}')
	TEST_ASSERT(wanted["APC"], "a docked interface starts docked")
	TEST_ASSERT(!wanted["Vending"], "a floated one does not")
	TEST_ASSERT(!wanted["Junk"], "a malformed entry is ignored")
	TEST_ASSERT_EQUAL(length(window_dock_wanted("not json")), 0, "junk text docks nothing")
	TEST_ASSERT_EQUAL(length(window_dock_wanted(null)), 0, "an unset layout docks nothing")
	TEST_ASSERT(("Vending" in wanted) && !wanted["Vending"], "a floated interface is remembered as floating, not forgotten")
	TEST_ASSERT(!("Junk" in wanted), "a malformed entry says nothing")
	var/datum/window_dock/dock = new(null)
	TEST_ASSERT(dock.wants("StatPanel"), "the stat panel opens docked by default")
	TEST_ASSERT(!dock.wants("Vending"), "an interface with no saved word floats")
	dock.wants_cache = list("StatPanel" = FALSE)
	TEST_ASSERT(!dock.wants("StatPanel"), "a stat panel the player floated stays floating")
	qdel(dock)

/datum/unit_test/dq_window_dock_routing
/datum/unit_test/dq_window_dock_routing/Run()
	TEST_ASSERT(GLOB.window_dock_modal_interfaces["AlertModal"], "alerts stay separate windows")
	TEST_ASSERT(GLOB.window_dock_modal_interfaces["TextInputModal"], "text prompts stay separate windows")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/host = allocate(/obj/item, run_loc_floor_bottom_left)
	var/datum/tgui/dq_dock_probe/ui = new(user, host, "Probe")
	TEST_ASSERT(ui.dockable_interface(), "an ordinary interface may live in the column")
	TEST_ASSERT(!ui.dockable(), "but a UI with no window can neither dock nor float")
	TEST_ASSERT_NULL(ui.dock_window(), "with no client the column has no window for it")
	var/datum/window_dock/dock = new(null)
	TEST_ASSERT(!dock.dock(ui), "an undockable window is refused")
	TEST_ASSERT(!ui.docked, "and stays floating")
	dock.drop_answer(list("wid" = "tgui-window-1", "index" = 0))
	dock.drop_answer(list("wid" = 5))
	TEST_ASSERT(!ui.closing, "a drop answer for a window that is not the client's does nothing")
	TEST_ASSERT(!column_route(null, list("wid" = "statbrowser", "type" = "ready")), "a column message with no client routes nowhere")
	qdel(dock)
	qdel(ui)

/datum/unit_test/dq_window_dock_points
/datum/unit_test/dq_window_dock_points/Run()
	TEST_ASSERT_EQUAL(dock_point_text(list("x" = 120.4, "y" = -30)), "120,-30", "a page point becomes screen text")
	TEST_ASSERT_NULL(dock_point_text(list("x" = "1", "y" = 2)), "a point that is not two numbers is dropped")
	TEST_ASSERT_NULL(dock_point_text("5,5"), "so is anything that is not a point")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/host = allocate(/obj/item, run_loc_floor_bottom_left)
	var/datum/tgui/dq_dock_probe/ui = new(user, host, "Probe")
	var/datum/window_dock/dock = new(null)
	TEST_ASSERT(!dock.undock(ui, "300,40"), "a floating window has nothing to float out of")
	ui.docked = TRUE
	TEST_ASSERT(dock.undock(ui, "300,40"), "a docked window floats (reopened by its host)")
	TEST_ASSERT(ui.closing, "the column copy closes")
	qdel(dock)
	qdel(ui)

/datum/unit_test/dq_window_dock_view_from_column
/datum/unit_test/dq_window_dock_view_from_column/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/host = allocate(/obj/item, run_loc_floor_bottom_left)
	var/datum/tgui/dq_dock_probe/ui = new(user, host, "Probe")
	ui.dock_message("wm/view", list("hidden" = TRUE))
	TEST_ASSERT(!ui.view_hidden, "a floating window ignores the column's view report")
	ui.docked = TRUE
	ui.dock_message("wm/view", list("hidden" = TRUE))
	TEST_ASSERT(ui.view_hidden, "a collapsed or background docked window stops getting data")
	ui.send_full_update()
	TEST_ASSERT_EQUAL(ui.probe_full, 0, "its updates wait")
	ui.dock_message("wm/view", list("hidden" = FALSE))
	TEST_ASSERT(!ui.view_hidden, "shown again")
	TEST_ASSERT_EQUAL(ui.probe_full, 1, "it gets one fresh update")
	qdel(ui)

/datum/unit_test/dq_stat_panel_raw_messages
/datum/unit_test/dq_stat_panel_raw_messages/Run()
	var/datum/stat_panel_ui/panel = new(null)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT(!panel.ui_raw_message(user, "Set-Tab", list("tab" = "Status")), "a panel with no client handles nothing")
	TEST_ASSERT(!panel.ui_prepare(user, null), "and opens for no one")
	var/datum/stat_panel_ui/host = new(null)
	TEST_ASSERT(!host.ui_raw_message(null, "Update-Verbs", null), "a message with no user goes nowhere")
	qdel(host)
	qdel(panel)
