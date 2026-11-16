// A click on yourself, or on something next to you, with the common items: every one of them either changes something or tells the actor why not.
// The clicks go through the input inbox exactly as a player's do (hci_click(): a real /datum/input_event/click through input_submit()).

/// What the actor was told by one click: the click is sent, time runs, and the chat text kept for the actor comes back.
/proc/sam_click(mob/living/carbon/human/H, atom/target, obj/item/held, stance = I_HELP, modifiers = "left=1")
	test_chat_clear()
	hci_click(H, target, held, stance, modifiers)
	test_time(5 SECONDS)
	return test_chat_of(H)

/datum/unit_test/dq_self_actions
	abstract_type = /datum/unit_test/dq_self_actions

/datum/unit_test/dq_self_actions/Run()
	set_global(nameof(GLOB.hop_cache_hits), GLOB.hop_cache_hits)
	test_driver_begin()
	test_rng(11)
	test_prompts_reset()
	run_gate()
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	test_driver_end()

/datum/unit_test/dq_self_actions/proc/run_gate()
	return

/datum/unit_test/dq_self_actions/proc/tile(dx, dy)
	RETURN_TYPE(/turf)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/datum/unit_test/dq_self_actions/proc/person(dx = 2, dy = 2)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, tile(dx, dy))
	H.enable_godmode()
	return H

// ---------------------------------------------------------------------------------------------------------------------
// Guns on yourself
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_self_actions/sizegun_on_self_help

/datum/unit_test/dq_self_actions/sizegun_on_self_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gun/energy/sizegun/G = allocate(/obj/item/gun/energy/sizegun, tile(3, 3))
	var/charge = G.power_supply.charge
	var/list/told = sam_click(H, H, G, I_HELP)
	TEST_ASSERT(G.power_supply.charge < charge, "a size gun clicked on its holder out of combat mode fires: [json_encode(told)]")

/datum/unit_test/dq_self_actions/sizegun_on_self_hurt

/datum/unit_test/dq_self_actions/sizegun_on_self_hurt/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gun/energy/sizegun/G = allocate(/obj/item/gun/energy/sizegun, tile(3, 3))
	var/charge = G.power_supply.charge
	var/list/told = sam_click(H, H, G, I_HURT)
	TEST_ASSERT(G.power_supply.charge < charge, "a size gun clicked on its holder in combat mode fires: [json_encode(told)]")

/datum/unit_test/dq_self_actions/sizegun_on_neighbour_help

/datum/unit_test/dq_self_actions/sizegun_on_neighbour_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(3, 2)
	var/obj/item/gun/energy/sizegun/G = allocate(/obj/item/gun/energy/sizegun, tile(3, 3))
	var/charge = G.power_supply.charge
	var/list/told = sam_click(H, other, G, I_HELP)
	TEST_ASSERT(G.power_supply.charge < charge, "a size gun clicked on a neighbour fires in any stance: [json_encode(told)]")

/datum/unit_test/dq_self_actions/medigun_on_self_help

/datum/unit_test/dq_self_actions/medigun_on_self_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gun/energy/medigun/G = allocate(/obj/item/gun/energy/medigun, tile(3, 3))
	var/charge = G.power_supply.charge
	var/list/told = sam_click(H, H, G, I_HELP)
	TEST_ASSERT(G.power_supply.charge < charge, "a medigun clicked on its holder fires in any stance: [json_encode(told)]")

/datum/unit_test/dq_self_actions/slow_sizegun_on_self

/datum/unit_test/dq_self_actions/slow_sizegun_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/slow_sizegun/G = allocate(/obj/item/slow_sizegun, tile(3, 3))
	var/list/told = sam_click(H, H, G, I_HELP)
	TEST_ASSERT(G.busy || length(told), "a gradual size gun clicked on its holder starts or says why not")
	if(G.busy)
		G.sizegun_finish()

/datum/unit_test/dq_self_actions/laser_on_self_help

