// Behaviour-preservation tests for the devices of group D2 (text-to-speech, hailer, selectable items, teleportation scroll, task manager, scanners, printers,
// floor painter, holowarrant, AI modules, sleevemate, mind binder). They pin what a player observes through clicks, answers and the kernel clock, so the
// same file passes before and after the group moves to the final forms. The helpers (hci_click, hci_answer) are in dq_hc_items_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Text-to-speech device
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/tts_use_names_the_device_and_asks

/datum/unit_test/dq_hc_items/tts_use_names_the_device_and_asks/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/text_to_speech/T = allocate(/obj/item/text_to_speech, tile(2, 2))
	TEST_ASSERT(!T.named, "starts unnamed")
	hci_click(H, T, T)
	settle()
	TEST_ASSERT(T.named, "the first use names the device")
	TEST_ASSERT(findtext(T.name, H.real_name), "after its user")
	hci_answer(H, "hello there")

/datum/unit_test/dq_hc_items/tts_alt_click_asks_too

/datum/unit_test/dq_hc_items/tts_alt_click_asks_too/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/text_to_speech/T = allocate(/obj/item/text_to_speech, tile(2, 2))
	hci_click(H, T, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(T.named, "an alt-click does what the use does")
	hci_answer(H, "x")

/datum/unit_test/dq_hc_items/tts_unnamed_stays_named_for_its_first_user

/datum/unit_test/dq_hc_items/tts_unnamed_stays_named_for_its_first_user/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/text_to_speech/T = allocate(/obj/item/text_to_speech, tile(2, 2))
	hci_click(H, T, T)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	var/first_name = T.name
	hci_click(H, T, T)
	settle()
	TEST_ASSERT_EQUAL(T.name, first_name, "a second use keeps the name")

// ---------------------------------------------------------------------------------------------------------------------
// Hailer
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/hailer_use_starts_the_cooldown

/datum/unit_test/dq_hc_items/hailer_use_starts_the_cooldown/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/hailer/R = allocate(/obj/item/hailer, tile(2, 2))
	TEST_ASSERT(COOLDOWN_FINISHED(R, spamcheck), "ready at first")
	hci_click(H, R, R)
	TEST_ASSERT(!COOLDOWN_FINISHED(R, spamcheck), "a use starts the cooldown")

/datum/unit_test/dq_hc_items/hailer_menu_sets_the_message

/datum/unit_test/dq_hc_items/hailer_menu_sets_the_message/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/hailer/R = allocate(/obj/item/hailer, tile(2, 2))
	H.put_in_active_hand(R)
	R.set_message_effect(H, null, null)
	settle()
	hci_answer(H, "stop right there")
	settle()
	TEST_ASSERT_EQUAL(R.use_message, "Stop right there", "the new message is capitalised")
	R.set_message_effect(H, null, null)
	settle()
	hci_answer(H, "")
	settle()
	TEST_ASSERT_EQUAL(R.use_message, "Halt! Security!", "a blank answer resets it")

/datum/unit_test/dq_hc_items/hailer_emag_overloads_once

/datum/unit_test/dq_hc_items/hailer_emag_overloads_once/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/hailer/R = allocate(/obj/item/hailer, tile(2, 2))
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(3, 3))
	TEST_ASSERT_NULL(R.insults, "a clean hailer")
	hci_click(H, R, E)
	settle()
	TEST_ASSERT(R.insults >= 1 && R.insults <= 3, "the sequencer overloads it with a few insults")
	var/insults = R.insults
	hci_click(H, R, E)
	settle()
	TEST_ASSERT_EQUAL(R.insults, insults, "a second sequencer does nothing more")
	H.put_in_active_hand(R)
	// MENU-REFUSAL
	hci_click(H, R, R)
	settle()
	TEST_ASSERT_EQUAL(R.insults, insults - 1, "a use spends an insult")

// ---------------------------------------------------------------------------------------------------------------------
// Selectable item
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/selectable_item_delivers_the_choice

/datum/unit_test/dq_hc_items/selectable_item_delivers_the_choice/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/selectable_item/S = allocate(/obj/item/selectable_item, T)
	hci_click(H, S, S)
	settle()
	test_answer(H, TRUE)
	settle()
	hci_answer(H, "Health Analyzer")
	settle()
	TEST_ASSERT(QDELETED(S), "the item is used up")
	var/found = FALSE
	for(var/obj/item/healthanalyzer/A in T)
		found = TRUE
	for(var/obj/item/healthanalyzer/A in H.contents)
		found = TRUE
	TEST_ASSERT(found, "the chosen item is delivered")
	for(var/obj/item/I in T)
		qdel(I)

/datum/unit_test/dq_hc_items/selectable_item_no_keeps_it

/datum/unit_test/dq_hc_items/selectable_item_no_keeps_it/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/selectable_item/S = allocate(/obj/item/selectable_item, tile(2, 2))
	hci_click(H, S, S)
	settle()
	test_answer(H, FALSE)
	settle()
	TEST_ASSERT(!QDELETED(S), "answering no keeps the item")
	hci_click(H, S, S)
	settle()
	test_answer(H, TRUE)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT(!QDELETED(S), "cancelling the choice keeps the item")

