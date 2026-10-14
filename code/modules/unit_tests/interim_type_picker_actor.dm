/// The fixture supplies a small real type table to the actual filter/choice helper.
/datum/interim_type_picker_actor
	var/result
	var/runs = 0
	var/static/list/matches = list("Blue pen" = /obj/item/pen/blue, "Red pen" = /obj/item/pen/red, "Power cell" = /obj/item/cell)

/datum/interim_type_picker_actor/proc/choose(mob/user)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(choose), args)
	runs++
	result = pick_closest_path(FALSE, matches, "interim_type", user)
	return result

/datum/unit_test/om/interim_type_picker_actor/run_om(list/made)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/interim_type_picker_actor/picker = allocate(/datum/interim_type_picker_actor)
	picker.choose(actor)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual helper opens its filter prompt")
	var/datum/prompt/text/filter = GLOB.test_prompts[1]
	made += filter
	TEST_ASSERT_EQUAL(filter.answerer, actor, "the actual filter prompt belongs to the supplied actor")
	TEST_ASSERT_NULL(test_prompt_answer(filter, "pen"), "the real filter answer resumes the actual picker")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "two actual matching types require a choice prompt")
	var/datum/prompt/choice/choice = GLOB.test_prompts[2]
	made += choice
	TEST_ASSERT_EQUAL(choice.answerer, actor, "the real resumed choice keeps the supplied actor")
	TEST_ASSERT("Blue pen" in choice.choices, "the actual filtered choices retain the first matching type")
	TEST_ASSERT("Red pen" in choice.choices, "the actual filtered choices retain the second matching type")
	TEST_ASSERT(!("Power cell" in choice.choices), "the actual filter excludes the nonmatching type")
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Red pen"), "the real type choice resumes the actual helper")
	TEST_ASSERT_EQUAL(picker.result, /obj/item/pen/red, "the actual helper returns the selected concrete type path")
	TEST_ASSERT_EQUAL(picker.runs, 3, "the real flow executes initially and after both actual answers")

/datum/unit_test/om/interim_type_picker_single_match/run_om(list/made)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/interim_type_picker_actor/picker = allocate(/datum/interim_type_picker_actor)
	picker.choose(actor)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual picker creates a filter prompt before selection")
	var/datum/prompt/text/filter = GLOB.test_prompts[1]
	made += filter
	TEST_ASSERT_EQUAL(filter.answerer, actor, "the single-match filter uses its explicit actor")
	TEST_ASSERT_NULL(test_prompt_answer(filter, "blue"), "the actual single-match filter answer resumes selection")
	TEST_ASSERT_EQUAL(picker.result, /obj/item/pen/blue, "the actual helper returns its sole matching concrete type")
	TEST_ASSERT_EQUAL(picker.runs, 2, "a sole match finishes on the first real filter answer")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "a sole matching type creates no redundant choice prompt")
