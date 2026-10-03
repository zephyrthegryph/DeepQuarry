// The gate of the engine gaps the phase-2 conversions hit: prompt kinds, timed stall hooks, the held-verb part, mob drags and player clicks for natural
// weapons. Every test drives the engine through the test driver. The fixtures are code/tests/engine/eg2_fixtures.dm.

/datum/unit_test/dq_eg2
	abstract_type = /datum/unit_test/dq_eg2

/datum/unit_test/dq_eg2/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_eg2/proc/run_gate()
	return

/// A conscious person with hands.
/datum/unit_test/dq_eg2/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

// ---------------------------------------------------------------------------------------------------------------------
// Prompt kinds
// ---------------------------------------------------------------------------------------------------------------------

/// A choice from a literal list: a value that is not one of them is refused and the question stays open; a valid one answers.
/datum/unit_test/dq_eg2/prompt_choice_from_a_list
/datum/unit_test/dq_eg2/prompt_choice_from_a_list/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "pick")
	var/datum/prompt/choice/asked = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(asked, "the op opened a question")
	TEST_ASSERT(istype(asked), "it is a choice")
	TEST_ASSERT_EQUAL(length(asked.choices), 2, "with the declared choices")
	test_answer(H, "green")
	TEST_ASSERT_EQUAL(F.ran, 0, "a value that is not a choice ran nothing")
	TEST_ASSERT(SSrequests.open_for(H) == asked, "and the question is still open")
	test_answer(H, "blue")
	TEST_ASSERT_EQUAL(F.got, "blue", "a choice answers")
	TEST_ASSERT_EQUAL(F.ran, 1, "and the op ran once")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "nothing is left open")

/// A choice from a proc of the holder: it is asked when the op asks.
/datum/unit_test/dq_eg2/prompt_choice_from_a_proc
/datum/unit_test/dq_eg2/prompt_choice_from_a_proc/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "pick_proc")
	var/datum/prompt/choice/asked = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(asked, "the op opened a question")
	TEST_ASSERT(("alpha" in asked.choices) && ("beta" in asked.choices) && length(asked.choices) == 2, "its choices are what the holder's proc computed")
	test_answer(H, "alpha")
	TEST_ASSERT_EQUAL(F.got, "alpha", "an answer from the computed list")

/// A list with nothing in it has nothing to show: the window is never made for it.
/datum/unit_test/dq_eg2/prompt_choice_with_nothing_to_pick
/datum/unit_test/dq_eg2/prompt_choice_with_nothing_to_pick/run_gate()
	var/mob/living/carbon/human/H = person()
	var/datum/prompt/choice/empty = new
	TEST_ASSERT_NULL(empty.present(H), "an empty list shows no window")
	var/datum/prompt/choice/some = new
	some.choices = list("one")
	TEST_ASSERT_NOTNULL(some.refusal("two"), "a value outside the list is refused")
	TEST_ASSERT_NULL(some.refusal("one"), "one inside it is allowed")
	qdel(empty)
	qdel(some)

/// A colour is lowercased to "#rrggbb"; text that is not a colour is refused.
/datum/unit_test/dq_eg2/prompt_color
/datum/unit_test/dq_eg2/prompt_color/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "tint")
	var/datum/prompt/color/asked = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(asked, "the op opened a question")
	TEST_ASSERT_EQUAL(asked.default, "#336699", "the picker starts on the holder's own colour (a named var is read from the capture)")
	test_answer(H, "red")
	test_answer(H, "#12")
	TEST_ASSERT_EQUAL(F.ran, 0, "text that is not a colour ran nothing")
	test_answer(H, "#FF8800")
	TEST_ASSERT_EQUAL(F.got, "#ff8800", "a colour answers, normalised")

/// A checklist answers the ticked choices, in the list's order, within its count limits.
/datum/unit_test/dq_eg2/prompt_checklist
/datum/unit_test/dq_eg2/prompt_checklist/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "boxes")
	test_answer(H, list())
	test_answer(H, list("a", "b", "c"))
	TEST_ASSERT_EQUAL(F.ran, 0, "too few and too many were refused")
	test_answer(H, list("c", "a", "z"))
	var/list/got = F.got
	TEST_ASSERT(islist(got) && length(got) == 2 && got[1] == "a" && got[2] == "c", "the ticked choices answer in the list's order, unknown ones dropped")

