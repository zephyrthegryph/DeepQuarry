/// Real held sheet stack, public self-click and actual constructed windows.
/datum/unit_test/round2_glass_window_choice
	var/build_case = "directional"

/datum/unit_test/round2_glass_window_choice/Run()
	test_driver_begin()
	exercise_window()
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_glass_window_choice/proc/exercise_window()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/stack/material/glass/sheets = allocate(/obj/item/stack/material/glass, surface, 5)
	TEST_ASSERT(user.put_in_active_hand(sheets), "Real inventory equips the original glass sheets")
	TEST_ASSERT_NULL(locate(/obj/structure/window) in surface, "Real construction floor starts without any window")
	input_submit(new /datum/input_event/click(user, sheets, null, "mapwindow.map", "left=1"))
	var/datum/prompt/choice/glass_window_build/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question), "Actual held-stack self-click opens the native construction choice")
	TEST_ASSERT_EQUAL(question.owner, sheets.material, "The actual original glass material owns construction")
	TEST_ASSERT_EQUAL(question.subject, sheets, "The original actual stack remains the construction subject")
	TEST_ASSERT_EQUAL(question.answerer, user, "Original human is the construction answerer")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 5, "Opening the actual construction question consumes no sheets")
	if(build_case == "closed")
		test_answer(user, null, REQ_CANCELLED)
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Close retires the actual construction request")
		TEST_ASSERT_EQUAL(sheets.get_amount(), 5, "Close preserves all real held sheets")
		TEST_ASSERT_NULL(locate(/obj/structure/window) in surface, "Close creates no actual window")
		return
	test_answer(user, build_case == "full" ? "Full Window" : "One Direction")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Accepted construction retires the actual request")
	var/obj/structure/window/built = locate(/obj/structure/window) in surface
	TEST_ASSERT(built, "Actual accepted construction creates a real window on the current floor")
	TEST_ASSERT(!built.anchored && built.state == 0, "Actual construction initializes an unfastened, unanchored window")
	if(build_case == "full")
		TEST_ASSERT_EQUAL(built.type, /obj/structure/window/basic/full, "Actual Full Window choice builds the full-tile glass type")
		TEST_ASSERT_EQUAL(sheets.get_amount(), 1, "Full construction consumes exactly four real sheets")
	else
		TEST_ASSERT_EQUAL(built.type, /obj/structure/window/basic, "Actual directional choice builds the single-direction glass type")
		TEST_ASSERT_EQUAL(built.dir, user.dir, "Actual single-direction construction uses current human facing")
		TEST_ASSERT_EQUAL(sheets.get_amount(), 4, "Directional construction consumes exactly one real sheet")
	TEST_ASSERT_EQUAL(sheets.loc, user, "Unconsumed original sheets retain actual inventory custody")

/datum/unit_test/round2_glass_window_choice/full
	build_case = "full"

/datum/unit_test/round2_glass_window_choice/closed
	build_case = "closed"
