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
	test_prompts_reset()
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

/// An ID swiped over a pAI: a click with the card in hand.
/proc/hcs_swipe(mob/living/carbon/human/user, mob/living/silicon/pai/P, obj/item/card/id/ID)
	return hci_click(user, P, ID)

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

// ---------------------------------------------------------------------------------------------------------------------
// Cyborgs and drones
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_silicon/proc/make_borg()
	return allocate(/mob/living/silicon/robot, test_floor())

/datum/unit_test/dq_hc_silicon/cloak_level_is_a_percentage

/datum/unit_test/dq_hc_silicon/cloak_level_is_a_percentage/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/borg/cloak/cloak = allocate(/obj/item/borg/cloak, test_floor())
	cloak.forceMove(R)
	cloak.set_cloaking_level(R)
	hci_answer(R, 40)
	settle()
	TEST_ASSERT_EQUAL(cloak.cloak_strength, 0.4, "the answer in percent is the cloak's strength")
	cloak.set_cloaking_level(R)
	hci_answer(R, 100)
	settle()
	TEST_ASSERT_EQUAL(cloak.cloak_strength, 1, "a full level is kept")

/datum/unit_test/dq_hc_silicon/cloak_level_dropped_when_cloak_leaves_the_borg

/datum/unit_test/dq_hc_silicon/cloak_level_dropped_when_cloak_leaves_the_borg/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/borg/cloak/cloak = allocate(/obj/item/borg/cloak, test_floor())
	cloak.forceMove(R)
	var/before = cloak.cloak_strength
	cloak.set_cloaking_level(R)
	cloak.forceMove(test_floor())
	hci_answer(R, 10)
	settle()
	TEST_ASSERT_EQUAL(cloak.cloak_strength, before, "a cloak that left the borg is not changed")

/datum/unit_test/dq_hc_silicon/robot_name_is_picked_once

/datum/unit_test/dq_hc_silicon/robot_name_is_picked_once/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	R.custom_name = ""
	R.ability_pick_name(null)
	hci_answer(R, "Bolt-9")
	settle()
	TEST_ASSERT_EQUAL(R.custom_name, "Bolt-9", "the answer is the borg's name")

/// The first external component a borg's pry question offers: its name and the component.
/datum/unit_test/dq_hc_silicon/proc/first_prying_target(mob/living/silicon/robot/R)
	for(var/datum/robot_component/C as anything in R.components)
		if(C.internal || C.slot == ROBOT_SLOT_POWER || C.installed == ROBOT_PART_MISSING || !C.wrapped)
			continue
		return C
	return null

/datum/unit_test/dq_hc_silicon/robot_pry_component_takes_the_part_out

/datum/unit_test/dq_hc_silicon/robot_pry_component_takes_the_part_out/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, get_step(H, EAST))
	R.opened = TRUE
	R.cell = null
	var/datum/robot_component/target = first_prying_target(R)
	TEST_ASSERT(target, "the borg has an external component to pry out")
	R.pry_component(H)
	hci_answer(H, "[target.name]")
	settle()
	TEST_ASSERT_EQUAL(target.installed, ROBOT_PART_MISSING, "the chosen component is out of its slot")

/datum/unit_test/dq_hc_silicon/robot_pry_component_dropped_when_borg_closes

/datum/unit_test/dq_hc_silicon/robot_pry_component_dropped_when_borg_closes/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, get_step(H, EAST))
	R.opened = TRUE
	R.cell = null
	var/datum/robot_component/target = first_prying_target(R)
	R.pry_component(H)
	R.opened = FALSE
	hci_answer(H, "[target.name]")
	settle()
	TEST_ASSERT_NOTEQUAL(target.installed, ROBOT_PART_MISSING, "a borg that closed meanwhile keeps its part")

/datum/unit_test/dq_hc_silicon/shield_level_is_chosen_in_percent

/datum/unit_test/dq_hc_silicon/shield_level_is_chosen_in_percent/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/borg/combat/shield/shield = allocate(/obj/item/borg/combat/shield, test_floor())
	shield.forceMove(R)
	hcs_menu(R, shield, "set_level", "borg_shield_verb_set_level")
	hci_answer(R, "75")
	settle()
	TEST_ASSERT_EQUAL(shield.shield_level, 0.75, "the chosen level is the shield's")

/datum/unit_test/dq_hc_silicon/cyborg_cable_colour_is_picked

/datum/unit_test/dq_hc_silicon/cyborg_cable_colour_is_picked/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/stack/cable_coil/cyborg/coil = allocate(/obj/item/stack/cable_coil/cyborg, test_floor())
	coil.forceMove(R)
	coil.set_colour(R)
	hci_answer(R, "Cyan")
	settle()
	TEST_ASSERT_EQUAL(coil.color, GLOB.possible_cable_coil_colours["Cyan"], "the picked colour is the coil's")

/datum/unit_test/dq_hc_silicon/robopen_colour_and_mode

/datum/unit_test/dq_hc_silicon/robopen_colour_and_mode/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pen/robopen/pen = allocate(/obj/item/pen/robopen, test_floor())
	hci_click(H, pen, pen)
	settle()
	hci_answer(H, "Colour")
	hci_answer(H, "green")
	settle()
	TEST_ASSERT_EQUAL(pen.colour, "green", "the second question picks the ink colour")