/// A bitfield keeps what it may not edit.
/datum/unit_test/dq_eg2/prompt_bitfield
/datum/unit_test/dq_eg2/prompt_bitfield/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "flags")
	test_answer(H, "many")
	TEST_ASSERT_EQUAL(F.ran, 0, "a non-number was refused")
	test_answer(H, 15)
	TEST_ASSERT_EQUAL(F.got, 7, "the flags it may edit (3) took the answer, the rest (4) kept the default")

/// Text is cut to its length and a number is clamped and rounded: the schema of the value, applied to every answer.
/datum/unit_test/dq_eg2/prompt_text_and_number_are_normalised
/datum/unit_test/dq_eg2/prompt_text_and_number_are_normalised/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "words")
	test_answer(H, "abcdefgh")
	TEST_ASSERT_EQUAL(F.got, "abcde", "text is cut to its length")
	test_menu(H, F, "amount")
	test_answer(H, 99)
	TEST_ASSERT_EQUAL(F.got, 10, "a number above the range is clamped")
	test_menu(H, F, "amount")
	test_answer(H, 3.6)
	TEST_ASSERT_EQUAL(F.got, 4, "and rounded to its step")

/// A window answers through the same check as the driver, and closing it is a cancellation.
/datum/unit_test/dq_eg2/prompt_window_answers_and_closes
/datum/unit_test/dq_eg2/prompt_window_answers_and_closes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/eg2_asker/F = allocate(/obj/eg2_asker, run_loc_floor_bottom_left)
	test_menu(H, F, "pick")
	var/datum/prompt/choice/asked = SSrequests.open_for(H)
	var/datum/tgui_list_input/prompt/window = new(H, "Which?", "Pick", asked.choices, null, 0, GLOB.tgui_always_state)
	window.prompt = asked
	window.set_choice("green") // not one of them: the question stays open
	TEST_ASSERT(SSrequests.open_for(H) == asked && F.ran == 0, "a window answer outside the choices is refused")
	var/datum/tgui_list_input/prompt/again = new(H, "Which?", "Pick", asked.choices, null, 0, GLOB.tgui_always_state)
	again.prompt = asked
	again.set_choice("red")
	TEST_ASSERT_EQUAL(F.got, "red", "a window answer reaches the op")
	qdel(again)
	TEST_ASSERT_NULL(SSrequests.open_for(H), "and ends the question")
	qdel(window)
	F.got = null
	test_menu(H, F, "pick")
	var/datum/prompt/choice/second = SSrequests.open_for(H)
	var/datum/tgui_list_input/prompt/closing = new(H, "Which?", "Pick", second.choices, null, 0, GLOB.tgui_always_state)
	closing.prompt = second
	closing.tgui_close(H)
	TEST_ASSERT_NULL(F.got, "closing the window answered nothing")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "and ended the question cancelled")
	TEST_ASSERT_EQUAL(F.ran, 1, "so the op never ran again")

/// Proof site: a chaplain's first use of a bible asks for the skin in a radial choice, the answer becomes the religion's bible, and a later use invokes it.
/datum/unit_test/dq_eg2/bible_chaplain_chooses_a_skin
/datum/unit_test/dq_eg2/bible_chaplain_chooses_a_skin/run_gate()
	var/mob/living/carbon/human/H = person()
	H.mind_initialize()
	H.mind.assigned_role = JOB_CHAPLAIN
	own_set(H.mind, nameof(/datum/mind::my_religion), new /datum/religion("Testism", "Tester", "Bible", "bible", "bible", JOB_CHAPLAIN))
	var/obj/item/storage/bible/B = allocate(/obj/item/storage/bible, run_loc_floor_bottom_left)
	H.put_in_active_hand(B)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, B, null, null, "left=1"))
	test_time(1 SECONDS)
	var/datum/prompt/choice/asked = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(asked, "a chaplain's first use asks for a skin")
	TEST_ASSERT(asked.radial, "in a radial ring")
	TEST_ASSERT_EQUAL(length(asked.choices), length(GLOB.biblenames), "with every bible to choose from")
	test_answer(H, "Koran")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(B.icon_state, "koran", "the chosen skin is the bible's")
	TEST_ASSERT(H.mind.my_religion.configured, "and the religion is configured")
	B.icon_state = "bible"
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, B, null, null, "left=1"))
	test_time(1 SECONDS)
	TEST_ASSERT_NULL(SSrequests.open_for(H), "a later use asks nothing")
	TEST_ASSERT_EQUAL(B.icon_state, "koran", "it invokes the religion's bible instead")

