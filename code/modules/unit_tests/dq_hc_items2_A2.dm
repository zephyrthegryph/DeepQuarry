// Behaviour-preservation tests for items group A2 (the radio family, medigun backpack, RPD, teleportation, wiki manuals, id cards, customizable toys,
// transfer valve, flamethrower, tanks). They pin what a player observes (a click, a window button, an answer, time passing) so the same file passes
// before and after the family moves to the final forms. State is read through plain vars; nothing depends on message text or on an op key. The
// helpers (hci_click, hci_answer, hci_ui) are in dq_hc_items_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Batch 1: the radio family
// ---------------------------------------------------------------------------------------------------------------------

/// Radios that say who opened their window: a person with no client cannot open a real one.
/obj/item/radio/hci2a2_probe
	var/mob/opened_by

/obj/item/radio/hci2a2_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	opened_by = user
	return TRUE

/obj/item/radio/headset/hci2a2_probe
	var/mob/opened_by

/obj/item/radio/headset/hci2a2_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	opened_by = user
	return TRUE

/obj/item/radio/electropack/hci2a2_probe
	var/mob/opened_by

/obj/item/radio/electropack/hci2a2_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	opened_by = user
	return TRUE

/obj/item/radio/intercom/hci2a2_probe
	var/mob/opened_by

/obj/item/radio/intercom/hci2a2_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	opened_by = user
	return TRUE

/datum/unit_test/dq_hc_items/radio_use_in_hand_opens_window

/datum/unit_test/dq_hc_items/radio_use_in_hand_opens_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/hci2a2_probe/R = allocate(/obj/item/radio/hci2a2_probe, tile(2, 2))
	hci_click(H, R, R)
	settle()
	TEST_ASSERT_EQUAL(R.opened_by, H, "using a radio in hand opens its window")
	var/obj/item/radio/hci2a2_probe/other = allocate(/obj/item/radio/hci2a2_probe, tile(3, 3))
	other.beacon = TRUE
	hci_click(H, other, other)
	settle()
	TEST_ASSERT_NULL(other.opened_by, "a radio that is a beacon has no radio window")

/datum/unit_test/dq_hc_items/headset_use_in_hand_opens_window

/datum/unit_test/dq_hc_items/headset_use_in_hand_opens_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/headset/hci2a2_probe/R = allocate(/obj/item/radio/headset/hci2a2_probe, tile(2, 2))
	hci_click(H, R, R)
	settle()
	TEST_ASSERT_EQUAL(R.opened_by, H, "using a headset in hand opens its window")
	TEST_ASSERT_EQUAL(R.tgui_state(H), GLOB.tgui_inventory_state, "a headset's window needs it in your inventory")

/datum/unit_test/dq_hc_items/radio_window_buttons

/datum/unit_test/dq_hc_items/radio_window_buttons/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/R = allocate(/obj/item/radio, tile(2, 2))
	TEST_ASSERT(!R.broadcasting, "starts not broadcasting")
	hci_ui(H, R, "broadcast")
	TEST_ASSERT(R.broadcasting, "the microphone button switches broadcasting on")
	hci_ui(H, R, "broadcast")
	TEST_ASSERT(!R.broadcasting, "and off")
	TEST_ASSERT(R.listening, "starts listening")
	hci_ui(H, R, "listen")
	TEST_ASSERT(!R.listening, "the speaker button switches listening off")
	hci_ui(H, R, "setFrequency", list("freq" = 1400))
	TEST_ASSERT_EQUAL(R.frequency, sanitize_frequency(1400), "the same as the sanitiser gives")
	TEST_ASSERT(!R.subspace_transmission, "starts without subspace")
	hci_ui(H, R, "subspace")
	TEST_ASSERT(!R.subspace_transmission, "a radio that cannot switch subspace refuses the button")
	R.subspace_switchable = TRUE
	hci_ui(H, R, "subspace")
	TEST_ASSERT(R.subspace_transmission, "a switchable radio goes to subspace")
	TEST_ASSERT(R.loudspeaker, "the loudspeaker starts on")
	hci_ui(H, R, "toggleLoudspeaker")
	TEST_ASSERT(!R.loudspeaker, "the loudspeaker button toggles it")
	R.subspace_switchable = FALSE
	hci_ui(H, R, "toggleLoudspeaker")
	TEST_ASSERT(!R.loudspeaker, "a radio that cannot switch ignores the loudspeaker button")

