// Behaviour-preservation tests for group B of the items domain (lighters, cigarettes, tools, weapons, shields, grenades, defibs, bags...). They pin what
// a player observes through clicks, windows and the kernel clock, so the same file passes before and after a family moves to the final forms. State is
// read through plain vars; nothing here depends on message text or on an op key. The helpers (hci_click, hci_answer) are in dq_hc_items_behaviour.dm.

/// One step of an item's periodic work. The legacy periodic lane is not driven by the test clock, so the tests call the step the lane would (an adapter:
/// only its body changes when the family moves to every()).
/proc/hci2b_step(obj/item/I)
	if(istype(I, /obj/item/flame))
		var/obj/item/flame/F = I
		F.flame_step(null)
	else if(istype(I, /obj/item/clothing/mask/smokable/ecig))
		var/obj/item/clothing/mask/smokable/ecig/E = I
		E.ecig_step(null)
	else if(istype(I, /obj/item/clothing/mask/smokable))
		var/obj/item/clothing/mask/smokable/S = I
		S.smokable_step(null)

// ---------------------------------------------------------------------------------------------------------------------
// Matches, lighters, cigarettes, pipes, e-cigs
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/b_match_burns_down_and_out

/datum/unit_test/dq_hc_items/b_match_burns_down_and_out/run_gate()
	var/obj/item/flame/match/M = allocate(/obj/item/flame/match, tile(2, 2))
	TEST_ASSERT(!M.lit, "a match starts unlit")
	M.light(null)
	TEST_ASSERT(M.lit, "lighting it lights it")
	TEST_ASSERT(M.is_hot(), "a lit match is hot")
	hci2b_step(M)
	TEST_ASSERT(M.lit, "it still burns after a step")
	TEST_ASSERT(M.smoketime < 5, "it burns down while lit")
	for(var/i in 1 to 6)
		hci2b_step(M)
	TEST_ASSERT(!M.lit, "it burns out")
	TEST_ASSERT(M.burnt, "a burnt match is marked burnt")
	TEST_ASSERT_EQUAL(M.icon_state, "match_burnt", "and looks it")

/datum/unit_test/dq_hc_items/b_lighter_toggles_with_use_and_lights_a_cigarette

/datum/unit_test/dq_hc_items/b_lighter_toggles_with_use_and_lights_a_cigarette/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter, T)
	TEST_ASSERT(!L.lit, "a lighter starts off")
	hci_click(H, L, L)
	settle()
	TEST_ASSERT(L.lit, "using it in the hand lights it")
	TEST_ASSERT_EQUAL(L.icon_state, "lighteron", "it shows the lit state")
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	TEST_ASSERT(!C.lit, "a cigarette starts unlit")
	hci_click(H, C, L)
	settle()
	TEST_ASSERT(C.lit, "a lit lighter used on a cigarette lights it")
	var/before = C.smoketime
	hci2b_step(C)
	TEST_ASSERT(C.smoketime < before, "a lit cigarette burns down")
	hci_click(H, L, L)
	settle()
	TEST_ASSERT(!L.lit, "using the lighter again puts it out")
	TEST_ASSERT_EQUAL(L.icon_state, "lighter", "it shows the off state")
	var/mid = C.smoketime
	hci_click(H, C, C)
	settle()
	TEST_ASSERT(!C.lit, "using a lit cigarette in the hand puts it out")
	TEST_ASSERT_EQUAL(C.smoketime, mid, "an unlit cigarette keeps its fuel")

/datum/unit_test/dq_hc_items/b_cigarette_dropped_in_hurt_stance_goes_out_as_a_butt

/datum/unit_test/dq_hc_items/b_cigarette_dropped_in_hurt_stance_goes_out_as_a_butt/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	C.light("lit")
	TEST_ASSERT(C.lit, "lit")
	hci_click(H, C, C, I_HURT)
	settle()
	TEST_ASSERT(QDELETED(C), "treading on a lit cigarette replaces it")
	var/found = FALSE
	for(var/obj/item/trash/cigbutt/B in T)
		found = TRUE
		qdel(B)
	for(var/obj/item/trash/cigbutt/B in H)
		found = TRUE
		qdel(B)
	TEST_ASSERT(found, "a butt is left")

/datum/unit_test/dq_hc_items/b_zippo_uses_its_own_states_and_pipe_empties

