// The admin tools' question sequences (code/modules/admin/view_variables/pickers.dm): the value picker and the smaller pickers it asks through ask_child().

/// Starts a sequence and keeps what it hands back.
/datum/dq_ask_probe
	var/result
	var/finished = FALSE
	var/stopped

/datum/dq_ask_probe/proc/begin(mob/user, sequence, list/params)
	return ask_sequence_begin(src, sequence, user, null, null, PROC_REF(done), PROC_REF(halted), null, params)

/datum/dq_ask_probe/proc/done(datum/ask_sequence/asked)
	result = asked.get("result")
	finished = TRUE

/datum/dq_ask_probe/proc/halted(datum/ask_sequence/asked, reason)
	stopped = reason

/datum/unit_test/dq_flow_ask_vv_number/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/dq_ask_probe/probe = allocate(/datum/dq_ask_probe)
	probe.begin(actor, /datum/ask_sequence/picker/vv_pick, list("class" = VV_NUM, "current_value" = 3))
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "a preset kind asks only for its value")
	var/datum/prompt/number/asked = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(asked.answerer, actor, "the value is asked of the admin")
	TEST_ASSERT_NULL(test_prompt_answer(asked, 5), "the number answer goes through")
	TEST_ASSERT(probe.finished, "the picker ends with the value")
	var/list/picked = probe.result
	TEST_ASSERT_EQUAL(picked["class"], VV_NUM, "the picked kind is handed back")
	TEST_ASSERT_EQUAL(picked["value"], 5, "the picked value is handed back")
	test_driver_end()

/datum/unit_test/dq_flow_ask_vv_text_by_kind/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/dq_ask_probe/probe = allocate(/datum/dq_ask_probe)
	probe.begin(actor, /datum/ask_sequence/picker/vv_pick, list("restricted_classes" = list(VV_RESTORE_DEFAULT)))
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the kind is asked first")
	var/datum/prompt/choice/kind = GLOB.test_prompts[1]
	TEST_ASSERT(VV_TEXT in kind.choices, "text is one of the kinds")
	TEST_ASSERT(!(VV_RESTORE_DEFAULT in kind.choices), "a restricted kind is not offered")
	TEST_ASSERT_NULL(test_prompt_answer(kind, VV_TEXT), "the kind answer goes through")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "the kind asks for its value")
	var/datum/prompt/text/typed = GLOB.test_prompts[2]
	TEST_ASSERT_NULL(test_prompt_answer(typed, "hello"), "the text answer goes through")
	var/list/picked = probe.result
	TEST_ASSERT_EQUAL(picked["class"], VV_TEXT, "the chosen kind is handed back")
	TEST_ASSERT_EQUAL(picked["value"], "hello", "the typed text is handed back")
	test_driver_end()

/datum/unit_test/dq_flow_ask_vv_cancel/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/dq_ask_probe/probe = allocate(/datum/dq_ask_probe)
	probe.begin(actor, /datum/ask_sequence/picker/vv_pick, list())
	var/datum/prompt/choice/kind = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(test_prompt_answer(kind, null, TRUE), "no answer", "the kind question can be cancelled")
	TEST_ASSERT(!probe.finished, "a cancelled pick hands nothing back")
	TEST_ASSERT(probe.stopped, "a cancelled pick ends the sequence that asked")
	test_driver_end()

/datum/unit_test/dq_flow_ask_vv_new_list/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/dq_ask_probe/probe = allocate(/datum/dq_ask_probe)
	probe.begin(actor, /datum/ask_sequence/picker/vv_pick, list("class" = VV_NEW_LIST))
	var/datum/prompt/choice/populate = GLOB.test_prompts[1]
	TEST_ASSERT_NULL(test_prompt_answer(populate, "Yes"), "the list is to be populated")
	var/datum/prompt/choice/first_kind = GLOB.test_prompts[2]
	TEST_ASSERT(!(VV_RESTORE_DEFAULT in first_kind.choices), "an entry cannot restore a default")
	TEST_ASSERT_NULL(test_prompt_answer(first_kind, VV_NUM), "the first entry is a number")
	var/datum/prompt/number/first_value = GLOB.test_prompts[3]
	TEST_ASSERT_NULL(test_prompt_answer(first_value, 7), "the first entry is 7")
	var/datum/prompt/choice/second_kind = GLOB.test_prompts[4]
	TEST_ASSERT_EQUAL(test_prompt_answer(second_kind, null, TRUE), "no answer", "closing the kinds ends the list")
	TEST_ASSERT(probe.finished, "the list is handed back")
	var/list/picked = probe.result
	TEST_ASSERT_EQUAL(picked["class"], VV_NEW_LIST, "the list kind is handed back")
	var/list/made_list = picked["value"]
	TEST_ASSERT_EQUAL(length(made_list), 1, "the list holds the one entry")
	TEST_ASSERT_EQUAL(made_list[1], 7, "the entry is the number given")
	TEST_ASSERT_EQUAL(picked["type"], /list, "a made list names its type")
	test_driver_end()

/datum/unit_test/dq_flow_ask_subtypes/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/dq_ask_probe/probe = allocate(/datum/dq_ask_probe)
	probe.begin(actor, /datum/ask_sequence/picker/subtype_pick, list("target_type" = /datum/dq_ask_probe))
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "a type without subtypes asks nothing")
	TEST_ASSERT(probe.finished, "the answer is immediate")
	TEST_ASSERT_EQUAL(probe.result, FALSE, "a type without subtypes is strict")
	var/datum/dq_ask_probe/second = allocate(/datum/dq_ask_probe)
	second.begin(actor, /datum/ask_sequence/picker/subtype_pick, list("target_type" = /obj/item))
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "a type with subtypes asks")
	var/datum/prompt/choice/mode = GLOB.test_prompts[1]
	TEST_ASSERT_NULL(test_prompt_answer(mode, "This type and subtypes"), "the subtype answer goes through")
	TEST_ASSERT_EQUAL(second.result, TRUE, "the subtypes are included")
	test_driver_end()

/datum/unit_test/dq_flow_ask_proc_args/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/dq_ask_probe/probe = allocate(/datum/dq_ask_probe)
	probe.begin(actor, /datum/ask_sequence/picker/proc_args, list())
	var/datum/prompt/number/count = GLOB.test_prompts[1]
	TEST_ASSERT_NULL(test_prompt_answer(count, 1), "one argument is asked for")
	var/datum/prompt/text/arg_name = GLOB.test_prompts[2]
	TEST_ASSERT_NULL(test_prompt_answer(arg_name, "amount"), "the argument is named")
	var/datum/prompt/choice/kind = GLOB.test_prompts[3]
	TEST_ASSERT_NULL(test_prompt_answer(kind, VV_NUM), "the argument is a number")
	var/datum/prompt/number/value = GLOB.test_prompts[4]
	TEST_ASSERT_NULL(test_prompt_answer(value, 9), "the argument is 9")
	TEST_ASSERT(probe.finished, "the arguments are handed back")
	var/list/args_given = probe.result
	TEST_ASSERT(islist(args_given), "the arguments are a list")
	TEST_ASSERT_EQUAL(args_given["amount"], 9, "the named argument carries its value")
	test_driver_end()
