// Behaviour-preservation tests for items group A1 (the communicator family, the pAI card, GPS, the AI card and the uplink). They pin what a player
// observes through clicks, windows and the kernel clock, so the same file passes before and after the group moves to the final forms. State is read
// through plain vars; nothing here depends on message text or on an op key. The helpers (hci_click, hci_answer, hci_ui) are in
// dq_hc_items_behaviour.dm.

/// Time passes for the kernel's timers and for the old periodic lanes of the object model alike.
/proc/a1_pass(t)
	test_time(t)
	scheduler_advance(t / (1 SECOND))

/// Has `actor` an open question (an engine request, or a prompt the old way collected)?
/proc/a1_asked(mob/actor)
	for(var/datum/request/R as anything in SSrequests.open)
		if(R.answerer == actor && R.is_open())
			return TRUE
	for(var/datum/om/prompt/P as anything in om_scheduler().test_prompts)
		if(!P.answered && P.peek("answerer") == actor)
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------------------------------
// AI card
// ---------------------------------------------------------------------------------------------------------------------

/// A card holding a fresh AI.
/datum/unit_test/dq_hc_items/proc/a1_carded_ai(turf/T)
	var/obj/item/aicard/card = allocate(/obj/item/aicard, T || tile(2, 2))
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, tile(3, 3), null, null, null, TRUE)
	rel_set(card, nameof(/obj/item/aicard::carded_ai), AI)
	return card

/datum/unit_test/dq_hc_items/aicard_window_toggles_radio_and_wireless

/datum/unit_test/dq_hc_items/aicard_window_toggles_radio_and_wireless/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/aicard/card = a1_carded_ai()
	var/mob/living/silicon/ai/AI = card.carded_ai()
	var/radio = AI.aiRadio.disabledAi
	var/wireless = AI.control_disabled
	hci_ui(H, card, "radio")
	TEST_ASSERT_NOTEQUAL(AI.aiRadio.disabledAi, radio, "the radio button flips the transceiver")
	hci_ui(H, card, "radio")
	TEST_ASSERT_EQUAL(AI.aiRadio.disabledAi, radio, "and flips it back")
	hci_ui(H, card, "wireless")
	TEST_ASSERT_NOTEQUAL(AI.control_disabled, wireless, "the wireless button flips the interface")
	hci_ui(H, card, "wireless")
	TEST_ASSERT_EQUAL(AI.control_disabled, wireless, "and flips it back")

/datum/unit_test/dq_hc_items/aicard_window_does_nothing_without_an_ai

/datum/unit_test/dq_hc_items/aicard_window_does_nothing_without_an_ai/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/aicard/card = allocate(/obj/item/aicard, tile(2, 2))
	hci_ui(H, card, "radio")
	hci_ui(H, card, "wireless")
	hci_ui(H, card, "wipe")
	settle()
	TEST_ASSERT_NULL(card.flush, "an empty card cannot be wiped")
	var/list/data = hc_data(card, H)
	TEST_ASSERT(!data["has_ai"], "the window says the card is empty")

/datum/unit_test/dq_hc_items/aicard_window_data_and_wipe

/datum/unit_test/dq_hc_items/aicard_window_data_and_wipe/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/aicard/card = a1_carded_ai()
	var/mob/living/silicon/ai/AI = card.carded_ai()
	var/list/data = hc_data(card, H)
	TEST_ASSERT(data["has_ai"], "the window says the card holds an AI")
	TEST_ASSERT_EQUAL(data["name"], AI.name, "and names it")
	TEST_ASSERT_EQUAL(data["wireless"], !AI.control_disabled, "and shows the interface")
	hci_ui(H, card, "wipe")
	TEST_ASSERT(card.flush, "the wipe button starts the purge")
	TEST_ASSERT(AI.suiciding, "and the AI is marked as dying")

/datum/unit_test/dq_hc_items/aicard_look_follows_the_ai