/datum/unit_test/dq_self_actions/laser_on_self_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/gun/energy/laser/G = allocate(/obj/item/gun/energy/laser, tile(3, 3))
	var/charge = G.power_supply.charge
	var/list/told = sam_click(H, H, G, I_HELP)
	TEST_ASSERT(length(told), "a laser clicked on its holder out of combat mode says why it does not fire")
	TEST_ASSERT_EQUAL(G.power_supply.charge, charge, "a lethal gun is not fired at its holder out of combat mode")

/datum/unit_test/dq_self_actions/laser_on_adjacent_mob_help

/datum/unit_test/dq_self_actions/laser_on_adjacent_mob_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(3, 2)
	var/obj/item/gun/energy/laser/G = allocate(/obj/item/gun/energy/laser, tile(3, 3))
	var/charge = G.power_supply.charge
	var/list/told = sam_click(H, other, G, I_HELP)
	for(var/obj/effect/decal/cleanable/mess in other.loc)
		qdel(mess)
	TEST_ASSERT(G.power_supply.charge < charge || length(told), "a laser clicked on a neighbour out of combat mode fires, hits or says why not")

// ---------------------------------------------------------------------------------------------------------------------
// Medicine on yourself
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_self_actions/syringe_on_self

/datum/unit_test/dq_self_actions/syringe_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe/inaprovaline, tile(3, 3))
	S.set_mode(NEEDLE_INJECT)
	var/volume = S.reagents.total_volume
	var/list/told = sam_click(H, H, S, I_HELP)
	TEST_ASSERT(S.reagents.total_volume != volume || length(told), "a filled syringe clicked on its holder injects or says why not")

/datum/unit_test/dq_self_actions/autoinjector_on_self

/datum/unit_test/dq_self_actions/autoinjector_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/reagent_containers/hypospray/autoinjector/A = allocate(/obj/item/reagent_containers/hypospray/autoinjector, tile(3, 3))
	var/volume = A.reagents.total_volume
	var/list/told = sam_click(H, H, A, I_HELP)
	TEST_ASSERT(A.reagents.total_volume != volume || length(told), "an autoinjector clicked on its holder injects or says why not")

/datum/unit_test/dq_self_actions/hypospray_on_self

/datum/unit_test/dq_self_actions/hypospray_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/reagent_containers/hypospray/S = allocate(/obj/item/reagent_containers/hypospray, tile(3, 3))
	var/volume = S.reagents?.total_volume
	var/list/told = sam_click(H, H, S, I_HELP)
	TEST_ASSERT(S.reagents?.total_volume != volume || length(told), "a hypospray clicked on its holder injects or says why not")

/datum/unit_test/dq_self_actions/pill_on_self

/datum/unit_test/dq_self_actions/pill_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/reagent_containers/pill/P = allocate(/obj/item/reagent_containers/pill/paracetamol, tile(3, 3))
	var/list/told = sam_click(H, H, P, I_HELP)
	TEST_ASSERT(QDELETED(P) || length(told), "a pill clicked on its holder is swallowed or says why not")

/datum/unit_test/dq_self_actions/glass_on_self

/datum/unit_test/dq_self_actions/glass_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/reagent_containers/food/drinks/glass2/G = allocate(/obj/item/reagent_containers/food/drinks/glass2, tile(3, 3))
	G.reagents.add_reagent(REAGENT_ID_WATER, 10)
	var/volume = G.reagents.total_volume
	var/list/told = sam_click(H, H, G, I_HELP)
	TEST_ASSERT(G.reagents.total_volume != volume || length(told), "a glass of water clicked on its holder is drunk or says why not")

/datum/unit_test/dq_self_actions/bandage_on_self

/datum/unit_test/dq_self_actions/bandage_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/medical/bruise_pack/B = allocate(/obj/item/stack/medical/bruise_pack, tile(3, 3))
	var/amount = B.amount
	var/list/told = sam_click(H, H, B, I_HELP)
	TEST_ASSERT(B.amount != amount || length(told), "a bandage clicked on its holder is used or says why not")

