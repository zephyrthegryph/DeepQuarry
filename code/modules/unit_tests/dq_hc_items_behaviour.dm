// Behaviour-preservation tests for the hand-converted item families (code/game/objects/items). They pin what a player observes through clicks and
// the kernel clock, so the same file passes before and after a family moves to the final forms. State is read through plain vars; nothing here
// depends on message text or on an op key.

/// A click as a player makes it: `held` in the active hand, the stance set, the click sent through the input inbox.
/proc/hci_click(mob/living/carbon/human/H, atom/target, obj/item/held, stance = I_HELP, modifiers = "left=1")
	if(held && H.get_active_hand() != held)
		if(H.get_active_hand())
			H.drop_item()
		H.put_in_active_hand(held)
	else if(!held && H.get_active_hand())
		H.drop_item()
	H.set_use_stance(stance)
	H.next_click = 0
	var/datum/input_event/click/E = new(H, target, null, null, modifiers)
	input_submit(E)
	H.set_use_stance(I_HELP)
	return E.result

/datum/unit_test/dq_hc_items
	abstract_type = /datum/unit_test/dq_hc_items

/datum/unit_test/dq_hc_items/Run()
	test_driver_begin()
	test_rng(11)
	om_scheduler().test_prompts = list()
	run_gate()
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	test_driver_end()

/datum/unit_test/dq_hc_items/proc/run_gate()
	return

/datum/unit_test/dq_hc_items/proc/tile(dx, dy)
	RETURN_TYPE(/turf)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/datum/unit_test/dq_hc_items/proc/settle()
	test_time(10 SECONDS)

/datum/unit_test/dq_hc_items/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || tile(2, 2))
	H.enable_godmode()
	return H

// ---------------------------------------------------------------------------------------------------------------------
// Geiger counter
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/geiger_use_toggles_scanning
	/// The held counter used in hand switches on and off; the look follows.

/datum/unit_test/dq_hc_items/geiger_use_toggles_scanning/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/geiger/G = allocate(/obj/item/geiger, tile(2, 2))
	TEST_ASSERT(!G.scanning, "starts off")
	hci_click(H, G, G)
	settle()
	TEST_ASSERT(G.scanning, "in-hand use switches it on")
	G.update_icon()
	TEST_ASSERT_EQUAL(G.icon_state, "geiger_on_1", "on shows the level 1 state")
	hci_click(H, G, G)
	settle()
	TEST_ASSERT(!G.scanning, "in-hand use switches it off")
	G.update_icon()
	TEST_ASSERT_EQUAL(G.icon_state, "geiger_off", "off shows the off state")

/datum/unit_test/dq_hc_items/geiger_alt_resets_only_while_scanning

