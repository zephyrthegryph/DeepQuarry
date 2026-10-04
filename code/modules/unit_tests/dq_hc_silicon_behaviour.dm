// Behaviour-preservation tests for the silicon mobs (hc-mobs silicon): the questions an AI, a cyborg, a drone or a pAI is asked and what each answer
// does. A question is answered through hci_answer() (dq_hc_items_behaviour.dm): the engine's requests first, else the prompt the test scheduler
// collected for a question asked the legacy way. The same file passes before and after the questions move to open_request(). Nothing here depends on
// message text.

/datum/unit_test/dq_hc_silicon
	abstract_type = /datum/unit_test/dq_hc_silicon

/datum/unit_test/dq_hc_silicon/Run()
	test_driver_begin()
	test_rng(13)
	om_scheduler().test_prompts = list()
	run_gate()
	for(var/turf/N in range(3, test_floor()))
		own_turf_contents(N)
	test_driver_end()

/datum/unit_test/dq_hc_silicon/proc/run_gate()
	return

/datum/unit_test/dq_hc_silicon/proc/settle()
	test_time(10 SECONDS)

/datum/unit_test/dq_hc_silicon/proc/make_ai()
	return allocate(/mob/living/silicon/ai, test_floor(), null, null, null, TRUE)

// ---------------------------------------------------------------------------------------------------------------------
// AI
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_silicon/ai_icon_choice_sets_core_sprite

/datum/unit_test/dq_hc_silicon/ai_icon_choice_sets_core_sprite/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.custom_sprite = FALSE
	var/datum/ai_icon/wanted
	for(var/datum/ai_icon/I in GLOB.ai_icons)
		if(I != AI.selected_sprite)
			wanted = I
			break
	TEST_ASSERT(wanted, "there is a second core sprite to pick")
	AI.pick_icon()
	hci_answer(AI, wanted)
	settle()
	TEST_ASSERT_EQUAL(AI.selected_sprite, wanted, "the picked sprite is the core's")

/datum/unit_test/dq_hc_silicon/ai_icon_choice_dropped_when_unable

/datum/unit_test/dq_hc_silicon/ai_icon_choice_dropped_when_unable/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.custom_sprite = FALSE
	var/datum/ai_icon/before = AI.selected_sprite
	var/datum/ai_icon/wanted
	for(var/datum/ai_icon/I in GLOB.ai_icons)
		if(I != before)
			wanted = I
			break
	AI.pick_icon()
	AI.custom_sprite = TRUE
	hci_answer(AI, wanted)
	settle()
	TEST_ASSERT_NOTEQUAL(AI.selected_sprite, wanted, "an AI that got a custom sprite meanwhile does not take the picked one")

/datum/unit_test/dq_hc_silicon/ai_announcement_starts_cooldown

/datum/unit_test/dq_hc_silicon/ai_announcement_starts_cooldown/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.announcement_cooldown = 0
	AI.ai_announcement()
	hci_answer(AI, "Testing one two")
	settle()
	TEST_ASSERT(!COOLDOWN_FINISHED(AI, announcement_cooldown), "an announcement starts the cooldown")

/datum/unit_test/dq_hc_silicon/ai_announcement_cancel_keeps_cooldown_off

/datum/unit_test/dq_hc_silicon/ai_announcement_cancel_keeps_cooldown_off/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.announcement_cooldown = 0
	AI.ai_announcement()
	hci_answer(AI, null, TRUE)
	settle()
	TEST_ASSERT(COOLDOWN_FINISHED(AI, announcement_cooldown), "a cancelled announcement costs nothing")

/datum/unit_test/dq_hc_silicon/ai_emergency_message_starts_cooldown

/datum/unit_test/dq_hc_silicon/ai_emergency_message_starts_cooldown/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.emergency_message_cooldown = 0
	AI.ai_emergency_message()
	hci_answer(AI, "Send help")
	settle()
	TEST_ASSERT(!COOLDOWN_FINISHED(AI, emergency_message_cooldown), "a sent message starts the cooldown")

/datum/unit_test/dq_hc_silicon/ai_emergency_message_dropped_without_wireless

/datum/unit_test/dq_hc_silicon/ai_emergency_message_dropped_without_wireless/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.emergency_message_cooldown = 0
	AI.ai_emergency_message()
	AI.control_disabled = TRUE
	hci_answer(AI, "Send help")
	settle()
	TEST_ASSERT(COOLDOWN_FINISHED(AI, emergency_message_cooldown), "an AI that lost wireless meanwhile sends nothing")

/datum/unit_test/dq_hc_silicon/ai_hologram_color_two_steps

/datum/unit_test/dq_hc_silicon/ai_hologram_color_two_steps/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.holo_color = "#00ff00"
	AI.ai_hologram_change()
	hci_answer(AI, "Color")
	hci_answer(AI, "#ff0000")
	settle()
	TEST_ASSERT_EQUAL(AI.holo_color, "#ff0000", "the picked colour is the hologram's")

/datum/unit_test/dq_hc_silicon/ai_hologram_cancel_changes_nothing

/datum/unit_test/dq_hc_silicon/ai_hologram_cancel_changes_nothing/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.holo_color = "#00ff00"
	AI.ai_hologram_change()
	hci_answer(AI, "Cancel")
	settle()
	TEST_ASSERT_EQUAL(AI.holo_color, "#00ff00", "Cancel leaves the hologram")

/datum/unit_test/dq_hc_silicon/ai_shell_pick_cancel_deploys_nothing

/datum/unit_test/dq_hc_silicon/ai_shell_pick_cancel_deploys_nothing/run_gate()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/silicon/robot/shell = allocate(/mob/living/silicon/robot, test_floor())
	shell.shell = TRUE
	AI.deploy_to_shell()
	hci_answer(AI, null, TRUE)
	settle()
	TEST_ASSERT_NULL(AI.deployed_shell, "a cancelled pick deploys nowhere")

// ---------------------------------------------------------------------------------------------------------------------
// Every silicon
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_silicon/pose_set_and_cleared_by_cancel

/datum/unit_test/dq_hc_silicon/pose_set_and_cleared_by_cancel/run_gate()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	R.pose()
	hci_answer(R, "is standing here")
	settle()
	TEST_ASSERT_EQUAL(R.pose, "is standing here", "the answer is the pose")
	R.pose()
	hci_answer(R, null, TRUE)
	settle()
	TEST_ASSERT_NULL(R.pose, "a cancel clears the pose")