/datum/unit_test/dq_hc_items/b_zippo_uses_its_own_states_and_pipe_empties/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/lighter/zippo/Z = allocate(/obj/item/flame/lighter/zippo, T)
	hci_click(H, Z, Z)
	settle()
	TEST_ASSERT(Z.lit, "a zippo lights in the hand")
	TEST_ASSERT_EQUAL(Z.item_state, "zippoon", "it shows the lit in-hand state")
	hci_click(H, Z, Z)
	settle()
	TEST_ASSERT(!Z.lit, "and goes out")
	TEST_ASSERT_EQUAL(Z.item_state, "zippo", "back to the plain in-hand state")
	var/obj/item/clothing/mask/smokable/pipe/P = allocate(/obj/item/clothing/mask/smokable/pipe, T)
	P.light("lit")
	TEST_ASSERT(P.lit, "a pipe lights")
	hci_click(H, P, P, I_HELP)
	settle()
	TEST_ASSERT(!P.lit, "using a lit pipe puts it out")
	P.light("lit")
	hci_click(H, P, P, I_HURT)
	settle()
	TEST_ASSERT(!P.lit, "emptying a lit pipe puts it out")
	for(var/obj/effect/decal/cleanable/ash/ash in T)
		qdel(ash)

/datum/unit_test/dq_hc_items/b_match_lights_a_pipe

/datum/unit_test/dq_hc_items/b_match_lights_a_pipe/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/match/M = allocate(/obj/item/flame/match, T)
	M.light(null)
	var/obj/item/clothing/mask/smokable/cigarette/cigar/C = allocate(/obj/item/clothing/mask/smokable/cigarette/cigar, T)
	hci_click(H, C, M)
	settle()
	TEST_ASSERT(C.lit, "a lit match lights a cigar")

/datum/unit_test/dq_hc_items/b_ecig_toggles_vapes_ejects_and_takes_a_cartridge

/datum/unit_test/dq_hc_items/b_ecig_toggles_vapes_ejects_and_takes_a_cartridge/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/clothing/mask/smokable/ecig/simple/E = allocate(/obj/item/clothing/mask/smokable/ecig/simple, T)
	var/obj/item/reagent_containers/ecig_cartridge/cart = E.ec_cartridge
	TEST_ASSERT(cart, "it starts with a cartridge")
	TEST_ASSERT(!E.active, "off")
	hci_click(H, E, E)
	settle()
	TEST_ASSERT(E.active, "using it switches it on")
	E.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(E.icon_state, E.icon_on, "the look follows")
	TEST_ASSERT(H.equip_to_slot_if_possible(E, SLOT_ID_MASK), "worn")
	var/before = cart.reagents.total_volume
	hci2b_step(E)
	TEST_ASSERT(cart.reagents.total_volume < before, "a worn running e-cig vapes its cartridge")
	H.drop_from_inventory(E)
	hci_click(H, E, E)
	settle()
	TEST_ASSERT(!E.active, "using it again switches it off")
	H.put_in_inactive_hand(E)
	hci_click(H, E, null)
	settle()
	TEST_ASSERT_NULL(E.ec_cartridge, "an empty hand on the held e-cig ejects the cartridge")
	TEST_ASSERT_EQUAL(cart.loc, H, "the cartridge is in the hand")
	H.drop_item()
	hci_click(H, E, cart)
	settle()
	TEST_ASSERT_EQUAL(E.ec_cartridge, cart, "a cartridge used on it is installed")

/datum/unit_test/dq_hc_items/b_candle_burns_wax_while_lit

/datum/unit_test/dq_hc_items/b_candle_burns_wax_while_lit/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/flame/candle/C = allocate(/obj/item/flame/candle, tile(2, 2))
	var/start = C.wax
	C.light(user = H)
	TEST_ASSERT(C.lit, "lit")
	hci2b_step(C)
	TEST_ASSERT(C.wax < start, "a lit candle burns wax")
	hci_click(H, C, C)
	settle()
	TEST_ASSERT(!C.lit, "using it snuffs it")
	var/everburn_wax = 99999
	var/obj/item/flame/candle/everburn/E = allocate(/obj/item/flame/candle/everburn, tile(3, 3))
	hci2b_step(E)
	TEST_ASSERT_EQUAL(E.wax, everburn_wax, "an everburning candle never loses wax")

/datum/unit_test/dq_hc_items/b_wrapped_chewable_unwraps_in_the_hand

/datum/unit_test/dq_hc_items/b_wrapped_chewable_unwraps_in_the_hand/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/clothing/mask/chewable/tobacco/W = allocate(/obj/item/clothing/mask/chewable/tobacco, tile(2, 2))
	W.wrapped = TRUE
	hci_click(H, W, W)
	settle()
	TEST_ASSERT(!W.wrapped, "using a wrapped chewable unwraps it")