/datum/unit_test/dq_hc_items/geiger_alt_resets_only_while_scanning/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/geiger/G = allocate(/obj/item/geiger, tile(2, 2))
	G.last_perceived_radiation_danger = PERCEIVED_RADIATION_DANGER_HIGH
	hci_click(H, G, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT_EQUAL(G.last_perceived_radiation_danger, PERCEIVED_RADIATION_DANGER_HIGH, "an alt-click on a counter that is off does nothing")
	G.scanning = TRUE
	hci_click(H, G, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT_NULL(G.last_perceived_radiation_danger, "an alt-click on a running counter clears the danger")

/datum/unit_test/dq_hc_items/geiger_level_follows_danger

/datum/unit_test/dq_hc_items/geiger_level_follows_danger/run_gate()
	var/obj/item/geiger/G = allocate(/obj/item/geiger, tile(2, 2))
	G.scanning = TRUE
	G.last_perceived_radiation_danger = PERCEIVED_RADIATION_DANGER_EXTREME
	G.update_icon()
	settle()
	TEST_ASSERT_EQUAL(G.icon_state, "geiger_on_5", "extreme danger shows level 5")
	var/obj/item/geiger/wall/W = allocate(/obj/item/geiger/wall, tile(3, 3))
	W.last_perceived_radiation_danger = PERCEIVED_RADIATION_DANGER_LOW
	W.update_icon()
	settle()
	TEST_ASSERT_EQUAL(W.icon_state, "geiger_level_2", "the wall counter has its own states")

/datum/unit_test/dq_hc_items/geiger_wall_hand_toggles

/datum/unit_test/dq_hc_items/geiger_wall_hand_toggles/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/geiger/wall/W = allocate(/obj/item/geiger/wall, tile(3, 2))
	TEST_ASSERT(W.scanning, "a wall counter starts on")
	hci_click(H, W, null)
	settle()
	TEST_ASSERT(!W.scanning, "an empty hand on the wall counter switches it off")

/// Answers the question `actor` was asked with `value` (`cancel` closes it). The engine's requests answer first; a question asked the legacy way
/// is answered through the prompt the test scheduler collected.
/proc/hci_answer(mob/actor, value, cancel = FALSE)
	var/datum/op_result/result = test_answer(actor, value, cancel ? REQ_CANCELLED : REQ_ANSWERED)
	if(!isnull(result))
		return result
	var/list/prompts = om_scheduler().test_prompts
	for(var/i in length(prompts) to 1 step -1)
		var/datum/om/prompt/P = prompts[i]
		if(!P.answered && P.peek("answerer") == actor)
			var/answer = value
			if(istype(P, /datum/om/prompt/confirm))
				var/datum/om/prompt/confirm/C = P
				answer = value ? C.yes_text : C.no_text
			return om_prompt_answer(P, cancel ? null : answer, cancel)
	return null

// ---------------------------------------------------------------------------------------------------------------------
// Gun boxes
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/gunbox_kit_is_chosen_and_box_used_up

/datum/unit_test/dq_hc_items/gunbox_kit_is_chosen_and_box_used_up/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/gunbox/B = allocate(/obj/item/gunbox, T)
	B.w_class = ITEMSIZE_SMALL
	hci_click(H, B, B)
	settle()
	hci_answer(H, "MarsTech P92X (9mm)")
	settle()
	TEST_ASSERT(QDELETED(B), "the box is used up")
	var/found = FALSE
	for(var/obj/item/gun/projectile/p92x/rubber/G in T)
		found = TRUE
	TEST_ASSERT(found, "the chosen gun is delivered")
	for(var/obj/item/I in T)
		qdel(I)

/datum/unit_test/dq_hc_items/gunbox_cancel_keeps_box

/datum/unit_test/dq_hc_items/gunbox_cancel_keeps_box/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gunbox/B = allocate(/obj/item/gunbox, tile(2, 2))
	B.w_class = ITEMSIZE_SMALL
	hci_click(H, B, B)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT(!QDELETED(B), "a cancelled question keeps the box")

/datum/unit_test/dq_hc_items/gunbox_variant_offers_its_own_kits

/datum/unit_test/dq_hc_items/gunbox_variant_offers_its_own_kits/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/gunbox/stun/B = allocate(/obj/item/gunbox/stun, T)
	B.w_class = ITEMSIZE_SMALL
	hci_click(H, B, B)
	settle()
	hci_answer(H, "Taser")
	settle()
	TEST_ASSERT(QDELETED(B), "the stun box is used up")
	var/found = FALSE
	for(var/obj/item/gun/energy/taser/G in T)
		found = TRUE
	TEST_ASSERT(found, "the stun box delivers a taser")
	for(var/obj/item/I in T)
		qdel(I)

// ---------------------------------------------------------------------------------------------------------------------
// Latex balloon
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/latexballoon_bursts_on_blast_shot_and_point

/datum/unit_test/dq_hc_items/latexballoon_bursts_on_blast_shot_and_point/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 3)
	var/obj/item/tank/oxygen/tank = allocate(/obj/item/tank/oxygen, T)
	var/obj/item/latexballon/B = allocate(/obj/item/latexballon, T)
	B.blow(tank)
	TEST_ASSERT_EQUAL(B.icon_state, "latexballon_blow", "a blown balloon")
	B.ex_act(3)
	TEST_ASSERT_EQUAL(B.icon_state, "latexballon_bursted", "a blast bursts it")
	var/obj/item/latexballon/B2 = allocate(/obj/item/latexballon, T)
	B2.blow(tank)
	var/obj/item/projectile/P = allocate(/obj/item/projectile)
	P.damage = 5
	P.nodamage = FALSE
	B2.bullet_act(P)
	TEST_ASSERT_EQUAL(B2.icon_state, "latexballon_bursted", "a round bursts it")
	TEST_ASSERT(!QDELETED(B2), "a round is blocked from damaging it further")
	var/obj/item/latexballon/B3 = allocate(/obj/item/latexballon, tile(2, 2))
	B3.blow(tank)
	var/obj/item/pen/P3 = allocate(/obj/item/pen, H.loc)
	hci_click(H, B3, P3)
	settle()
	TEST_ASSERT_EQUAL(B3.icon_state, "latexballon_bursted", "a pen bursts it")
	var/obj/item/latexballon/B4 = allocate(/obj/item/latexballon, tile(2, 2))
	B4.blow(tank)
	var/obj/item/pen/P4 = allocate(/obj/item/paper, H.loc)
	hci_click(H, B4, P4)
	settle()
	TEST_ASSERT_EQUAL(B4.icon_state, "latexballon_blow", "a paper does not burst it")

// ---------------------------------------------------------------------------------------------------------------------
// Petrifier and shooting target
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/petrifier_unlinked_does_nothing

/datum/unit_test/dq_hc_items/petrifier_unlinked_does_nothing/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/petrifier/P = allocate(/obj/item/petrifier, tile(2, 2))
	hci_click(H, P, P)
	settle()
	TEST_ASSERT(!QDELETED(P), "an unlinked device is not used up")

/datum/unit_test/dq_hc_items/target_empty_hand_picks_up_free_target

/datum/unit_test/dq_hc_items/target_empty_hand_picks_up_free_target/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/target/X = allocate(/obj/item/target, tile(2, 2))
	hci_click(H, X, null)
	settle()
	TEST_ASSERT_EQUAL(H.get_active_hand(), X, "a target that is on no stake is picked up")

/datum/unit_test/dq_hc_items/target_pinned_is_taken_off_stake

/datum/unit_test/dq_hc_items/target_pinned_is_taken_off_stake/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/target/X = allocate(/obj/item/target, tile(2, 3))
	var/obj/structure/target_stake/S = allocate(/obj/structure/target_stake, tile(2, 3))
	tile(2, 3).luminosity = 3 // view() sees only lit turfs
	rel_set(S, nameof(S.pinned_target), X)
	S.set_density(FALSE)
	hci_click(H, X, null)
	settle()
	TEST_ASSERT(S.density, "the stake can be pushed again")
	TEST_ASSERT(!X.density, "the target is not an obstacle")
	TEST_ASSERT_EQUAL(H.get_active_hand(), X, "the target is in the hand that took it")
