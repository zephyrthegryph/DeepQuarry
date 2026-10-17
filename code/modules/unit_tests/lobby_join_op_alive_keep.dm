/// A player in the lobby (a new_player, never conscious) joins through the late-join window op: the op's default ALIVE keep must not end it with
/// "You stop what you were doing." before its handler runs.
/datum/unit_test/lobby_join_op_alive_keep

/datum/unit_test/lobby_join_op_alive_keep/Run()
	var/old_allowed = CONFIG_GET(flag/enter_allowed)
	CONFIG_SET(flag/enter_allowed, FALSE) // the handler refuses with a message: the test needs the op to reach it, not to spawn anyone
	var/mob/new_player/lobbyist = allocate(/mob/new_player)
	var/datum/tgui_module/late_choices/module = allocate(/datum/tgui_module/late_choices, lobbyist)
	var/datum/tgui/window = allocate(/datum/tgui, lobbyist, module, module.ui_interface(lobbyist))
	TEST_ASSERT_EQUAL(window.status, STATUS_INTERACTIVE, "the lobby player's late-join window is interactive")
	var/datum/op_result/result = op_ui_act(lobbyist, module, "join", list("job" = JOB_ALT_VISITOR), pressed_in = window)
	CONFIG_SET(flag/enter_allowed, old_allowed)
	TEST_ASSERT(result != null, "the join button reaches its op")
	TEST_ASSERT(result.reason != MSG(op/stopped), "a lobby player's join is not stopped by an ALIVE keep the lobby player cannot meet")
	TEST_ASSERT(test_op_committed(result), "the join op reaches its handler")
