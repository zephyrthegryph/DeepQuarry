// The chat's pane as the whole right-hand column (code/content/client/chat_column.dm), the map split, and the radio rows.
/datum/unit_test/dq_chat_pane_is_the_column
/datum/unit_test/dq_chat_pane_is_the_column/Run()
	TEST_ASSERT(chat_pane_is_column("left=[SKIN_OUTPUT_PANE];right="), "the skin's own layout: the chat pane alone is the column")
	TEST_ASSERT(!chat_pane_is_column("left=[SKIN_STAT_PANE];right=[SKIN_OUTPUT_PANE]"), "an older layout with the stat pane is re-seated")
	TEST_ASSERT(!chat_pane_is_column(null), "an unreadable report is re-seated")
	TEST_ASSERT_EQUAL(chat_pane_column_params(), "[SKIN_RPANE_SPLIT].left=;[SKIN_RPANE_SPLIT].right=;[SKIN_RPANE_SPLIT].left=[SKIN_OUTPUT_PANE];[SKIN_RPANE_SPLIT].splitter=100", "both sides emptied first (a pane lives in one place), then the chat pane fills the split")

/datum/unit_test/dq_chat_map_split_pref_range
/datum/unit_test/dq_chat_map_split_pref_range/Run()
	var/datum/preference/numeric/map_split/pref = GLOB.preference_entries[/datum/preference/numeric/map_split]
	TEST_ASSERT_NOTNULL(pref, "the map split preference exists")
	TEST_ASSERT_EQUAL(pref.create_default_value(), 0, "unset by default: the viewport fit picks the width")
	TEST_ASSERT(pref.is_valid(MAP_SPLIT_MIN) && pref.is_valid(MAP_SPLIT_MAX) && pref.is_valid(0), "the kept range is valid")
	TEST_ASSERT(!pref.is_valid(MAP_SPLIT_MAX + 1), "past the range is not")

/datum/unit_test/dq_chat_radio_rows
/datum/unit_test/dq_chat_radio_rows/Run()
	TEST_ASSERT_EQUAL(length(chat_radio_rows(list())), 0, "no channels, no selector rows")
	var/list/rows = chat_radio_rows(list(CHANNEL_MEDICAL, CHANNEL_COMMAND))
	TEST_ASSERT_EQUAL(length(rows), 3, "department plus one row per channel")
	TEST_ASSERT_EQUAL(rows[1]["key"], ":h", "the department key is first")
	TEST_ASSERT_EQUAL(rows[2]["key"], ":m", "medical has :m")
	TEST_ASSERT_EQUAL(rows[2]["label"], CHANNEL_MEDICAL, "the label is the channel name")
	TEST_ASSERT_EQUAL(rows[3]["key"], ":c", "command has :c")
	TEST_ASSERT_EQUAL(length(chat_radio_rows(list(CHANNEL_MEDICAL, CHANNEL_MEDICAL))), 2, "a repeated channel is listed once")