// ---------------------------------------------------------------------------------------------------------------------
// Teleportation scroll
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/scroll_yes_asks_for_an_area

/datum/unit_test/dq_hc_items/scroll_yes_asks_for_an_area/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/teleportation_scroll/S = allocate(/obj/item/teleportation_scroll, tile(2, 2))
	hci_click(H, S, S)
	settle()
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT(!isnull(SSrequests.open_for(H)), "a yes opens the question of where to jump")
	hci_answer(H, "nowhere in particular")
	settle()
	TEST_ASSERT_EQUAL(S.uses, 4, "an unknown area spends nothing")

/datum/unit_test/dq_hc_items/scroll_declining_or_cancelling_spends_nothing

/datum/unit_test/dq_hc_items/scroll_declining_or_cancelling_spends_nothing/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/start = tile(2, 2)
	var/obj/item/teleportation_scroll/S = allocate(/obj/item/teleportation_scroll, start)
	hci_click(H, S, S)
	settle()
	hci_answer(H, FALSE)
	settle()
	TEST_ASSERT_EQUAL(S.uses, 4, "declining spends nothing")
	hci_click(H, S, S)
	settle()
	hci_answer(H, TRUE)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(S.uses, 4, "cancelling the area spends nothing")
	TEST_ASSERT_EQUAL(get_turf(H), start, "and nobody moves")

// ---------------------------------------------------------------------------------------------------------------------
// Task manager
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/taskmanager_mode_follows_the_ring

/datum/unit_test/dq_hc_items/taskmanager_mode_follows_the_ring/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/taskmanager/M = allocate(/obj/item/taskmanager, tile(2, 2))
	M.scancount = 2
	hci_click(H, M, M)
	settle()
	hci_answer(H, "Medical")
	settle()
	TEST_ASSERT_EQUAL(M.mode, "Medical", "the chosen department is the mode")
	TEST_ASSERT_EQUAL(M.scancount, 0, "a new mode starts the count over")
	hci_click(H, M, M)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(M.mode, "Medical", "cancelling keeps the mode")

// ---------------------------------------------------------------------------------------------------------------------
// Scanners
// ---------------------------------------------------------------------------------------------------------------------

/// An analyzer that counts the scans made of it and a thing that counts the scans made of it.
/obj/item/analyzer/dq_probe
	var/scans = 0

/obj/item/analyzer/dq_probe/atmosanalyze(mob/user)
	scans++
	return list("probe")

/obj/structure/dq_scan_target
	name = "scan target"
	var/scans = 0

/obj/structure/dq_scan_target/atmosanalyze(mob/user)
	scans++
	return list("probe")

/datum/unit_test/dq_hc_items/gas_analyzer_use_scans_for_the_user

/datum/unit_test/dq_hc_items/gas_analyzer_use_scans_for_the_user/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/analyzer/dq_probe/A = allocate(/obj/item/analyzer/dq_probe, tile(2, 2))
	hci_click(H, A, A)
	settle()
	TEST_ASSERT_EQUAL(A.scans, 1, "an in-hand use scans the analyzer itself")
	var/obj/structure/dq_scan_target/other = allocate(/obj/structure/dq_scan_target, tile(2, 2))
	hci_click(H, other, A)
	settle()
	TEST_ASSERT_EQUAL(other.scans, 1, "a click on a nearby object scans it")

/datum/unit_test/dq_hc_items/gas_analyzer_special_handling_declines

/datum/unit_test/dq_hc_items/gas_analyzer_special_handling_declines/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/analyzer/dq_probe/A = allocate(/obj/item/analyzer/dq_probe, tile(2, 2))
	A.special_handling = TRUE
	hci_click(H, A, A)
	settle()
	TEST_ASSERT_EQUAL(A.scans, 0, "an analyzer that is handled elsewhere does not scan itself")

/datum/unit_test/dq_hc_items/mass_spectrometer_reads_blood_and_clears

/datum/unit_test/dq_hc_items/mass_spectrometer_reads_blood_and_clears/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/mass_spectrometer/M = allocate(/obj/item/mass_spectrometer, tile(2, 2))
	M.reagents.add_reagent(REAGENT_ID_BLOOD, 5, list("trace_chem" = list2params(list("inaprovaline" = 3))))
	TEST_ASSERT(M.reagents.total_volume > 0, "a sample is loaded")
	hci_click(H, M, M)
	settle()
	TEST_ASSERT_EQUAL(M.reagents.total_volume, 0, "reading the blood empties the sample")
	M.reagents.add_reagent(REAGENT_ID_WATER, 5)
	hci_click(H, M, M)
	settle()
	TEST_ASSERT_EQUAL(M.reagents.total_volume, 0, "a contaminated sample is dumped")
