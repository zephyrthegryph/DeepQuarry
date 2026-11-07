// The chat pane's place: pinned to the bottom or top of the right-hand column (the stat panel taking the rest) or floating,
// and never moved before the chat page has loaded (moving it at login stalled the client's other browsers).

/datum/unit_test/dq_chat_layout_defaults
/datum/unit_test/dq_chat_layout_defaults/Run()
	var/datum/preference/toggle/chat_floating/floating = GLOB.preference_entries[/datum/preference/toggle/chat_floating]
	TEST_ASSERT_NOTNULL(floating, "the float preference is registered")
	TEST_ASSERT(!floating.default_value, "the chat is pinned unless the player floats it")
	var/datum/preference/choiced/chat_dock_side/side = GLOB.preference_entries[/datum/preference/choiced/chat_dock_side]
	TEST_ASSERT_NOTNULL(side, "the dock side preference is registered")
	TEST_ASSERT_EQUAL(side.create_default_value(), CHAT_DOCK_BOTTOM_RIGHT, "the chat pins bottom right by default")
	var/datum/preference/numeric/chat_share/share = GLOB.preference_entries[/datum/preference/numeric/chat_share]
	TEST_ASSERT_NOTNULL(share, "the share preference is registered")
	TEST_ASSERT_EQUAL(share.create_default_value(), CHAT_SHARE_DEFAULT, "the chat takes its default share")
	TEST_ASSERT(CHAT_SHARE_DEFAULT >= 40, "the default share is about 40% of the column")

/datum/unit_test/dq_chat_layout_mode_from_prefs
/datum/unit_test/dq_chat_layout_mode_from_prefs/Run()
	TEST_ASSERT_EQUAL(chat_mode_for(FALSE, CHAT_DOCK_BOTTOM_RIGHT), CHAT_MODE_BOTTOM, "bottom right")
	TEST_ASSERT_EQUAL(chat_mode_for(FALSE, CHAT_DOCK_TOP_RIGHT), CHAT_MODE_TOP, "top right")
	TEST_ASSERT_EQUAL(chat_mode_for(TRUE, CHAT_DOCK_TOP_RIGHT), CHAT_MODE_FLOAT, "floating wins over the side")
	TEST_ASSERT_EQUAL(chat_mode_for(FALSE, null), CHAT_MODE_BOTTOM, "no side is the bottom")

/datum/unit_test/dq_chat_layout_split_math
/datum/unit_test/dq_chat_layout_split_math/Run()
	TEST_ASSERT_EQUAL(chat_share_clamped(5), CHAT_SHARE_MIN, "a thin share is raised")
	TEST_ASSERT_EQUAL(chat_share_clamped(99), CHAT_SHARE_MAX, "a huge share is cut")
	TEST_ASSERT_EQUAL(chat_share_clamped("x"), CHAT_SHARE_DEFAULT, "junk is the default")
	TEST_ASSERT_EQUAL(chat_splitter_for(CHAT_MODE_BOTTOM, 40), 60, "the chat is the second pane at the bottom: the stat panel keeps 60")
	TEST_ASSERT_EQUAL(chat_splitter_for(CHAT_MODE_TOP, 40), 40, "the chat is the first pane at the top")
	for(var/mode in list(CHAT_MODE_TOP, CHAT_MODE_BOTTOM))
		for(var/share in list(20, 33, 40, 55, 80))
			TEST_ASSERT_EQUAL(chat_share_for_splitter(mode, chat_splitter_for(mode, share)), share, "the share survives the splitter round trip in [mode]")

/datum/unit_test/dq_chat_layout_params_bottom_top
/datum/unit_test/dq_chat_layout_params_bottom_top/Run()
	var/split = SKIN_RPANE_SPLIT
	// The skin is bottom right: nothing but the splitter is needed to stay.
	TEST_ASSERT_EQUAL(chat_layout_params(CHAT_MODE_BOTTOM, 40, CHAT_MODE_BOTTOM), "[split].right=[SKIN_OUTPUT_PANE];[split].splitter=60", "bottom to bottom")
	var/to_top = chat_layout_params(CHAT_MODE_TOP, 40, CHAT_MODE_BOTTOM)
	TEST_ASSERT_EQUAL(to_top, "[split].left=;[split].right=;[split].left=[SKIN_OUTPUT_PANE];[split].right=[SKIN_STAT_PANE];[split].splitter=40", "bottom to top swaps the panes, chat first")
	var/to_bottom = chat_layout_params(CHAT_MODE_BOTTOM, 40, CHAT_MODE_TOP)
	TEST_ASSERT_EQUAL(to_bottom, "[split].left=;[split].right=;[split].left=[SKIN_STAT_PANE];[split].right=[SKIN_OUTPUT_PANE];[split].splitter=60", "top to bottom swaps back")