/datum/unit_test/dq_hc_silicon/robopen_mode_flips

/datum/unit_test/dq_hc_silicon/robopen_mode_flips/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pen/robopen/pen = allocate(/obj/item/pen/robopen, test_floor())
	var/mode = pen.mode
	hci_click(H, pen, pen)
	settle()
	hci_answer(H, "Mode")
	settle()
	TEST_ASSERT_NOTEQUAL(pen.mode, mode, "Mode flips the printing mode")

/datum/unit_test/dq_hc_silicon/robopen_cancel_changes_nothing

/datum/unit_test/dq_hc_silicon/robopen_cancel_changes_nothing/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pen/robopen/pen = allocate(/obj/item/pen/robopen, test_floor())
	var/mode = pen.mode
	hci_click(H, pen, pen)
	settle()
	hci_answer(H, "Cancel")
	settle()
	TEST_ASSERT_EQUAL(pen.mode, mode, "Cancel changes nothing")

/datum/unit_test/dq_hc_silicon/robopen_labels_paper

/datum/unit_test/dq_hc_silicon/robopen_labels_paper/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pen/robopen/pen = allocate(/obj/item/pen/robopen, test_floor())
	var/obj/item/paper/paper = allocate(/obj/item/paper, get_step(H, EAST))
	pen.RenamePaper(H, paper)
	hci_answer(H, "Memo")
	settle()
	TEST_ASSERT(findtext(paper.name, "Memo"), "the label is the paper's name")

/datum/unit_test/dq_hc_silicon/form_printer_prints_a_chosen_form

/datum/unit_test/dq_hc_silicon/form_printer_prints_a_chosen_form/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/form_printer/printer = allocate(/obj/item/form_printer, test_floor())
	printer.forceMove(R)
	var/turf/T = test_floor()
	var/before = 0
	for(var/obj/item/paper/P in T)
		before++
	printer.deploy_paper(R)
	hci_answer(R, "Paper")
	settle()
	var/after_blank = 0
	for(var/obj/item/paper/P in T)
		after_blank++
	TEST_ASSERT_EQUAL(after_blank, before + 1, "a blank page is dispensed")
	printer.deploy_paper(R)
	hci_answer(R, "Form")
	hci_answer(R, "Security")
	hci_answer(R, "SEC-1003: Incident Report")
	settle()
	var/after_form = 0
	for(var/obj/item/paper/P in T)
		after_form++
	TEST_ASSERT_EQUAL(after_form, after_blank + 1, "the chosen form is dispensed")

/datum/unit_test/dq_hc_silicon/mining_scanner_range_is_picked

/datum/unit_test/dq_hc_silicon/mining_scanner_range_is_picked/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/mining_scanner/robot/scanner = allocate(/obj/item/mining_scanner/robot, test_floor())
	scanner.forceMove(R)
	scanner.upgrade(R)
	perform_op(R, scanner, "set_range", null, ORIGIN_CLICK)
	hci_answer(R, 5)
	settle()
	TEST_ASSERT_EQUAL(scanner.range, 5, "the picked range is the scanner's")

/datum/unit_test/dq_hc_silicon/lost_drone_keeps_or_rerolls_laws