/datum/unit_test/dq_hc_items/radio_emp_silences

/datum/unit_test/dq_hc_items/radio_emp_silences/run_gate()
	var/obj/item/radio/R = allocate(/obj/item/radio, tile(2, 2))
	R.broadcasting = TRUE
	R.listening = TRUE
	R.channels = list("Security" = R.FREQ_LISTENING)
	R.emp_act(1)
	settle()
	TEST_ASSERT(!R.broadcasting, "an EMP switches the microphone off")
	TEST_ASSERT(!R.listening, "and the speaker")
	TEST_ASSERT_EQUAL(R.channels["Security"], 0, "and every channel")

/datum/unit_test/dq_hc_items/headset_takes_keys_into_two_slots

/datum/unit_test/dq_hc_items/headset_takes_keys_into_two_slots/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/radio/headset/R = allocate(/obj/item/radio/headset, T)
	var/obj/item/encryptionkey/headset_sec/K1 = allocate(/obj/item/encryptionkey/headset_sec, T)
	var/obj/item/encryptionkey/headset_eng/K2 = allocate(/obj/item/encryptionkey/headset_eng, T)
	var/obj/item/encryptionkey/headset_rob/K3 = allocate(/obj/item/encryptionkey/headset_rob, T)
	hci_click(H, R, K1)
	settle()
	TEST_ASSERT_EQUAL(R.keyslot1, K1, "the first key goes in the first slot")
	TEST_ASSERT("Security" in R.channels, "and its channel is open")
	hci_click(H, R, K2)
	settle()
	TEST_ASSERT_EQUAL(R.keyslot2, K2, "the second key goes in the second slot")
	hci_click(H, R, K3)
	settle()
	TEST_ASSERT(isnull(K3.loc) || K3.loc != R, "a third key is refused")
	TEST_ASSERT_EQUAL(R.keyslot1, K1, "the first stays")
	TEST_ASSERT_EQUAL(R.keyslot2, K2, "the second stays")

/datum/unit_test/dq_hc_items/borg_radio_takes_one_key

/datum/unit_test/dq_hc_items/borg_radio_takes_one_key/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/mob/living/silicon/robot/body = allocate(/mob/living/silicon/robot, T)
	var/obj/item/radio/borg/R = allocate(/obj/item/radio/borg, body)
	var/obj/item/encryptionkey/headset_sec/K1 = allocate(/obj/item/encryptionkey/headset_sec, T)
	var/obj/item/encryptionkey/headset_eng/K2 = allocate(/obj/item/encryptionkey/headset_eng, T)
	R.keyslot = null
	H.forceMove(T)
	hci_click(H, R, K1)
	settle()
	TEST_ASSERT_EQUAL(R.keyslot, K1, "a borg radio takes a key")
	hci_click(H, R, K2)
	settle()
	TEST_ASSERT_EQUAL(R.keyslot, K1, "a second key is refused")

/datum/unit_test/dq_hc_items/electropack_window_buttons

