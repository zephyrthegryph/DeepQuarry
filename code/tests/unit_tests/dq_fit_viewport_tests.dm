// fit_viewport must never hand a whole window to the chat (the map measured while still collapsed) or to the map
// (a tall window whose pixel-exact fit is wider than the window allows).

/datum/unit_test/dq_fit_viewport_collapsed_map_keeps_a_floor/Run()
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(0, 1280), 640, "a collapsed map measurement at login must not shrink the map below the floor")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(-40, 1280), 640, "a negative width is clamped to the floor")

/datum/unit_test/dq_fit_viewport_tall_window_keeps_the_chat/Run()
	// 1920 wide splitter, 1500 tall, square view: the exact fit is 1500 px, the chat keeps 576 (30%).
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(1500, 1920), 1920 - 576, "a tall window shrinks the map so the chat keeps 30%")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(5000, 1280), 1280 - FIT_VIEWPORT_MIN_SIDE, "on a smaller window the chat keeps its pixel minimum")

/datum/unit_test/dq_fit_viewport_wide_window_keeps_the_exact_fit/Run()
	// 2560 wide splitter, 900 tall: the exact 900 px fit leaves the chat far more than its minimum.
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(1280, 2560), 1280, "a wide window keeps the pixel-exact map")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(1500, 2560), 1500, "a width inside the bounds is kept")

/datum/unit_test/dq_fit_viewport_refit_is_stable/Run()
	var/first = fit_viewport_clamp_width(1500, 1920)
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(first, 1920), first, "refitting the clamped width at the same size changes nothing")

/datum/unit_test/dq_fit_viewport_narrow_window_splits_evenly/Run()
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(10, 800), 400, "a window narrower than two minimums splits in half at the lowest")
	TEST_ASSERT_EQUAL(fit_viewport_clamp_width(790, 800), 400, "and never gives the map more than the floor allows the chat")