/datum/unit_test/dq_chat_layout_params_float
/datum/unit_test/dq_chat_layout_params_float/Run()
	var/split = SKIN_RPANE_SPLIT
	var/host = SKIN_CHAT_FLOAT_HOST
	var/window = SKIN_CHAT_FLOAT_WINDOW
	var/chrome = "[window].titlebar=false;[window].can-resize=false;[window].can-minimize=false;[window].can-close=false;[window].statusbar=false"
	TEST_ASSERT_EQUAL(chat_layout_params(CHAT_MODE_FLOAT, 40, CHAT_MODE_BOTTOM), "[split].right=;[split].splitter=100;[host].left=[SKIN_OUTPUT_PANE];[chrome];[window].is-visible=true", "bottom to float lets the stat panel fill the column")
	TEST_ASSERT_EQUAL(chat_layout_params(CHAT_MODE_FLOAT, 40, CHAT_MODE_TOP), "[split].left=;[split].right=;[split].left=[SKIN_STAT_PANE];[split].splitter=100;[host].left=[SKIN_OUTPUT_PANE];[chrome];[window].is-visible=true", "top to float seats the stat panel first")
	TEST_ASSERT_EQUAL(chat_layout_params(CHAT_MODE_BOTTOM, 40, CHAT_MODE_FLOAT), "[window].is-visible=false;[host].left=;[split].right=[SKIN_OUTPUT_PANE];[split].splitter=60", "float to bottom hides the window then re-seats the chat")
	TEST_ASSERT_EQUAL(chat_layout_params(CHAT_MODE_TOP, 40, CHAT_MODE_FLOAT), "[window].is-visible=false;[host].left=;[split].left=;[split].right=;[split].left=[SKIN_OUTPUT_PANE];[split].right=[SKIN_STAT_PANE];[split].splitter=40", "float to top")

/datum/unit_test/dq_chat_layout_moves_only_on_change
/datum/unit_test/dq_chat_layout_moves_only_on_change/Run()
	TEST_ASSERT_EQUAL(chat_layout_change(CHAT_MODE_BOTTOM, 40, CHAT_MODE_BOTTOM, 40), CHAT_CHANGE_NONE, "same place, same share: nothing to do")
	TEST_ASSERT_EQUAL(chat_layout_change(CHAT_MODE_FLOAT, 40, CHAT_MODE_FLOAT, 55), CHAT_CHANGE_NONE, "a floating chat has no share")
	TEST_ASSERT_EQUAL(chat_layout_change(CHAT_MODE_TOP, 55, CHAT_MODE_TOP, 40), CHAT_CHANGE_SPLITTER, "same end, new share: only the splitter")
	TEST_ASSERT_EQUAL(chat_layout_change(CHAT_MODE_TOP, 40, CHAT_MODE_BOTTOM, 40), CHAT_CHANGE_LAYOUT, "another end moves the pane")
	TEST_ASSERT_EQUAL(chat_layout_change(CHAT_MODE_FLOAT, 40, CHAT_MODE_BOTTOM, 40), CHAT_CHANGE_LAYOUT, "floating moves the pane")

/datum/unit_test/dq_chat_float_fit_inside_main
/datum/unit_test/dq_chat_float_fit_inside_main/Run()
	// area: main window at 100,50, 1600x900
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(300, 200, 560, 420, 100, 50, 1600, 900)), json_encode(list(300, 200, 560, 420)), "a window inside is left alone")
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(0, 0, 500, 400, 100, 50, 1600, 900)), json_encode(list(100, 50, 500, 400)), "pulled in from the top left")
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(1500, 800, 500, 400, 100, 50, 1600, 900)), json_encode(list(1200, 550, 500, 400)), "pulled in from the bottom right")
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(0, 0, 2000, 1200, 100, 50, 1600, 900)), json_encode(list(100, 50, 1600, 900)), "a window larger than the main window is cut to it")
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(100, 50, 100, 100, 100, 50, 1600, 900)), json_encode(list(100, 50, CHAT_FLOAT_MIN_W, CHAT_FLOAT_MIN_H)), "a tiny window is raised to the minimum")

/datum/unit_test/dq_chat_float_pair_parse
/datum/unit_test/dq_chat_float_pair_parse/Run()
	TEST_ASSERT_EQUAL(json_encode(chat_float_pair("60,60", ",")), json_encode(list(60, 60)), "a position")
	TEST_ASSERT_EQUAL(json_encode(chat_float_pair("560x420", "x")), json_encode(list(560, 420)), "a size")
	TEST_ASSERT_NULL(chat_float_pair("junk", "x"), "junk is nothing")
	TEST_ASSERT_NULL(chat_float_pair(null, ","), "null is nothing")

/datum/unit_test/dq_chat_float_under_pointer
/datum/unit_test/dq_chat_float_under_pointer/Run()
	TEST_ASSERT_EQUAL(json_encode(chat_float_under_pointer(1700, 300, 560)), json_encode(list(1420, 284)), "the pointer lands on the middle of the top strip")

/datum/unit_test/dq_chat_float_fit_top_left_reachable
/datum/unit_test/dq_chat_float_fit_top_left_reachable/Run()
	// A main window at 0,0 and one at 100,50, both 1920x1040: a window pulled in from past the top left corner sits in the corner, not the middle.
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(-400, -300, 560, 420, 0, 0, 1920, 1040)), json_encode(list(0, 0, 560, 420)), "corner at 0,0")
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(40, 20, 560, 420, 100, 50, 1920, 1040)), json_encode(list(100, 50, 560, 420)), "corner at 100,50")
	TEST_ASSERT_EQUAL(json_encode(chat_float_fit(110, 60, 560, 420, 100, 50, 1920, 1040)), json_encode(list(110, 60, 560, 420)), "near the corner is left alone")

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