/datum/unit_test/dq_hc_items/aicard_look_follows_the_ai/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/aicard/card = allocate(/obj/item/aicard, tile(2, 2))
	card.update_icon()
	settle()
	TEST_ASSERT_EQUAL(card.icon_state, "aicard", "an empty card shows the plain state")
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, tile(3, 3), null, null, null, TRUE)
	card.grab_ai_timed_done(AI, H)
	settle()
	TEST_ASSERT_EQUAL(card.carded_ai(), AI, "the transfer fills the card")
	TEST_ASSERT_EQUAL(card.icon_state, "aicard-full", "a card with an AI shows the full state")
	var/bare = length(card.overlays)
	hci_ui(H, card, "wireless")
	settle()
	TEST_ASSERT(length(card.overlays) > bare, "an AI with its wireless interface up shows the light")
	AI.death()
	settle()
	TEST_ASSERT_EQUAL(card.icon_state, "aicard-404", "a dead AI shows the 404 state")
	card.clear()
	settle()
	TEST_ASSERT_EQUAL(card.icon_state, "aicard", "a card that lets its AI go shows the plain state again")
	qdel(locate(/obj/structure/AIcore/deactivated) in tile(3, 3))

// ---------------------------------------------------------------------------------------------------------------------
// GPS
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/gps_alt_click_toggles_power

