/// The lobby panel's own buttons (late_join, observe) pressed by a lobby new_player: neither may be refused before its handler runs (an ALIVE keep
/// a lobby player cannot meet answers "You stop what you were doing."), and observing must not end the op as a refusal once the round is set up.
/datum/unit_test/lobby_panel_observe_join

/datum/unit_test/lobby_panel_observe_join/Run()
	var/mob/new_player/lobbyist = allocate(/mob/new_player)
	var/datum/op_result/join = op_ui_act(lobbyist, lobbyist, "late_join", list())
	TEST_ASSERT(join != null, "the lobby panel's late_join button reaches its op")
	TEST_ASSERT(join.reason != MSG(op/stopped), "late_join is not stopped by a keep a lobby player cannot meet")
	TEST_ASSERT(test_op_committed(join), "late_join reaches its handler (outcome [join.outcome], reason [join.reason])")
	var/datum/op_result/observe = op_ui_act(lobbyist, lobbyist, "observe", list())
	TEST_ASSERT(observe != null, "the lobby panel's observe button reaches its op")
	TEST_ASSERT(observe.reason != MSG(op/stopped), "observe is not stopped by a keep a lobby player cannot meet")