/datum/unit_test/dq_hc_items/electropack_window_buttons/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/electropack/E = allocate(/obj/item/radio/electropack, tile(2, 2))
	H.put_in_active_hand(E)
	var/start = E.on
	hci_ui(H, E, "power")
	TEST_ASSERT_NOTEQUAL(E.on, start, "the power button toggles it")
	TEST_ASSERT_EQUAL(E.icon_state, "electropack[E.on]", "and its look")
	var/f0 = E.frequency
	hci_ui(H, E, "freq", list("delta" = 2))
	TEST_ASSERT_EQUAL(E.frequency, sanitize_frequency(f0 + 2), "the frequency moves by the step")
	E.code = 2
	hci_ui(H, E, "code", list("delta" = 5))
	TEST_ASSERT_EQUAL(E.code, 7, "the code moves by the step")
	hci_ui(H, E, "code", list("delta" = -500))
	TEST_ASSERT_EQUAL(E.code, 1, "and stays at least one")
	hci_ui(H, E, "code", list("delta" = 500))
	TEST_ASSERT_EQUAL(E.code, 100, "and at most a hundred")

/datum/unit_test/dq_hc_items/electropack_use_opens_its_own_window

/datum/unit_test/dq_hc_items/electropack_use_opens_its_own_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/electropack/hci2a2_probe/E = allocate(/obj/item/radio/electropack/hci2a2_probe, tile(2, 2))
	hci_click(H, E, E)
	settle()
	TEST_ASSERT_EQUAL(E.opened_by, H, "using the pack in hand opens its window")

/datum/unit_test/dq_hc_items/electropack_worn_on_the_back_cannot_be_taken_off_by_its_wearer

/datum/unit_test/dq_hc_items/electropack_worn_on_the_back_cannot_be_taken_off_by_its_wearer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/electropack/E = allocate(/obj/item/radio/electropack, tile(2, 2))
	TEST_ASSERT(H.equip_to_slot_if_possible(E, SLOT_ID_BACK, disable_warning = TRUE), "the pack goes on the back")
	hci_click(H, E, null)
	settle()
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_BACK), E, "its wearer cannot take it off with an empty hand")

/datum/unit_test/dq_hc_items/electropack_helmet_makes_a_shock_kit

/datum/unit_test/dq_hc_items/electropack_helmet_makes_a_shock_kit/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/radio/electropack/E = allocate(/obj/item/radio/electropack, T)
	var/obj/item/clothing/head/helmet/helm = allocate(/obj/item/clothing/head/helmet, T)
	hci_click(H, E, helm)
	settle()
	TEST_ASSERT(!QDELETED(E) && E.loc == T, "a pack that is not open is not attached")
	E.b_stat = TRUE
	hci_click(H, E, helm)
	settle()
	var/found = FALSE
	for(var/obj/item/assembly/shock_kit/K in H.contents)
		found = TRUE
		TEST_ASSERT_EQUAL(K.part1, helm, "the helmet is the kit's first part")
		TEST_ASSERT_EQUAL(K.part2, E, "the pack is its second")
	TEST_ASSERT(found, "an open pack and a helmet make a shock kit in hand")
	for(var/obj/item/I in H.contents)
		qdel(I)

/datum/unit_test/dq_hc_items/jammer_use_toggles_and_drains

/datum/unit_test/dq_hc_items/jammer_use_toggles_and_drains/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio_jammer/J = allocate(/obj/item/radio_jammer, tile(2, 2))
	TEST_ASSERT(J.power_source, "a jammer has its cell")
	hci_click(H, J, J)
	settle()
	TEST_ASSERT(J.on, "using it switches it on")
	J.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(J.icon_state, J.active_state, "its look is the active one")
	var/before = J.power_source.charge
	test_time(10 SECONDS)
	TEST_ASSERT(J.power_source.charge < before, "a running jammer drains its cell")
	hci_click(H, J, J)
	settle()
	TEST_ASSERT(!J.on, "using it again switches it off")
	J.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(J.icon_state, initial(J.icon_state), "its look is the idle one")

/datum/unit_test/dq_hc_items/jammer_cell_in_and_out

