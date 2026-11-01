// fit_viewport must never hand a whole window to the chat (the map measured while still collapsed) or to the map.

/datum/unit_test/dq_fit_viewport_collapsed_map_keeps_a_floor/Run()
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(0, 1280), FIT_VIEWPORT_MIN_SIDE, "a collapsed map measurement must not shrink the map below the floor")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(-40, 1280), FIT_VIEWPORT_MIN_SIDE, "a negative width is clamped to the floor")

/datum/unit_test/dq_fit_viewport_chat_keeps_its_side/Run()
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(5000, 1280), 1280 - FIT_VIEWPORT_MIN_SIDE, "the chat side keeps its minimum width")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(700, 1280), 700, "a width inside the bounds is kept")

/datum/unit_test/dq_fit_viewport_narrow_window_splits_evenly/Run()
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(10, 400), 200, "a window narrower than two floors splits in half at the lowest")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(390, 400), 200, "and never gives the map more than the floor allows the chat")
