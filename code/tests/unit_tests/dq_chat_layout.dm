// The chat pane's place: docked in the right-hand split by default, floating on request, and never moved before the
// chat page has loaded (moving it at login stalled the client's other browsers).

/datum/unit_test/dq_chat_layout_defaults_docked
/datum/unit_test/dq_chat_layout_defaults_docked/Run()
	var/datum/preference/toggle/chat_floating/pref = GLOB.preference_entries[/datum/preference/toggle/chat_floating]
	TEST_ASSERT_NOTNULL(pref, "the chat layout preference is registered")
	TEST_ASSERT(!pref.default_value, "the chat is docked unless the player floats it")

/datum/unit_test/dq_chat_layout_params
/datum/unit_test/dq_chat_layout_params/Run()
	var/list/floating = chat_layout_params(TRUE)
	TEST_ASSERT_EQUAL(floating["[SKIN_RPANE_SPLIT].right"], "", "floating frees the split's right side")
	TEST_ASSERT_EQUAL(floating["[SKIN_CHAT_FLOAT_HOST].left"], SKIN_OUTPUT_PANE, "floating hosts the chat pane in the float window")
	TEST_ASSERT_EQUAL(floating["[SKIN_CHAT_FLOAT_WINDOW].is-visible"], "true", "floating shows the window")
	var/list/docked = chat_layout_params(FALSE)
	TEST_ASSERT_EQUAL(docked["[SKIN_RPANE_SPLIT].right"], SKIN_OUTPUT_PANE, "docked puts the chat pane in the split")
	TEST_ASSERT_EQUAL(docked["[SKIN_CHAT_FLOAT_HOST].left"], "", "docked empties the float window")
	TEST_ASSERT_EQUAL(docked["[SKIN_CHAT_FLOAT_WINDOW].is-visible"], "false", "docked hides the window")

/datum/unit_test/dq_chat_layout_moves_only_on_change
/datum/unit_test/dq_chat_layout_moves_only_on_change/Run()
	TEST_ASSERT(!chat_layout_needs_change(FALSE, FALSE), "docked and docked: nothing to move")
	TEST_ASSERT(!chat_layout_needs_change(TRUE, TRUE), "floating and floating: nothing to move")
	TEST_ASSERT(chat_layout_needs_change(TRUE, FALSE), "docked to floating moves the pane")
	TEST_ASSERT(chat_layout_needs_change(FALSE, TRUE), "floating to docked moves the pane")