/datum/unit_test/dq_hc_items/gps_alt_click_toggles_power/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gps/G = allocate(/obj/item/gps, tile(2, 2))
	TEST_ASSERT(!G.tracking, "starts off")
	hci_click(H, G, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(G.tracking, "an alt-click switches it on")
	G.update_icon()
	settle()
	var/lit = length(G.overlays)
	hci_click(H, G, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(!G.tracking, "another alt-click switches it off")
	G.update_icon()
	settle()
	TEST_ASSERT(lit > length(G.overlays), "the working light goes with the power")

/datum/unit_test/dq_hc_items/gps_alt_click_is_refused_while_busted

/datum/unit_test/dq_hc_items/gps_alt_click_is_refused_while_busted/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gps/G = allocate(/obj/item/gps, tile(2, 2))
	G.emp_act(1)
	settle()
	TEST_ASSERT(EXPIRY_ACTIVE(G, emp_until, CLOCK_WORLD), "an EMP busts the unit")
	hci_click(H, G, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(!G.tracking, "a busted unit cannot be switched on")

/datum/unit_test/dq_hc_items/gps_window_buttons

/datum/unit_test/dq_hc_items/gps_window_buttons/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gps/G = allocate(/obj/item/gps, tile(2, 2))
	var/obj/item/gps/other = allocate(/obj/item/gps/on, tile(3, 3))
	hci_ui(H, G, "power")
	TEST_ASSERT(G.tracking, "the power button switches it on")
	hci_ui(H, G, "rename", list("value" = "alpha"))
	TEST_ASSERT_EQUAL(G.gps_tag, "ALPHA", "the rename button sets an upper-case tag")
	TEST_ASSERT_EQUAL(G.name, "global positioning system (ALPHA)", "and the name follows")
	hci_ui(H, G, "rename", list("value" = ""))
	TEST_ASSERT_EQUAL(G.gps_tag, "ALPHA", "an empty name changes nothing")
	hci_ui(H, G, "localMode")
	TEST_ASSERT(G.local_mode, "the local button narrows the range")
	hci_ui(H, G, "hideSignal")
	TEST_ASSERT(!G.hide_signal, "a unit that cannot hide ignores the hide button")
	G.can_hide_signal = TRUE
	hci_ui(H, G, "hideSignal")
	TEST_ASSERT(G.hide_signal, "a unit that can hide hides")
	var/ref = "\ref[other]"
	hci_ui(H, G, "startTrack", list("ref" = ref))
	TEST_ASSERT(LAZYACCESS(G.tracking_devices, ref), "the track button follows another unit")
	TEST_ASSERT(LAZYACCESS(G.showing_tracked_names, ref), "and shows its tag")
	hci_ui(H, G, "trackLabel", list("ref" = ref))
	TEST_ASSERT(!LAZYACCESS(G.showing_tracked_names, ref), "the label button hides the tag")
	hci_ui(H, G, "trackLabel", list("ref" = ref))
	TEST_ASSERT(LAZYACCESS(G.showing_tracked_names, ref), "and shows it again")
	hci_ui(H, G, "trackColor", list("ref" = ref, "color" = "#ff0000"))
	TEST_ASSERT_EQUAL(LAZYACCESS(G.tracking_devices, ref), "#ff0000", "the colour button colours the track")
	hci_ui(H, G, "stopTrack", list("ref" = ref))
	TEST_ASSERT(!LAZYACCESS(G.tracking_devices, ref), "the stop button forgets the unit")

/datum/unit_test/dq_hc_items/gps_window_data_lists_visible_signals

/datum/unit_test/dq_hc_items/gps_window_data_lists_visible_signals/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gps/G = allocate(/obj/item/gps/on, tile(2, 2))
	var/obj/item/gps/other = allocate(/obj/item/gps/on, tile(4, 4))
	var/obj/item/gps/hidden = allocate(/obj/item/gps/syndie, tile(5, 5))
	hidden.set_tracking(TRUE)
	var/list/data = hc_data(G, H)
	TEST_ASSERT(data["power"], "the window shows the power")
	TEST_ASSERT_EQUAL(data["tag"], G.gps_tag, "and the tag")
	var/found_other = FALSE
	var/found_hidden = FALSE
	for(var/list/signal in data["signals"])
		if(signal["ref"] == "\ref[other]")
			found_other = TRUE
		if(signal["ref"] == "\ref[hidden]")
			found_hidden = TRUE
	TEST_ASSERT(found_other, "another running unit is listed")
	TEST_ASSERT(!found_hidden, "a hiding unit is not")

// ---------------------------------------------------------------------------------------------------------------------
// Uplink
// ---------------------------------------------------------------------------------------------------------------------

/// The hidden uplink of a fresh uplink radio.
/datum/unit_test/dq_hc_items/proc/a1_uplink(turf/T)
	var/obj/item/radio/uplink/R = allocate(/obj/item/radio/uplink, T || tile(2, 2))
	return item_hidden_uplink(R)

/datum/unit_test/dq_hc_items/uplink_window_buttons

/datum/unit_test/dq_hc_items/uplink_window_buttons/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/uplink/hidden/U = a1_uplink()
	TEST_ASSERT(U, "the radio has its uplink")
	U.active = TRUE
	hci_ui(H, U, "select", list("category" = "Weapons"))
	TEST_ASSERT_EQUAL(U.selected_cat, "Weapons", "the category button selects it")
	TEST_ASSERT(!U.compact_mode, "starts roomy")
	hci_ui(H, U, "compact_toggle")
	TEST_ASSERT(U.compact_mode, "the compact button switches the layout")
	hci_ui(H, U, "view_exploits", list("id" = 7))
	TEST_ASSERT_EQUAL(U.exploit_id, 7, "the exploit button picks a record")
	hci_ui(H, U, "lock")
	TEST_ASSERT(!U.active, "the lock button switches the uplink off")

/// An uplink whose window is always usable: the real one needs a player's client.
/obj/item/uplink/hidden/a1_open

/obj/item/uplink/hidden/a1_open/tgui_status(mob/user, datum/tgui_state/state)
	return STATUS_INTERACTIVE

/datum/unit_test/dq_hc_items/uplink_buy_spends_telecrystals

/datum/unit_test/dq_hc_items/uplink_buy_spends_telecrystals/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/uplink/R = allocate(/obj/item/radio/uplink, tile(2, 2))
	var/obj/item/uplink/hidden/U = new /obj/item/uplink/hidden/a1_open(R)
	U.active = TRUE
	H.mind = new /datum/mind(H.key)
	H.mind.tcrystals = 100
	var/before = H.mind.tcrystals
	var/tries = 0
	for(var/datum/uplink_item/I in GLOB.uplink.items)
		if(I.item_cost <= 0 || I.item_cost > 5 || !istype(I, /datum/uplink_item/item))
			continue
		hci_ui(H, U, "buy", list("ref" = "\ref[I]"))
		if(H.mind.tcrystals < before)
			break
		if(++tries >= 20)
			break
	settle()
	TEST_ASSERT(H.mind.tcrystals < before, "buying spends crystals")
	var/spent = H.mind.tcrystals
	hci_ui(H, U, "buy", list("ref" = "\ref[H]"))
	TEST_ASSERT_EQUAL(H.mind.tcrystals, spent, "a ref that is no catalogue item buys nothing")
	qdel(U)

/datum/unit_test/dq_hc_items/uplink_window_data_follows_the_viewer

/datum/unit_test/dq_hc_items/uplink_window_data_follows_the_viewer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/uplink/hidden/U = a1_uplink()
	U.active = TRUE
	H.mind = new /datum/mind(H.key)
	H.mind.tcrystals = 12
	U.compact_mode = TRUE
	var/list/data = hc_data(U, H)
	TEST_ASSERT_EQUAL(data["telecrystals"], 12, "the window shows the viewer's crystals")
	TEST_ASSERT(data["compactMode"], "and the layout")

/datum/unit_test/dq_hc_items/uplink_offers_a_discount_over_time

/datum/unit_test/dq_hc_items/uplink_offers_a_discount_over_time/run_gate()
	var/obj/item/uplink/hidden/U = a1_uplink()
	TEST_ASSERT_NULL(U.discount_item(), "starts without an offer")
	test_time(U.offer_time + 1 MINUTE)
	TEST_ASSERT(U.discount_item(), "a discount is offered after the offer time")
	TEST_ASSERT(U.discount_amount > 0 && U.discount_amount < 1, "and it is a fraction")

// ---------------------------------------------------------------------------------------------------------------------
// pAI card
// ---------------------------------------------------------------------------------------------------------------------

/// A test that puts a pAI in a card: the card lets go of it before the block is swept, so no spark outlives the test.
/datum/unit_test/dq_hc_items/a1_pai
	abstract_type = /datum/unit_test/dq_hc_items/a1_pai
	var/list/a1_cards

/datum/unit_test/dq_hc_items/a1_pai/Run()
	..()
	for(var/obj/item/paicard/card as anything in a1_cards)
		card.removePersonality()

/// A card with a pAI in it, on a tile.
/datum/unit_test/dq_hc_items/a1_pai/proc/card_with_pai(turf/T)
	var/obj/item/paicard/card = allocate(/obj/item/paicard, T || tile(2, 2))
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai, card)
	if(!card.pai)
		rel_set(card, nameof(/obj/item/paicard::pai), P)
	LAZYADD(a1_cards, card)
	return card

/datum/unit_test/dq_hc_items/a1_pai/paicard_in_hand_asks_which_part_when_the_panel_is_open

/datum/unit_test/dq_hc_items/a1_pai/paicard_in_hand_asks_which_part_when_the_panel_is_open/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, tile(2, 2))
	hci_click(H, card, card)
	settle()
	hci_answer(H, "cell")
	settle()
	TEST_ASSERT_EQUAL(card.cell, PP_FUNCTIONAL, "a closed card asks nothing: it opens its window")
	card.panel_open = TRUE
	hci_click(H, card, card)
	settle()
	hci_answer(H, "cell")
	settle()
	TEST_ASSERT_EQUAL(card.cell, PP_MISSING, "an open card removes the part picked after a wait")
	var/obj/item/paiparts/cell/dropped = locate(/obj/item/paiparts/cell) in get_turf(H)
	TEST_ASSERT(dropped, "and the part drops at the person's feet")
	qdel(dropped)

/datum/unit_test/dq_hc_items/a1_pai/paicard_screwdriver_opens_with_a_pai_and_closes

/datum/unit_test/dq_hc_items/a1_pai/paicard_screwdriver_opens_with_a_pai_and_closes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paicard/card = card_with_pai()
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, tile(2, 2))
	hci_click(H, card, S)
	settle()
	TEST_ASSERT(card.panel_open, "a screwdriver opens the panel of a card with a pAI after a wait")
	hci_click(H, card, S)
	settle()
	TEST_ASSERT(!card.panel_open, "and closes it again")
	var/obj/item/paicard/empty = allocate(/obj/item/paicard, tile(3, 3))
	hci_click(H, empty, S)
	settle()
	TEST_ASSERT(!empty.panel_open, "an empty card stays shut")