/datum/unit_test/dq_hc_items/b_ashtray_takes_butts_and_puts_out_cigarettes

/datum/unit_test/dq_hc_items/b_ashtray_takes_butts_and_puts_out_cigarettes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/material/ashtray/plastic/A = allocate(/obj/item/material/ashtray/plastic, T)
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	C.light("lit")
	hci_click(H, A, C)
	settle()
	TEST_ASSERT(QDELETED(C), "a lit cigarette put in an ashtray is put out and replaced")
	var/found = FALSE
	for(var/obj/item/trash/cigbutt/B in A)
		found = TRUE
	TEST_ASSERT(found, "its butt is in the ashtray")
	var/obj/item/trash/cigbutt/butt = allocate(/obj/item/trash/cigbutt, T)
	hci_click(H, A, butt)
	settle()
	TEST_ASSERT_EQUAL(butt.loc, A, "a butt is put in")

/datum/unit_test/dq_hc_items/b_burning_steps_run_with_the_clock

/datum/unit_test/dq_hc_items/b_burning_steps_run_with_the_clock/run_gate()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/match/M = allocate(/obj/item/flame/match, T)
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(M.smoketime, 5, "an unlit match does not burn")
	M.light(null)
	test_time(4 SECONDS)
	TEST_ASSERT(M.smoketime < 5, "a lit match burns with the clock")
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(C.smoketime, 300, "an unlit cigarette does not burn")
	C.light("lit")
	var/start = C.smoketime
	test_time(6 SECONDS)
	TEST_ASSERT(C.smoketime < start, "a lit cigarette burns with the clock")
	C.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(C.icon_state, "cig_on", "it looks lit")
	C.quench()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(C.icon_state, "cig_burnt", "a put out cigarette looks partly smoked")
	TEST_ASSERT_EQUAL(C.item_state, "cig_burnt", "and is held that way")
	for(var/obj/effect/decal/cleanable/ash/ash in T)
		qdel(ash)

/datum/unit_test/dq_hc_items/b_ecig_states_follow_the_cartridge

/datum/unit_test/dq_hc_items/b_ecig_states_follow_the_cartridge/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/clothing/mask/smokable/ecig/deluxe/E = allocate(/obj/item/clothing/mask/smokable/ecig/deluxe, tile(2, 2))
	settle()
	TEST_ASSERT_EQUAL(E.icon_state, E.icon_off, "a loaded e-cig shows its off state")
	TEST_ASSERT_EQUAL(E.item_state, E.icon_off, "and is held that way")
	H.put_in_inactive_hand(E)
	hci_click(H, E, null)
	settle()
	TEST_ASSERT_EQUAL(E.icon_state, E.icon_empty, "without a cartridge it shows the empty state")
	TEST_ASSERT_EQUAL(E.item_state, E.icon_empty, "and is held that way")

// ---------------------------------------------------------------------------------------------------------------------
// Welding tools, flashlights, power sinks, detectors
// ---------------------------------------------------------------------------------------------------------------------

/// One step of the periodic work of a tool or light (an adapter: the legacy lane is not driven by the test clock).
/proc/hci2b_tool_step(obj/item/I)
	I.periodic_step()

/datum/unit_test/dq_hc_items/b_welder_toggles_burns_fuel_and_is_secured_with_a_screwdriver

/datum/unit_test/dq_hc_items/b_welder_toggles_burns_fuel_and_is_secured_with_a_screwdriver/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/weldingtool/W = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT(!W.welding, "starts off")
	hci_click(H, W, W)
	settle()
	TEST_ASSERT(W.welding, "using it in the hand switches it on")
	TEST_ASSERT(W.isOn(), "it is on")
	TEST_ASSERT_EQUAL(W.force, 15, "a lit welder hits hard")
	W.update_icon()
	settle()
	TEST_ASSERT_EQUAL(W.item_state, "welder1", "and is held lit")
	var/fuel = W.get_fuel()
	for(var/i in 1 to 13) // the welder burns a unit of fuel every 13 steps
		hci2b_tool_step(W)
	TEST_ASSERT(W.get_fuel() < fuel, "a lit welder burns fuel")
	var/obj/item/tool/screwdriver/driver = allocate(/obj/item/tool/screwdriver, T)
	hci_click(H, W, driver)
	settle()
	TEST_ASSERT(W.status, "a lit welder is not unsecured")
	hci_click(H, W, W)
	settle()
	TEST_ASSERT(!W.welding, "using it again switches it off")
	TEST_ASSERT_EQUAL(W.force, 3, "and it hits soft again")
	hci_click(H, W, driver)
	settle()
	TEST_ASSERT(!W.status, "a screwdriver unsecures a welder that is off")
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, T)
	hci_click(H, W, R)
	settle()
	var/found = FALSE
	for(var/obj/item/flamethrower/F in get_turf(H))
		found = TRUE
		qdel(F)
	for(var/obj/item/flamethrower/F in H)
		found = TRUE
		qdel(F)
	TEST_ASSERT(found, "rods on an unsecured welder make a flamethrower")