/// Proof site: a polychromic wallet is recoloured from a colour prompt, only while it is carried.
/datum/unit_test/dq_eg2/wallet_recolor_asks_for_a_color
/datum/unit_test/dq_eg2/wallet_recolor_asks_for_a_color/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/storage/wallet/poly/W = allocate(/obj/item/storage/wallet/poly, run_loc_floor_bottom_left)
	test_menu(H, W, "recolor")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "a wallet on the floor is not recoloured")
	H.put_in_active_hand(W)
	test_menu(H, W, "recolor")
	var/datum/prompt/color/asked = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(asked, "a carried wallet asks for a colour")
	test_answer(H, "#00ff00")
	TEST_ASSERT_EQUAL(W.color, "#00ff00", "the answer is the wallet's colour")

// ---------------------------------------------------------------------------------------------------------------------
// Timed stall: a slow pouch takes what is put in after a wait
// ---------------------------------------------------------------------------------------------------------------------

/// Proof site: a pouch with an insertion delay holds the item in the hand until the wait ends, and walking away cancels it.
/datum/unit_test/dq_eg2/slow_pouch_takes_the_item_after_its_wait
/datum/unit_test/dq_eg2/slow_pouch_takes_the_item_after_its_wait/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/storage/pouch/P = allocate(/obj/item/storage/pouch, run_loc_floor_bottom_left)
	P.insert_delay = 2 SECONDS
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(pen)
	H.set_use_stance(I_HELP)
	test_click(H, P, pen)
	TEST_ASSERT(pen.loc != P, "the item is not in the pouch before the wait is over")
	test_time(5 SECONDS)
	TEST_ASSERT(pen.loc == P, "it is when the wait ends")
	var/obj/item/pen/second = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(second)
	test_click(H, P, second)
	test_time(1 SECONDS)
	H.forceMove(get_step(H, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(second.loc != P, "walking away cancelled the insertion")

// ---------------------------------------------------------------------------------------------------------------------
// held_verb()
// ---------------------------------------------------------------------------------------------------------------------

/// Proof site: a polychromic wallet has its recolour verb only while somebody carries it, and the verb runs the op.
/datum/unit_test/dq_eg2/held_verb_follows_the_carrier
/datum/unit_test/dq_eg2/held_verb_follows_the_carrier/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/storage/wallet/poly/W = allocate(/obj/item/storage/wallet/poly, run_loc_floor_bottom_left)
	var/verb_path = /obj/item/storage/wallet/poly/proc/change_color
	TEST_ASSERT(!(verb_path in W.verbs), "a wallet on the floor has no verb")
	H.put_in_active_hand(W)
	TEST_ASSERT(verb_path in W.verbs, "a carried one has it")
	H.drop_item()
	TEST_ASSERT(!(verb_path in W.verbs), "and loses it when dropped")
	var/obj/item/clothing/under/color/grey/suit = allocate(/obj/item/clothing/under/color/grey, run_loc_floor_bottom_left)
	TEST_ASSERT(H.equip_to_slot_if_possible(suit, SLOT_ID_UNIFORM, disable_warning = TRUE), "the uniform goes on")
	TEST_ASSERT(H.equip_to_slot_if_possible(W, SLOT_ID_POCKET_L, disable_warning = TRUE), "the wallet goes in a pocket")
	TEST_ASSERT(W in H.contents, "the wallet is in a pocket")
	TEST_ASSERT(verb_path in W.verbs, "a pocket counts as carried")
	TEST_ASSERT(slot_matches(SLOT_ANY_CARRIED, SLOT_ID_POCKET_L, H), "SLOT_ANY_CARRIED covers a pocket")
	TEST_ASSERT(!slot_matches(SLOT_ANY_HELD, SLOT_ID_POCKET_L, H), "SLOT_ANY_HELD does not")
	qdel(W)