/datum/unit_test/dq_hc_items/a1_pai/paicard_part_installs_after_a_wait

/datum/unit_test/dq_hc_items/a1_pai/paicard_part_installs_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, tile(2, 2))
	var/obj/item/paiparts/cell/part = allocate(/obj/item/paiparts/cell, tile(2, 2))
	card.cell = PP_MISSING
	card.panel_open = TRUE
	hci_click(H, card, part)
	TEST_ASSERT_EQUAL(card.cell, PP_MISSING, "the part is not in at once")
	settle()
	TEST_ASSERT_EQUAL(card.cell, PP_FUNCTIONAL, "an open card takes the part after a wait")
	TEST_ASSERT(QDELETED(part), "and the part is used up")

/datum/unit_test/dq_hc_items/a1_pai/paicard_id_swipe_edits_the_pai_access

/datum/unit_test/dq_hc_items/a1_pai/paicard_id_swipe_edits_the_pai_access/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paicard/card = card_with_pai()
	var/obj/item/card/id/ID = allocate(/obj/item/card/id, tile(2, 2))
	ID.access = list(ACCESS_SECURITY)
	card.pai.idcard.access = list()
	card.pai.idaccessible = 0
	hci_click(H, card, ID)
	settle()
	hci_answer(H, "Add Access")
	settle()
	TEST_ASSERT(!length(card.pai.idcard.access), "a pAI that does not accept access takes none")
	card.pai.idaccessible = 1
	hci_click(H, card, ID)
	settle()
	hci_answer(H, "Add Access")
	settle()
	TEST_ASSERT(ACCESS_SECURITY in card.pai.idcard.access, "Add Access copies the card's access")
	hci_click(H, card, ID)
	settle()
	hci_answer(H, "Remove Access")
	settle()
	TEST_ASSERT(!length(card.pai.idcard.access), "Remove Access clears it")
	hci_click(H, card, ID)
	settle()
	H.drop_item()
	ID.forceMove(tile(4, 4))
	hci_answer(H, "Add Access")
	settle()
	TEST_ASSERT(!length(card.pai.idcard.access), "a card that left the hand copies nothing")

