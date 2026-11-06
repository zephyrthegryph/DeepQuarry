// The ghost panel (code/content/mob/dead/observer/ghost_panel.dm): the Ghost tab's verbs are one window now.

/// The panel for a ghost standing on the test floor.
/datum/unit_test/proc/dq_ghost_panel_for(mob/observer/dead/ghost)
	return new /datum/ghost_panel(ghost)

/// Every ghost command is a row of the window: all the actions in their groups and all the toggles.
/datum/unit_test/dq_ghost_panel_lists_every_command

/datum/unit_test/dq_ghost_panel_lists_every_command/Run()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, test_floor())
	var/datum/ghost_panel/panel = dq_ghost_panel_for(ghost)
	var/list/data = panel.ui_data(null)
	var/list/ids = list()
	for(var/list/group as anything in data["groups"])
		for(var/list/action as anything in group["actions"])
			ids[action["id"]] = TRUE
	for(var/id in list(GHOST_ACT_REENTER, GHOST_ACT_TELEPORT, GHOST_ACT_FOLLOW, GHOST_ACT_JUMP, GHOST_ACT_AIR, GHOST_ACT_MANIFEST, GHOST_ACT_DOODLE,
			GHOST_ACT_RESPAWN, GHOST_ACT_BACKUP_PING, GHOST_ACT_BACKUP_DELAY, GHOST_ACT_SPAWN_MENU, GHOST_ACT_RESLEEVER, GHOST_ACT_TEXT_COMM,
			GHOST_ACT_CALL_COMM, GHOST_ACT_PAI_ALERT, GHOST_ACT_SPRITE))
		TEST_ASSERT(ids[id], "the window offers [id]")
	var/list/toggle_ids = list()
	for(var/list/toggle as anything in data["toggles"])
		toggle_ids[toggle["id"]] = TRUE
	for(var/id in list(GHOST_SET_INQUISITIVE, GHOST_SET_MEDHUD, GHOST_SET_SECHUD, GHOST_SET_ANTAGHUD, GHOST_SET_INTERACTIONS, GHOST_SET_VISIBILITY,
			GHOST_SET_ANONSAY, GHOST_SET_GHOSTSEE, GHOST_SET_DARKNESS))
		TEST_ASSERT(toggle_ids[id], "the window offers the setting [id]")
	var/list/reenter
	for(var/list/group as anything in data["groups"])
		for(var/list/action as anything in group["actions"])
			if(action["id"] == GHOST_ACT_REENTER)
				reenter = action
	TEST_ASSERT(reenter && !reenter["enabled"], "a ghost with no body cannot re-enter one, and the window says so")
	qdel(panel)

/// A setting button flips the ghost's setting and the window shows it; another mob or an unknown action does nothing.
/datum/unit_test/dq_ghost_panel_toggles_settings

/datum/unit_test/dq_ghost_panel_toggles_settings/Run()
	var/turf/T = test_floor()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	var/mob/observer/dead/other = allocate(/mob/observer/dead, T)
	var/datum/ghost_panel/panel = dq_ghost_panel_for(ghost)
	var/before = ghost.medHUD
	TEST_ASSERT(panel.run_action(ghost, GHOST_SET_MEDHUD), "the ghost's own press runs")
	TEST_ASSERT_EQUAL(!!ghost.medHUD, !before, "and flips the medical HUD")
	var/shown
	for(var/list/toggle as anything in panel.ui_data(null)["toggles"])
		if(toggle["id"] == GHOST_SET_MEDHUD)
			shown = toggle["value"]
	TEST_ASSERT_EQUAL(!!shown, !!ghost.medHUD, "the window reads the new state")
	var/anon = ghost.anonsay
	TEST_ASSERT(panel.run_action(ghost, GHOST_SET_ANONSAY), "anonymous chat toggles")
	TEST_ASSERT_EQUAL(!!ghost.anonsay, !anon, "and flips")
	TEST_ASSERT(!panel.run_action(other, GHOST_SET_MEDHUD), "another ghost cannot press this ghost's buttons")
	TEST_ASSERT(!panel.run_action(ghost, "no_such_action"), "an unknown action is refused")
	qdel(panel)