/datum/unit_test/dq_self_actions/ointment_on_self

/datum/unit_test/dq_self_actions/ointment_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/medical/ointment/B = allocate(/obj/item/stack/medical/ointment, tile(3, 3))
	var/amount = B.amount
	var/list/told = sam_click(H, H, B, I_HELP)
	TEST_ASSERT(B.amount != amount || length(told), "an ointment clicked on its holder is used or says why not")

/datum/unit_test/dq_self_actions/health_analyzer_on_self

/datum/unit_test/dq_self_actions/health_analyzer_on_self/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/healthanalyzer/A = allocate(/obj/item/healthanalyzer, tile(3, 3))
	var/list/told = sam_click(H, H, A, I_HELP)
	TEST_ASSERT(length(told), "a health analyzer clicked on its holder reports something")

/datum/unit_test/dq_self_actions/health_analyzer_on_adjacent_mob

/datum/unit_test/dq_self_actions/health_analyzer_on_adjacent_mob/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(3, 2)
	var/obj/item/healthanalyzer/A = allocate(/obj/item/healthanalyzer, tile(3, 3))
	var/list/told = sam_click(H, other, A, I_HELP)
	TEST_ASSERT(length(told), "a health analyzer clicked on a neighbour reports something")

/datum/unit_test/dq_self_actions/bandage_on_adjacent_mob

/datum/unit_test/dq_self_actions/bandage_on_adjacent_mob/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(3, 2)
	var/obj/item/stack/medical/bruise_pack/B = allocate(/obj/item/stack/medical/bruise_pack, tile(3, 3))
	var/amount = B.amount
	var/list/told = sam_click(H, other, B, I_HELP)
	TEST_ASSERT(B.amount != amount || length(told), "a bandage clicked on a neighbour is used or says why not")

// ---------------------------------------------------------------------------------------------------------------------
// Items on a neighbour or an object, empty hands
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_self_actions/crowbar_on_adjacent_mob_hurt

/datum/unit_test/dq_self_actions/crowbar_on_adjacent_mob_hurt/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(3, 2)
	other.disable_godmode()
	var/obj/item/C = allocate(/obj/item/tool/crowbar, tile(3, 3))
	var/load = 0
	for(var/category in 1 to INJURY_CATEGORY_COUNT)
		load += other.injury_load(category)
	var/list/told = sam_click(H, other, C, I_HURT)
	var/after = 0
	for(var/category in 1 to INJURY_CATEGORY_COUNT)
		after += other.injury_load(category)
	TEST_ASSERT(after > load || length(told), "a crowbar swung at a neighbour in combat mode hurts them or says why not")

/datum/unit_test/dq_self_actions/item_on_table

/datum/unit_test/dq_self_actions/item_on_table/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/table/standard/T = allocate(/obj/structure/table/standard, tile(3, 2))
	var/obj/item/pen/P = allocate(/obj/item/pen, tile(3, 3))
	var/list/told = sam_click(H, T, P, I_HELP)
	TEST_ASSERT(P.loc == T.loc || length(told), "an item clicked on an adjacent table is put on it or says why not")

/datum/unit_test/dq_self_actions/empty_hand_on_self_help

/datum/unit_test/dq_self_actions/empty_hand_on_self_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/list/told = sam_click(H, H, null, I_HELP)
	TEST_ASSERT(length(told), "an empty hand clicked on yourself out of combat mode checks yourself and says so")

/datum/unit_test/dq_self_actions/empty_hand_on_adjacent_mob_help

/datum/unit_test/dq_self_actions/empty_hand_on_adjacent_mob_help/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(3, 2)
	var/list/told = sam_click(H, other, null, I_HELP)
	TEST_ASSERT(length(told), "an empty hand clicked on a neighbour out of combat mode helps them up or says so")