/datum/unit_test/dq_hc_items/a1_pai/paicard_window_buttons

/datum/unit_test/dq_hc_items/a1_pai/paicard_window_buttons/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paicard/empty = allocate(/obj/item/paicard, tile(3, 3))
	hci_ui(H, empty, "preview", list("ref" = "abc"))
	TEST_ASSERT_EQUAL(empty.selected_pai, "abc", "the preview button picks a candidate for an empty card")
	hci_ui(H, empty, "clear_preview")
	TEST_ASSERT_NULL(empty.selected_pai, "and the clear button forgets it")
	var/obj/item/paicard/card = card_with_pai()
	hci_ui(H, card, "preview", list("ref" = "abc"))
	TEST_ASSERT_NULL(card.selected_pai, "a card with a pAI ignores the preview button")
	var/mob/living/silicon/pai/P = card.pai
	hci_ui(H, card, "setdna")
	TEST_ASSERT_EQUAL(P.master, H.real_name, "the bind button makes the viewer the master")
	TEST_ASSERT(P.master_dna, "by their DNA")
	hci_ui(H, card, "cleardna")
	TEST_ASSERT_NULL(P.master_dna, "the clear button frees the pAI")
	var/broadcasting = card.radio.broadcasting
	hci_ui(H, card, "wires", list("wires" = 4))
	TEST_ASSERT_NOTEQUAL(card.radio.broadcasting, broadcasting, "the transmit wire flips the radio")
	var/listening = card.radio.listening
	hci_ui(H, card, "wires", list("wires" = 2))
	TEST_ASSERT_NOTEQUAL(card.radio.listening, listening, "the receive wire flips the radio")
	hci_ui(H, card, "setlaws", list("directive" = "Be kind"))
	TEST_ASSERT_EQUAL(P.pai_laws, "Be kind", "the directive button sets the supplemental law")
	hci_ui(H, card, "clearlaws")
	TEST_ASSERT_NULL(P.pai_laws, "and the clear button removes it")
	var/list/data = hc_data(card, H)
	TEST_ASSERT(data["active_pai_data"], "the window shows the pAI")
	card.cell = PP_BROKEN
	hci_ui(H, card, "setlaws", list("directive" = "Be rude"))
	TEST_ASSERT_NULL(P.pai_laws, "a card with a broken critical part ignores its window")

