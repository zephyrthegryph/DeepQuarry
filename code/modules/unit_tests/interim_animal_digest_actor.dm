/mob/living/simple_mob/interim_digest_actor
	vore_default_mode = DM_HOLD

/obj/interim_digest_actor_click
	var/mob/living/simple_mob/animal

/obj/interim_digest_actor_click/Click(location, control, params)
	animal.toggle_digestion()

/datum/unit_test/om/interim_animal_digest_actor/run_om(list/made)
	test_prompts_reset()
	var/mob/living/simple_mob/animal = allocate(/mob/living/simple_mob/interim_digest_actor, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/interim_digest_actor_click/probe = allocate(/obj/interim_digest_actor_click, run_loc_floor_bottom_left)
	made += list(animal, actor, bystander, probe)
	TEST_ASSERT(!(/mob/living/simple_mob/proc/toggle_digestion in animal.verbs), "digestion remains unexposed before actual conditional belly initialization")
	animal.init_vore(TRUE)
	TEST_ASSERT(/mob/living/simple_mob/proc/toggle_digestion in animal.verbs, "the actual init_vore grant exposes the unchanged native proc path")
	var/obj/belly/belly = animal.vore_selected
	TEST_ASSERT(belly && belly.owner == animal, "actual default belly construction produces the animal's owned selected belly")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "the fixture's actual default belly starts in hold mode")
	rel_set(probe, nameof(probe.animal), animal)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual granted-proc boundary opens its real enable choice")
	var/datum/prompt/choice/enable = GLOB.test_prompts[1]
	made += enable
	TEST_ASSERT_EQUAL(enable.answerer, actor, "the first real choice keeps the native selecting human")
	test_prompt_answer(enable, "Enable")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_DIGEST, "the actual answer reenters the helper with its actor and enables digestion")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the resumed helper consumes its answer without reopening a prompt")
	var/list/timers = belly.om_rec?.timers
	TEST_ASSERT(timers && length(timers) == OM_TIMER_STRIDE, "actual enable schedules exactly one real reset timer on the selected belly")
	TEST_ASSERT_EQUAL(timers[3], TYPE_PROC_REF(/obj/belly, reset_digest_mode), "the actual timer invokes the existing reset proc")
	var/list/timer_args = timers[4]
	TEST_ASSERT_EQUAL(timer_args[1], animal.vore_default_mode, "the actual scheduled reset captures the animal's original mode")
	TEST_ASSERT_EQUAL(timer_left(belly, timers[1]), 20 MINUTES, "the actual scheduled reset retains its complete defined duration")
	animal.toggle_digestion_for(bystander)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "an explicit different human opens the real disable choice")
	var/datum/prompt/choice/disable = GLOB.test_prompts[2]
	made += disable
	TEST_ASSERT_EQUAL(disable.answerer, bystander, "the second helper retains its supplied actor rather than the prior native actor")
	test_prompt_answer(disable, "Disable")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "the actual resumed disable choice restores hold")
	animal.toggle_digestion_for(actor)
	var/datum/prompt/choice/cancelled = GLOB.test_prompts[3]
	made += cancelled
	test_prompt_answer(cancelled, "Cancel")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "the actual cancel choice leaves digestion unchanged")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 3, "cancellation resumes once without an extra choice")
	actor.set_stat(UNCONSCIOUS)
	animal.toggle_digestion_for(actor)
	animal.toggle_digestion_for(null)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 3, "unconscious and absent explicit actors open no choice")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "actor refusals preserve actual belly state")
