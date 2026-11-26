/datum/unit_test/interim_hud_drag_explicit_view/Run()
	var/atom/movable/screen/movable/button = allocate(/atom/movable/screen/movable)
	TEST_ASSERT_NULL(button.mouse_params_to_position("icon-x=10", "15x15"), "missing screen location is refused")
	TEST_ASSERT_EQUAL(button.mouse_params_to_position("screen-loc=3:20,4:24", "15x15"), "3:4,4:8", "free dragging centers the button on the supplied pixel coordinates")
	button.snap2grid = TRUE
	TEST_ASSERT_EQUAL(button.mouse_params_to_position("screen-loc=3:20,4:24", "15x15"), "3,4", "grid dragging removes pixel offsets")
	TEST_ASSERT_EQUAL(button.mouse_params_to_position("screen-loc=EAST:20,NORTH:24", "5x7"), "5,7", "relative coordinates respect the explicit rectangular view bounds")
