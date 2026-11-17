// A prompt's own window answers it: pressing the window's confirm (submit) button runs the window's op, which hands the answer to the prompt and ends
// it answered, and the asker's handler runs with the value. These drive the press through test_ui(), the path a player's button takes.

/// The asker of the probe prompts: records what each answer was.
/datum/dq_prompt_probe
	var/answered = FALSE
	var/value

/datum/dq_prompt_probe/proc/got(datum/act/request/A)
	answered = TRUE
	value = A.answer?.value

/// Opens a `kind` prompt for `user` with `fields`, shows its window and returns list(prompt, window, probe).
/datum/unit_test/proc/dq_prompt_window(mob/user, kind, list/fields)
	var/datum/dq_prompt_probe/probe = allocate(/datum/dq_prompt_probe)
	var/list/all = list("answerer" = user, "timeout" = 30 SECONDS) + fields
	var/datum/prompt/P = request_open(probe, kind, TYPE_PROC_REF(/datum/dq_prompt_probe, got), all)
	TEST_ASSERT(istype(P) && P.is_open(), "the [kind] prompt opens")
	var/datum/shown = P.present(user)
	TEST_ASSERT_NOTNULL(shown, "the [kind] prompt has a window")
	rel_set(P, nameof(P.window), shown)
	// A test person has no client: the window is made open by hand, so closing it is observable.
	var/datum/tgui/ui = new(user, shown, "HcTest")
	ui.status = STATUS_INTERACTIVE
	ui.set_state(GLOB.tgui_always_state)
	SStgui.on_open(ui)
	return list(P, shown, probe, ui)

/// The window of a confirmed prompt is closed: its tgui is gone or no longer open for `user`.
/datum/unit_test/proc/dq_prompt_window_assert_closed(mob/user, list/got, kind)
	var/datum/tgui/ui = got[4]
	TEST_ASSERT(QDELETED(ui) || !SStgui.get_open_ui(user, got[2]), "the [kind] window closes on confirm")

/// The number window's confirm commits the number.
/datum/unit_test/dq_prompt_window_number_confirm

/datum/unit_test/dq_prompt_window_number_confirm/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/list/got = dq_prompt_window(H, /datum/prompt/number, list("min_value" = 20, "max_value" = 300, "default" = 60))
	var/datum/prompt/P = got[1]
	var/datum/dq_prompt_probe/probe = got[3]
	var/datum/op_result/R = test_ui(H, got[2], "submit", list("entry" = 85))
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(P.outcome, REQ_ANSWERED, "the confirm answers the prompt ([R?.outcome] [R?.reason])")
	TEST_ASSERT(probe.answered, "the asker hears the answer")
	TEST_ASSERT_EQUAL(probe.value, 85, "with the number confirmed")
	dq_prompt_window_assert_closed(H, got, "number")

/// The text window's confirm commits the text.
/datum/unit_test/dq_prompt_window_text_confirm

/datum/unit_test/dq_prompt_window_text_confirm/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/list/got = dq_prompt_window(H, /datum/prompt/text, list("question" = "Name?"))
	var/datum/prompt/P = got[1]
	var/datum/dq_prompt_probe/probe = got[3]
	var/datum/op_result/R = test_ui(H, got[2], "submit", list("entry" = "flask"))
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(P.outcome, REQ_ANSWERED, "the confirm answers the prompt ([R?.outcome] [R?.reason])")
	TEST_ASSERT_EQUAL(probe.value, "flask", "with the text confirmed")
	dq_prompt_window_assert_closed(H, got, "text")

/// The yes/no window's yes button commits a yes.
/datum/unit_test/dq_prompt_window_yes_no_confirm

/datum/unit_test/dq_prompt_window_yes_no_confirm/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/list/got = dq_prompt_window(H, /datum/prompt/yes_no, list("yes_text" = "Confirm", "no_text" = "Cancel"))
	var/datum/prompt/P = got[1]
	var/datum/dq_prompt_probe/probe = got[3]
	var/datum/op_result/R = test_ui(H, got[2], "choose", list("choice" = "Confirm"))
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(P.outcome, REQ_ANSWERED, "the confirm answers the prompt ([R?.outcome] [R?.reason])")
	TEST_ASSERT_EQUAL(probe.value, TRUE, "with a yes")
	dq_prompt_window_assert_closed(H, got, "yes/no")