/datum/unit_test/dq_hc_items/b_self_refuelling_welders_regain_fuel_without_being_lit

/datum/unit_test/dq_hc_items/b_self_refuelling_welders_regain_fuel_without_being_lit/run_gate()
	var/obj/item/weldingtool/alien/A = allocate(/obj/item/weldingtool/alien, tile(2, 2))
	A.reagents.remove_reagent(REAGENT_ID_FUEL, 10)
	var/before = A.get_fuel()
	hci2b_tool_step(A)
	TEST_ASSERT(A.get_fuel() > before, "an alien welder makes fuel while off")
	var/obj/item/weldingtool/experimental/E = allocate(/obj/item/weldingtool/experimental, tile(3, 3))
	E.reagents.remove_reagent(REAGENT_ID_FUEL, 10)
	before = E.get_fuel()
	hci2b_tool_step(E)
	TEST_ASSERT(E.get_fuel() > before, "an experimental welder makes fuel while off")

/datum/unit_test/dq_hc_items/b_electric_welder_takes_and_gives_its_cell

/datum/unit_test/dq_hc_items/b_electric_welder_takes_and_gives_its_cell/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/weldingtool/electric/W = allocate(/obj/item/weldingtool/electric, T)
	var/obj/item/cell/cell = W.power_supply
	TEST_ASSERT(cell, "it starts with a cell")
	H.put_in_inactive_hand(W)
	hci_click(H, W, null)
	settle()
	TEST_ASSERT_NULL(W.power_supply, "an empty hand on the held welder takes the cell out")
	H.drop_item()
	hci_click(H, W, cell)
	settle()
	TEST_ASSERT_EQUAL(W.power_supply, cell, "a device cell used on it goes in")

/datum/unit_test/dq_hc_items/b_weld_pack_hands_out_and_takes_back_its_nozzle

/datum/unit_test/dq_hc_items/b_weld_pack_hands_out_and_takes_back_its_nozzle/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldpack/P = allocate(/obj/item/weldpack, tile(2, 2))
	TEST_ASSERT(H.equip_to_slot_if_possible(P, SLOT_ID_BACK), "the pack is worn")
	var/obj/item/weldingtool/tubefed/N = P.nozzle
	TEST_ASSERT(N, "the pack has a nozzle")
	hci_click(H, P, null)
	settle()
	TEST_ASSERT_EQUAL(N.loc, H, "an empty hand on the worn pack hands out the nozzle")
	TEST_ASSERT(!P.nozzle_attached, "which is no longer attached")
	hci_click(H, P, N)
	settle()
	TEST_ASSERT_EQUAL(N.loc, P, "the nozzle used on the pack goes back")
	TEST_ASSERT(P.nozzle_attached, "attached again")
	var/obj/item/weldingtool/W = allocate(/obj/item/weldingtool, tile(3, 3))
	W.reagents.remove_reagent(REAGENT_ID_FUEL, 10)
	hci_click(H, P, W)
	settle()
	TEST_ASSERT_EQUAL(W.get_fuel(), W.max_fuel, "a welder used on the pack is refilled")

/datum/unit_test/dq_hc_items/b_flashlight_switches_with_a_cell_and_runs_it_down

/datum/unit_test/dq_hc_items/b_flashlight_switches_with_a_cell_and_runs_it_down/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, T)
	TEST_ASSERT(F.cell, "it has a cell")
	TEST_ASSERT(!F.on, "off")
	hci_click(H, F, F)
	settle()
	TEST_ASSERT(F.on, "using it switches it on")
	TEST_ASSERT_EQUAL(F.icon_state, "flashlight-on", "it looks on")
	var/charge = F.cell.charge
	hci2b_tool_step(F)
	TEST_ASSERT(F.cell.charge < charge, "a lit flashlight uses its cell")
	hci_click(H, F, F)
	settle()
	TEST_ASSERT(!F.on, "using it again switches it off")
	H.put_in_inactive_hand(F)
	var/obj/item/cell/cell = F.cell
	hci_click(H, F, null)
	settle()
	TEST_ASSERT_NULL(F.cell, "an empty hand on the held flashlight takes the cell out")
	H.drop_item()
	hci_click(H, F, cell)
	settle()
	TEST_ASSERT_EQUAL(F.cell, cell, "a device cell goes back in")
	var/obj/item/flashlight/F2 = allocate(/obj/item/flashlight, tile(3, 3))
	F2.cell.charge = 0
	hci_click(H, F2, F2)
	settle()
	TEST_ASSERT(!F2.on, "a flashlight with a dead cell does not light")

