/datum/interim_icon_picker_actor
	var/result
	var/runs = 0

/datum/interim_icon_picker_actor/proc/choose(mob/user)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(choose), args)
	runs++
	result = pick_and_customize_icon(user, TRUE, "interim_icon")
	return result

/obj/interim_icon_picker_no_actor_probe
	var/datum/interim_icon_picker_actor/picker

/obj/interim_icon_picker_no_actor_probe/Click(location, control, params)
	picker.choose(null)

/datum/unit_test/om/interim_icon_picker_actor/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/interim_icon_picker_actor/picker = allocate(/datum/interim_icon_picker_actor)
	picker.choose(actor)
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the real icon picker opens its source-choice prompt")
	var/datum/om/prompt/choice/alert/source = sched.test_prompts[1]
	made += source
	TEST_ASSERT_EQUAL(source.peek("answerer"), actor, "the real source-choice prompt uses the explicit actor")
	TEST_ASSERT_NULL(om_prompt_answer(source, "No"), "the typed source answer resumes the real picker")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 2, "the path branch opens its actual text prompt")
	var/datum/om/prompt/text/path = sched.test_prompts[2]
	made += path
	TEST_ASSERT_EQUAL(path.peek("answerer"), actor, "the actual path prompt retains the supplied actor after reentry")
	TEST_ASSERT(fexists("icons/obj/bureaucracy.png"), "the real source PNG exists for the valid icon selection")
	TEST_ASSERT_NULL(om_prompt_answer(path, "icons/obj/bureaucracy.png"), "the real path answer resumes selection")
	TEST_ASSERT(isfile(picker.result), "the actual picker returns the selected PNG resource")
	TEST_ASSERT_EQUAL(md5(picker.result), md5(file("icons/obj/bureaucracy.png")), "the selected resource contains the exact requested source PNG bytes")
	TEST_ASSERT_EQUAL(picker.runs, 3, "the real picker runs initially and after each actual typed answer")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 2, "pick-only selection creates no customization prompt")

/datum/unit_test/om/interim_icon_picker_missing_actor/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/interim_icon_picker_actor/picker = allocate(/datum/interim_icon_picker_actor)
	var/obj/interim_icon_picker_no_actor_probe/probe = allocate(/obj/interim_icon_picker_no_actor_probe, run_loc_floor_bottom_left)
	rel_set(probe, nameof(probe.picker), picker)
	km_synthetic_click(bystander, probe)
	TEST_ASSERT_EQUAL(picker.runs, 1, "the actual native click invokes the actorless real picker")
	TEST_ASSERT_NULL(picker.result, "an actorless picker returns no resource")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 0, "the actorless helper cannot adopt the native click's unrelated ambient actor")
