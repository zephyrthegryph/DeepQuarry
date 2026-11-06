/// The actual ColorMate UI action edits only its real dialog colour state.
/datum/unit_test/round2_matrix_active_colour
	var/close_question = FALSE

/datum/unit_test/round2_matrix_active_colour/Run()
	test_driver_begin()
	exercise_colour()
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_matrix_active_colour/proc/exercise_colour()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pen/preview_item = allocate(/obj/item/pen, test_floor())
	var/datum/tgui_input_colormatrix/dialog = allocate(/datum/tgui_input_colormatrix, user, "Actual matrix fixture", "Round2 Matrix", preview_item, DEFAULT_COLORMATRIX, FALSE, 0, GLOB.tgui_always_state, FALSE)
	var/datum/tgui/editor = allocate(/datum/tgui, user, dialog, "ColorMate")
	var/original_colour = dialog.activecolor
	var/original_item_colour = preview_item.color
	input_submit(new /datum/input_event/ui_act(user, editor, "choose_color", list(), editor.state()))
	var/datum/prompt/color/matrix_active_colour/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question), "Actual public ColorMate action opens its native colour request")
	TEST_ASSERT_EQUAL(question.answerer, user, "Original user answers the actual colour picker")
	TEST_ASSERT_EQUAL(question.default, original_colour, "Actual picker preserves the opening current colour default")
	if(close_question)
		test_answer(user, null, REQ_CANCELLED)
		TEST_ASSERT_EQUAL(dialog.activecolor, original_colour, "Closing the actual picker preserves dialog colour")
	else
		test_answer(user, "#123456")
		TEST_ASSERT_EQUAL(dialog.activecolor, "#123456", "Actual accepted picker changes real dialog state")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Answer retires the actual picker request")
	TEST_ASSERT_EQUAL(preview_item.color, original_item_colour, "Choosing active colour does not paint the preview item")
	TEST_ASSERT(!dialog.closed, "Choosing or cancelling the secondary picker leaves the matrix dialog open")

/datum/unit_test/round2_matrix_active_colour/closed
	close_question = TRUE