/datum/unit_test/dq_hc_items/jammer_cell_in_and_out/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/radio_jammer/J = allocate(/obj/item/radio_jammer, T)
	var/obj/item/cell/device/weapon/cell = J.power_source
	H.put_in_inactive_hand(J)
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), J, "the jammer is in the other hand")
	hci_click(H, J, null)
	settle()
	TEST_ASSERT_NULL(J.power_source, "an empty hand takes the cell out of a jammer held in the other hand")
	TEST_ASSERT_EQUAL(H.get_active_hand(), cell, "the cell is in the hand")
	hci_click(H, J, J)
	settle()
	TEST_ASSERT(!J.on, "a jammer with no cell does not switch on")
	hci_click(H, J, cell)
	settle()
	TEST_ASSERT_EQUAL(J.power_source, cell, "a cell clicked onto an empty jammer goes in")

/datum/unit_test/dq_hc_items/syndicate_beacon_use_drops_a_singularity_beacon

/datum/unit_test/dq_hc_items/syndicate_beacon_use_drops_a_singularity_beacon/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/beacon/syndicate/B = allocate(/obj/item/radio/beacon/syndicate, tile(2, 2))
	hci_click(H, B, B)
	settle()
	TEST_ASSERT(QDELETED(B), "the suspicious beacon is used up")
	var/found = FALSE
	for(var/obj/machinery/power/singularity_beacon/syndicate/S in get_turf(H))
		found = TRUE
		qdel(S)
	TEST_ASSERT(found, "a singularity beacon is teleported to the user")

/// The beacon's alter-signal question, asked the way the game does for the menu entry (adapter: the legacy handler is called directly).
/proc/hci2a2_alter_beacon(mob/living/carbon/human/H, obj/item/radio/beacon/B)
	B.alter_signal_effect(H, null, null)

/datum/unit_test/dq_hc_items/beacon_alter_signal_asks_for_a_code

/datum/unit_test/dq_hc_items/beacon_alter_signal_asks_for_a_code/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/beacon/B = allocate(/obj/item/radio/beacon, tile(2, 2))
	H.put_in_active_hand(B)
	hci2a2_alter_beacon(H, B)
	settle()
	hci_answer(H, "tango")
	settle()
	TEST_ASSERT_EQUAL(B.code, "tango", "the answer is the new code")

/datum/unit_test/dq_hc_items/intercom_look_follows_power_and_panel

/datum/unit_test/dq_hc_items/intercom_look_follows_power_and_panel/run_gate()
	var/obj/item/radio/intercom/I = allocate(/obj/item/radio/intercom, tile(2, 2))
	var/area/A = get_area(I)
	var/had = A.requires_power
	A.requires_power = TRUE
	A.power_equip = FALSE
	I.update_icon()
	settle()
	TEST_ASSERT_EQUAL(I.icon_state, "intercom-p", "an unpowered intercom shows its dark state")
	TEST_ASSERT(!I.on, "and is off")
	I.wiresexposed = TRUE
	I.update_icon()
	settle()
	TEST_ASSERT_EQUAL(I.icon_state, "intercom-p_open", "with its wires out")
	A.requires_power = FALSE
	I.update_icon()
	settle()
	TEST_ASSERT_EQUAL(I.icon_state, "intercom_open", "a powered intercom with its wires out")
	TEST_ASSERT(I.on, "is on")
	I.wiresexposed = FALSE
	I.update_icon()
	settle()
	TEST_ASSERT_EQUAL(I.icon_state, initial(I.icon_state), "a powered intercom shows its plain state")
	A.requires_power = had

/datum/unit_test/dq_hc_items/intercom_hand_opens_window

/datum/unit_test/dq_hc_items/intercom_hand_opens_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/intercom/hci2a2_probe/I = allocate(/obj/item/radio/intercom/hci2a2_probe, tile(2, 3))
	hci_click(H, I, null)
	settle()
	TEST_ASSERT_EQUAL(I.opened_by, H, "an empty hand on an intercom opens its window")