/datum/unit_test/dq_hc_items/a1_pai/paicard_emag_needs_a_pai_and_unlocks_tools

/datum/unit_test/dq_hc_items/a1_pai/paicard_emag_needs_a_pai_and_unlocks_tools/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	var/obj/item/paicard/empty = allocate(/obj/item/paicard, tile(3, 3))
	var/uses = E.uses
	hci_click(H, empty, E)
	settle()
	TEST_ASSERT(!empty.emagged, "an empty card is not subverted")
	TEST_ASSERT_EQUAL(E.uses, uses, "and the sequencer keeps its use")
	var/obj/item/paicard/card = card_with_pai()
	hci_click(H, card, E)
	settle()
	TEST_ASSERT(card.emagged, "a card with a pAI is subverted")
	TEST_ASSERT(card.multitool, "and gains a multitool")
	TEST_ASSERT(card.signaler, "and a signaler")
	TEST_ASSERT_EQUAL(E.uses, uses - 1, "the sequencer pays a use")
	hci_ui(H, card, "select_tool", list("tool" = "Signaler"))
	TEST_ASSERT_EQUAL(card.selected_system, "Signaler", "the tool button picks a system")
	hci_ui(H, card, "select_tool", list("tool" = "Nonsense"))
	TEST_ASSERT_EQUAL(card.selected_system, "Signaler", "an unknown system changes nothing")

/datum/unit_test/dq_hc_items/a1_pai/sleevecard_keeps_its_own_item_and_use_handling

/datum/unit_test/dq_hc_items/a1_pai/sleevecard_keeps_its_own_item_and_use_handling/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paicard/sleevecard/S = allocate(/obj/item/paicard/sleevecard, tile(2, 2))
	var/obj/item/tool/screwdriver/D = allocate(/obj/item/tool/screwdriver, tile(2, 2))
	S.panel_open = TRUE
	hci_click(H, S, D)
	settle()
	TEST_ASSERT(S.panel_open, "an item the sleevecard does not know never reaches the card's own item handling")
	S.panel_open = TRUE
	hci_click(H, S, S)
	settle()
	hci_answer(H, "cell")
	settle()
	TEST_ASSERT_EQUAL(S.cell, PP_FUNCTIONAL, "a sleevecard with no mind asks nothing in hand")
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	var/uses = E.uses
	hci_click(H, S, E)
	settle()
	TEST_ASSERT(S.emagged, "a sequencer swiped over a sleevecard subverts it")
	TEST_ASSERT_EQUAL(E.uses, uses - 1, "and pays a use")

/datum/unit_test/dq_hc_items/a1_pai/paicard_radio_swallows_every_item