/datum/unit_test/dq_hc_items/b_penlight_flare_and_glowstick_light_without_a_cell

/datum/unit_test/dq_hc_items/b_penlight_flare_and_glowstick_light_without_a_cell/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/flashlight/pen/P = allocate(/obj/item/flashlight/pen, tile(2, 2))
	hci_click(H, P, P)
	settle()
	TEST_ASSERT(P.on, "a penlight switches on without a cell")
	var/obj/item/flashlight/flare/F = allocate(/obj/item/flashlight/flare, tile(3, 3))
	hci_click(H, F, F)
	settle()
	TEST_ASSERT(F.on, "a flare lights")
	var/fuel = F.fuel
	hci2b_tool_step(F)
	TEST_ASSERT(F.fuel < fuel, "a lit flare burns")
	hci_click(H, F, F)
	settle()
	TEST_ASSERT(F.on, "a lit flare cannot be put out")
	var/obj/item/flashlight/glowstick/G = allocate(/obj/item/flashlight/glowstick, tile(1, 1))
	hci_click(H, G, G)
	settle()
	TEST_ASSERT(G.on, "a glowstick lights")
	fuel = G.fuel
	hci2b_tool_step(G)
	TEST_ASSERT(G.fuel < fuel, "a lit glowstick burns")

/datum/unit_test/dq_hc_items/b_power_sink_is_worked_by_hand_and_dissipates

/datum/unit_test/dq_hc_items/b_power_sink_is_worked_by_hand_and_dissipates/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/powersink/S = allocate(/obj/item/powersink, tile(2, 2))
	hci_click(H, S, null)
	settle()
	TEST_ASSERT_EQUAL(S.mode, 0, "a loose sink ignores a hand")
	S.set_mode(1)
	hci_click(H, S, null)
	settle()
	TEST_ASSERT_EQUAL(S.mode, 2, "a clamped sink starts when touched")
	S.power_drained = 50000
	hci2b_tool_step(S)
	TEST_ASSERT_EQUAL(S.power_drained, 50000 - S.dissipation_rate, "an operating sink dissipates what it drained")
	hci_click(H, S, null)
	settle()
	TEST_ASSERT_EQUAL(S.mode, 1, "touched again it stops")

/datum/unit_test/dq_hc_items/b_ai_detector_senses_while_carried

/datum/unit_test/dq_hc_items/b_ai_detector_senses_while_carried/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/multitool/ai_detector/D = allocate(/obj/item/multitool/ai_detector, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(D), "carried")
	hci2b_tool_step(D)
	TEST_ASSERT_EQUAL(D.detect_state, "_no_camera", "off the camera network it says so")

/datum/unit_test/dq_hc_items/b_suit_cooler_t_scanner_and_nif_repairer_looks

/datum/unit_test/dq_hc_items/b_suit_cooler_t_scanner_and_nif_repairer_looks/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/suit_cooling_unit/U = allocate(/obj/item/suit_cooling_unit, T)
	U.update_icon()
	settle()
	TEST_ASSERT_EQUAL(U.icon_state, "suitcooler0", "a closed cooler shows its plain state")
	U.cover_open = TRUE
	U.update_icon()
	settle()
	TEST_ASSERT_EQUAL(U.icon_state, "suitcooler1", "an open cooler with a cell shows the cell")
	var/obj/item/t_scanner/S = allocate(/obj/item/t_scanner, tile(3, 3))
	hci_click(H, S, S)
	settle()
	TEST_ASSERT_EQUAL(S.icon_state, "t-ray1", "a switched on T-ray scanner shows it")
	var/obj/item/nifrepairer/N = allocate(/obj/item/nifrepairer, tile(1, 1))
	N.update_icon()
	settle()
	TEST_ASSERT_EQUAL(N.icon_state, initial(N.icon_state), "an empty repairer shows its plain state")
	N.supply.add_reagent(REAGENT_ID_NIFREPAIRNANITES, 10)
	N.update_icon()
	settle()
	TEST_ASSERT_EQUAL(N.icon_state, "[initial(N.icon_state)]2", "a loaded repairer shows its filled state")