/datum/unit_test/dq_hc_silicon/lost_drone_keeps_or_rerolls_laws/run_gate()
	var/mob/living/silicon/robot/malf/lost/randomlaws/R = allocate(/mob/living/silicon/robot/malf/lost/randomlaws, test_floor())
	R.law_retries = 2
	R.repick_laws()
	hci_answer(R, "Reroll (2)")
	hci_answer(R, "Keep")
	settle()
	TEST_ASSERT_EQUAL(R.law_retries, 0, "keeping ends the rerolls")
	R.law_retries = 3
	R.repick_laws()
	hci_answer(R, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(R.law_retries, 0, "closing the window keeps the laws")

/datum/unit_test/dq_hc_silicon/drone_mail_tag_is_set_and_cleared

/datum/unit_test/dq_hc_silicon/drone_mail_tag_is_set_and_cleared/run_gate()
	var/mob/living/silicon/robot/drone/D = allocate(/mob/living/silicon/robot/drone, test_floor())
	var/list/saved_locations = GLOB.tagger_locations
	GLOB.tagger_locations = list("Disposals" = 1)
	var/tag = "Disposals"
	D.ability_set_mail_tag(null)
	hci_answer(D, tag)
	settle()
	TEST_ASSERT_EQUAL(D.mail_destination, tag, "the picked destination is the drone's tag")
	D.ability_set_mail_tag(null)
	hci_answer(D, null, TRUE)
	settle()
	GLOB.tagger_locations = saved_locations
	TEST_ASSERT_EQUAL(D.mail_destination, "", "a cancel clears the tag")

/datum/unit_test/dq_hc_silicon/platform_paint_colours_a_part

/datum/unit_test/dq_hc_silicon/platform_paint_colours_a_part/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/robot/platform/P = allocate(/mob/living/silicon/robot/platform, get_step(H, EAST))
	var/obj/item/floor_painter/painter = allocate(/obj/item/floor_painter, test_floor())
	H.put_in_active_hand(painter)
	painter.paint_colour = "#123456"
	var/obj/item/robot_module/robot/platform/tank_module = P.module
	TEST_ASSERT(istype(tank_module), "the platform has its module")
	P.try_paint(painter, H)
	hci_answer(H, "Eyes")
	settle()
	TEST_ASSERT_EQUAL(tank_module.eye_color, "#123456", "the painter's colour is the eyes'")

// ---------------------------------------------------------------------------------------------------------------------
// Click and menu entries of cyborg gear
// ---------------------------------------------------------------------------------------------------------------------

/// A pick from `target`'s menu by op key.
/proc/hcs_menu(mob/actor, atom/target, op_key, legacy_proc)
	return test_menu(actor, target, op_key)

/datum/unit_test/dq_hc_silicon/shield_in_hand_asks_the_level

/datum/unit_test/dq_hc_silicon/shield_in_hand_asks_the_level/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/borg/combat/shield/shield = allocate(/obj/item/borg/combat/shield, test_floor())
	hci_click(H, shield, shield)
	settle()
	hci_answer(H, "25")
	settle()
	TEST_ASSERT_EQUAL(shield.shield_level, 0.25, "using the shield in hand asks its level")

/datum/unit_test/dq_hc_silicon/shield_menu_asks_the_level

/datum/unit_test/dq_hc_silicon/shield_menu_asks_the_level/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/borg/combat/shield/shield = allocate(/obj/item/borg/combat/shield, test_floor())
	shield.forceMove(R)
	hcs_menu(R, shield, "set_level", "borg_shield_verb_set_level")
	settle()
	hci_answer(R, "10")
	settle()
	TEST_ASSERT_EQUAL(shield.shield_level, 0.1, "the menu entry asks the level")

/datum/unit_test/dq_hc_silicon/cloak_menu_toggles_and_asks_strength

/datum/unit_test/dq_hc_silicon/cloak_menu_toggles_and_asks_strength/run_gate()
	var/mob/living/silicon/robot/R = make_borg()
	var/obj/item/borg/cloak/cloak = allocate(/obj/item/borg/cloak, test_floor())
	cloak.forceMove(R)
	var/was_active = cloak.active
	hcs_menu(R, cloak, "toggle", "cloak_verb_toggle")
	TEST_ASSERT_NOTEQUAL(cloak.active, was_active, "the toggle entry flips the cloak")
	hcs_menu(R, cloak, "strength", "cloak_verb_set_level")
	settle()
	hci_answer(R, 20)
	settle()
	TEST_ASSERT_EQUAL(cloak.cloak_strength, 0.2, "the strength entry asks the level")

/datum/unit_test/dq_hc_silicon/robot_analyzer_alt_click_flips_mode

/datum/unit_test/dq_hc_silicon/robot_analyzer_alt_click_flips_mode/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/robotanalyzer/analyzer = allocate(/obj/item/robotanalyzer, test_floor())
	var/mode = analyzer.mode
	hci_click(H, analyzer, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT_NOTEQUAL(analyzer.mode, mode, "an alt-click with an empty hand flips the mode")
	mode = analyzer.mode
	H.set_stat(CONSCIOUS) // the test floor has no air: settle() let the actor fall unconscious, and an unconscious hand does nothing
	hci_click(H, analyzer, analyzer, I_HELP, "alt=1")
	settle()
	TEST_ASSERT_NOTEQUAL(analyzer.mode, mode, "an alt-click with the analyzer in hand flips the mode")

/datum/unit_test/dq_hc_silicon/mining_scanner_alt_click_asks_range

/datum/unit_test/dq_hc_silicon/mining_scanner_alt_click_asks_range/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/mining_scanner/robot/scanner = allocate(/obj/item/mining_scanner/robot, test_floor())
	scanner.upgrade(H)
	hci_click(H, scanner, scanner, I_HELP, "alt=1")
	hci_answer(H, 6) // answered at once: a settle() first would leave the actor unconscious on the airless test floor, and the answer re-checks it
	settle()
	TEST_ASSERT_EQUAL(scanner.range, 6, "an alt-click on the upgraded scanner asks its range")

/datum/unit_test/dq_hc_silicon/drone_takes_a_hat_in_help_stance

/datum/unit_test/dq_hc_silicon/drone_takes_a_hat_in_help_stance/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/silicon/robot/drone/D = allocate(/mob/living/silicon/robot/drone, get_step(H, EAST))
	var/obj/item/clothing/head/beret/hat = allocate(/obj/item/clothing/head/beret, test_floor())
	hci_click(H, D, hat, I_HELP)
	settle()
	TEST_ASSERT_EQUAL(D.hat, hat, "the hat goes on the drone")
	var/obj/item/clothing/head/beret/second = allocate(/obj/item/clothing/head/beret, test_floor())
	hci_click(H, D, second, I_HELP)
	settle()
	TEST_ASSERT_EQUAL(D.hat, hat, "a drone that wears a hat does not take another")