/datum/unit_test/dq_hc_items/a1_pai/paicard_radio_swallows_every_item/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/borg/pai/R = allocate(/obj/item/radio/borg/pai, tile(2, 2))
	var/obj/item/encryptionkey/K = allocate(/obj/item/encryptionkey, tile(2, 2))
	hci_click(H, R, K)
	settle()
	TEST_ASSERT_NULL(R.keyslot, "the pAI radio takes no key")
	TEST_ASSERT_EQUAL(K.loc, H, "and the key stays with the person")

// ---------------------------------------------------------------------------------------------------------------------
// Communicator
// ---------------------------------------------------------------------------------------------------------------------

/// A voice on the line of a communicator, as the interim hangup test makes one.
/datum/unit_test/dq_hc_items/proc/a1_voice(obj/item/communicator/comm)
	var/mob/living/voice/V = allocate(/mob/living/voice, comm)
	rel_add(comm, nameof(/obj/item/communicator::voice_mobs), V)
	registry_join(REGISTRY_LISTENING_OBJECTS, comm)
	return V

/datum/unit_test/dq_hc_items/comm_in_hand_clears_the_alert_and_makes_an_address

/datum/unit_test/dq_hc_items/comm_in_hand_clears_the_alert_and_makes_an_address/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	C.alert_called = 1
	C.update_icon()
	settle()
	TEST_ASSERT_EQUAL(C.icon_state, "communicator-called", "a called communicator shows it")
	hci_click(H, C, C)
	settle()
	TEST_ASSERT(!C.alert_called, "using it in hand clears the alert")
	TEST_ASSERT(C.exonet?.address, "and gives it an address")
	TEST_ASSERT_EQUAL(C.icon_state, "communicator", "and the look follows")

/datum/unit_test/dq_hc_items/comm_id_is_read_slotted_and_ejected

/datum/unit_test/dq_hc_items/comm_id_is_read_slotted_and_ejected/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	var/obj/item/card/id/ID = allocate(/obj/item/card/id, tile(2, 2))
	ID.registered_name = "Bob"
	ID.assignment = "Clown"
	C.owner = "Bob"
	H.put_in_inactive_hand(C)
	hci_click(H, C, ID)
	settle()
	TEST_ASSERT_EQUAL(C.occupation, "Clown", "an ID of the owner sets the occupation")
	TEST_ASSERT_NULL(C.id, "the first swipe does not slot it")
	hci_click(H, C, ID)
	settle()
	TEST_ASSERT_EQUAL(C.id, ID, "the second swipe slots the card")
	hci_click(H, C, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT_NULL(C.id, "an alt-click ejects it")
	TEST_ASSERT_EQUAL(ID.loc, H, "into the person's hands")

/datum/unit_test/dq_hc_items/comm_window_buttons

/datum/unit_test/dq_hc_items/comm_window_buttons/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	C.initialize_exonet(H)
	hci_ui(H, C, "toggle_visibility")
	TEST_ASSERT(!C.network_visibility, "the visibility button hides it")
	hci_ui(H, C, "toggle_visibility")
	TEST_ASSERT(C.network_visibility, "and shows it again")
	var/ringer = C.ringer
	hci_ui(H, C, "toggle_ringer")
	TEST_ASSERT_NOTEQUAL(C.ringer, ringer, "the ringer button flips the ringer")
	hci_ui(H, C, "selfie_mode")
	TEST_ASSERT(C.selfie_mode, "the selfie button switches the mode")
	hci_ui(H, C, "Light")
	TEST_ASSERT(C.fon, "the light button lights it")
	hci_ui(H, C, "Light")
	TEST_ASSERT(!C.fon, "and darkens it")
	for(var/i in 1 to 5)
		hci_ui(H, C, "add_hex", list("add_hex" = "a"))
	TEST_ASSERT_EQUAL(C.target_address, "aaaa:a", "the hex buttons build an address with colons")
	hci_ui(H, C, "write_target_address", list("val" = "abc"))
	TEST_ASSERT_EQUAL(C.target_address, "abc", "a written address replaces it")
	hci_ui(H, C, "clear_target_address")
	TEST_ASSERT_EQUAL(C.target_address, "", "the clear button empties it")
	hci_ui(H, C, "copy", list("copy" = "1234"))
	TEST_ASSERT_EQUAL(C.target_address, "1234", "the copy button takes an address")
	hci_ui(H, C, "copy_name", list("copy_name" = "Zed"))
	TEST_ASSERT_EQUAL(C.target_address_name, "Zed", "and a name")
	hci_ui(H, C, "switch_tab", list("switch_tab" = 3))
	TEST_ASSERT_EQUAL(C.selected_tab, 3, "the tab button switches the tab")
	hci_ui(H, C, "newsfeed", list("newsfeed" = 2))
	TEST_ASSERT_EQUAL(C.newsfeed_channel, 2, "the news button picks a channel")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["currentTab"], 3, "the window shows the tab")
	TEST_ASSERT_EQUAL(data["targetAddress"], "1234", "the address")
	TEST_ASSERT_EQUAL(data["targetAddressName"], "Zed", "and the name")
	TEST_ASSERT_EQUAL(data["visible"], C.network_visibility, "the visibility")
	TEST_ASSERT_EQUAL(data["ring"], C.ringer, "the ringer")
	TEST_ASSERT_EQUAL(data["selfie_mode"], C.selfie_mode, "and the selfie mode")

