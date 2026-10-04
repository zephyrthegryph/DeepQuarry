// Behaviour-preservation tests for the silicon mobs (hc-mobs silicon): the questions an AI, a cyborg, a drone or a pAI is asked and what each answer
// does. A question is answered through hci_answer() (dq_hc_items_behaviour.dm): the engine's requests first, else the prompt the test scheduler
// collected for a question asked the legacy way. The same file passes before and after the questions move to open_request(). Nothing here depends on
// message text.

/datum/unit_test/dq_hc_silicon
	abstract_type = /datum/unit_test/dq_hc_silicon
	/// Cards a test tied to a pAI.
	var/list/linked_cards = list()

/datum/unit_test/dq_hc_silicon/Run()
	test_driver_begin()
	test_rng(13)
	om_scheduler().test_prompts = list()
	run_gate()
	for(var/obj/item/paicard/card as anything in linked_cards)
		card.removePersonality() // the card lets go of its pAI before the block is swept, so no spark outlives the test
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

// ---------------------------------------------------------------------------------------------------------------------
// pAI
// ---------------------------------------------------------------------------------------------------------------------

/// A pAI standing on a floor tile next to a person, with a card.
/datum/unit_test/dq_hc_silicon/proc/make_pai(mob/living/carbon/human/H)
	var/obj/item/paicard/card = allocate(/obj/item/paicard, test_floor())
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai, card)
	if(!card.pai)
		rel_set(card, nameof(card.pai), P)
		linked_cards += card
	P.forceMove(get_step(H, EAST))
	return P

/// An ID swiped over a pAI, as the pAI's item handler takes it (an interaction handler today).
/proc/hcs_swipe(mob/user, mob/living/silicon/pai/P, obj/item/card/id/ID)
	return P.pai_interaction_item(user, ID, null)

/datum/unit_test/dq_hc_silicon/pai_access_add_copies_the_card_access

/datum/unit_test/dq_hc_silicon/pai_access_add_copies_the_card_access/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/pai/P = make_pai(H)
	var/obj/item/card/id/ID = allocate(/obj/item/card/id, test_floor())
	ID.access = list(ACCESS_SECURITY)
	H.put_in_active_hand(ID)
	P.idaccessible = 1
	P.idcard.access = list()
	hcs_swipe(H, P, ID)
	hci_answer(H, "Add Access")
	settle()
	TEST_ASSERT(ACCESS_SECURITY in P.idcard.access, "the card's access is copied to the pAI")

/datum/unit_test/dq_hc_silicon/pai_access_remove_clears_access

/datum/unit_test/dq_hc_silicon/pai_access_remove_clears_access/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/pai/P = make_pai(H)
	var/obj/item/card/id/ID = allocate(/obj/item/card/id, test_floor())
	H.put_in_active_hand(ID)
	P.idaccessible = 1
	P.idcard.access = list(ACCESS_SECURITY)
	hcs_swipe(H, P, ID)
	hci_answer(H, "Remove Access")
	settle()
	TEST_ASSERT(!length(P.idcard.access), "Remove Access clears the pAI's access")

/datum/unit_test/dq_hc_silicon/pai_access_dropped_when_card_leaves_hand

/datum/unit_test/dq_hc_silicon/pai_access_dropped_when_card_leaves_hand/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/pai/P = make_pai(H)
	var/obj/item/card/id/ID = allocate(/obj/item/card/id, test_floor())
	ID.access = list(ACCESS_SECURITY)
	H.put_in_active_hand(ID)
	P.idaccessible = 1
	P.idcard.access = list()
	hcs_swipe(H, P, ID)
	H.drop_item()
	ID.forceMove(test_floor())
	hci_answer(H, "Add Access")
	settle()
	TEST_ASSERT(!length(P.idcard.access), "a card that left the hand copies nothing")

/datum/unit_test/dq_hc_silicon/pai_wipe_asks_before_wiping

/datum/unit_test/dq_hc_silicon/pai_wipe_asks_before_wiping/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/pai/P = make_pai(H)
	var/obj/item/paicard/card = P.card
	P.wipe_software()
	hci_answer(P, FALSE)
	settle()
	TEST_ASSERT_EQUAL(card.pai, P, "a no keeps the personality in the card")
	P.wipe_software()
	hci_answer(P, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(card.pai, P, "a cancel keeps the personality in the card")

/datum/unit_test/dq_hc_silicon/pai_download_spends_ram

/datum/unit_test/dq_hc_silicon/pai_download_spends_ram/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/pai/P = make_pai(H)
	var/datum/pai_software/target = GLOB.pai_software_by_key["med_records"]
	TEST_ASSERT(target, "the medical records software exists")
	P.software -= target.id
	P.ram = 100
	P.touch_window(target.name)
	hci_answer(P, TRUE)
	settle()
	TEST_ASSERT(P.software[target.id], "the software is installed")
	TEST_ASSERT_EQUAL(P.ram, 100 - target.ram_cost, "the download costs its RAM")

/datum/unit_test/dq_hc_silicon/pai_download_dropped_when_ram_runs_out

/datum/unit_test/dq_hc_silicon/pai_download_dropped_when_ram_runs_out/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/pai/P = make_pai(H)
	var/datum/pai_software/target = GLOB.pai_software_by_key["med_records"]
	P.software -= target.id
	P.ram = 100
	P.touch_window(target.name)
	P.ram = 0
	hci_answer(P, TRUE)
	settle()
	TEST_ASSERT(!P.software[target.id], "a pAI that spent its RAM meanwhile installs nothing")
	TEST_ASSERT_EQUAL(P.ram, 0, "and pays nothing")