/datum/unit_test/dq_hc_items/comm_window_questions

/datum/unit_test/dq_hc_items/comm_window_questions/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	C.initialize_exonet(H)
	for(var/action in list("rename", "set_ringer_tone", "edit"))
		TEST_ASSERT(!a1_asked(H), "no question is open before the [action] button")
		hci_ui(H, C, action)
		TEST_ASSERT(a1_asked(H), "the [action] button asks a question")
		hci_answer(H, null, TRUE)
		TEST_ASSERT(!a1_asked(H), "and a cancel closes it")
	hci_ui(H, C, "message", list("message" = "1234"))
	TEST_ASSERT(!a1_asked(H), "with no exonet link a message is refused before it is asked")
	TEST_ASSERT(!length(C.im_list), "and nothing was sent")

/datum/unit_test/dq_hc_items/comm_hang_up_and_disconnect_close_voices

/datum/unit_test/dq_hc_items/comm_hang_up_and_disconnect_close_voices/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	var/mob/living/voice/first = a1_voice(C)
	var/mob/living/voice/second = a1_voice(C)
	first.name = "Alpha"
	second.name = "Beta"
	hci_ui(H, C, "disconnect", list("disconnect" = "Alpha"))
	settle()
	TEST_ASSERT(QDELETED(first), "the disconnect button drops the voice it names")
	TEST_ASSERT(!QDELETED(second), "and keeps the other")
	hci_ui(H, C, "hang_up")
	settle()
	TEST_ASSERT(QDELETED(second), "the hang up button drops them all")

/datum/unit_test/dq_hc_items/comm_emp_drops_the_call

/datum/unit_test/dq_hc_items/comm_emp_drops_the_call/run_gate()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	var/mob/living/voice/V = a1_voice(C)
	C.emp_act(1)
	settle()
	TEST_ASSERT(QDELETED(V), "an EMP hangs up the line")

/datum/unit_test/dq_hc_items/comm_look_follows_the_line

/datum/unit_test/dq_hc_items/comm_look_follows_the_line/run_gate()
	var/obj/item/communicator/C = allocate(/obj/item/communicator, tile(2, 2))
	C.update_icon()
	settle()
	TEST_ASSERT_EQUAL(C.icon_state, "communicator", "idle shows the plain state")
	var/mob/living/voice/V = a1_voice(C)
	C.update_icon()
	settle()
	TEST_ASSERT_EQUAL(C.icon_state, "communicator-active", "a line shows the active state")
	C.close_connection(null, V, "hung up")
	settle()
	TEST_ASSERT_EQUAL(C.icon_state, "communicator", "and the state goes with it")
