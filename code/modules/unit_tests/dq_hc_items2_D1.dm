// Behaviour-preservation tests for the D1 item group (blueprints, crayons, the extrapolator, toys and bells). They pin what a player observes through
// clicks, questions and the kernel clock, so the same file passes before and after the group moves to the final forms. State is read through plain
// vars; nothing here depends on message text or on an op key. The helpers (hci_click, hci_answer) are in dq_hc_items_behaviour.dm.

/// Picks the menu entry of `target` whose label is `label`, as the player picks it from the context menu.
/proc/hci2d1_menu(mob/living/carbon/human/H, atom/target, label)
	RETURN_TYPE(/datum/op_result)
	var/list/rows = action_options(H, target, H.get_active_hand())
	for(var/list/row in rows)
		var/row_label = row["label"] || row["name"]
		if(row_label == label)
			return test_menu(H, target, row["key"] || row["id"])
	return null

/// What is open for `H` to answer, for a failure message.
/proc/hci2d1_open_text(mob/living/carbon/human/H)
	var/list/lines = list()
	var/datum/request/R = SSrequests.open_for(H)
	lines += "request: [R ? R.type : "none"]"
	for(var/datum/om/prompt/P in om_scheduler().test_prompts)
		lines += "om prompt: [P.type] answered=[P.answered]"
	return jointext(lines, "; ")

// ---------------------------------------------------------------------------------------------------------------------
// Crayons
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/crayon_mime_inverts_colours

/datum/unit_test/dq_hc_items/crayon_mime_inverts_colours/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/pen/crayon/mime/C = allocate(/obj/item/pen/crayon/mime, tile(2, 2))
	hci_click(H, C, C)
	settle()
	TEST_ASSERT_EQUAL(C.colour, "#000000", "a first use draws in black")
	TEST_ASSERT_EQUAL(C.shadeColour, "#FFFFFF", "with a white shade")
	hci_click(H, C, C)
	settle()
	TEST_ASSERT_EQUAL(C.colour, "#FFFFFF", "a second use draws in white")
	TEST_ASSERT_EQUAL(C.shadeColour, "#000000", "with a black shade")
	var/obj/item/pen/crayon/marker/mime/M = allocate(/obj/item/pen/crayon/marker/mime, tile(3, 2))
	hci_click(H, M, M)
	settle()
	TEST_ASSERT_EQUAL(M.colour, "#000000", "the mime marker inverts too")
	TEST_ASSERT_EQUAL(M.shadeColour, "#FFFFFF", "with its shade")

/datum/unit_test/dq_hc_items/crayon_rainbow_picks_colour_then_shade

/datum/unit_test/dq_hc_items/crayon_rainbow_picks_colour_then_shade/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/pen/crayon/rainbow/C = allocate(/obj/item/pen/crayon/rainbow, tile(2, 2))
	hci_click(H, C, C)
	settle()
	hci_answer(H, "#112233")
	settle()
	TEST_ASSERT_EQUAL(C.colour, "#112233", "the first answer is the colour")
	TEST_ASSERT_EQUAL(C.shadeColour, "#000FFF", "the shade waits for its own answer")
	hci_answer(H, "#445566")
	settle()
	TEST_ASSERT_EQUAL(C.colour, "#112233", "the colour stays")
	TEST_ASSERT_EQUAL(C.shadeColour, "#445566", "the second answer is the shade")
	// A cancel of the colour keeps it and still asks for the shade.
	hci_click(H, C, C)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(C.colour, "#112233", "a cancelled colour is kept")
	hci_answer(H, "#778899")
	settle()
	TEST_ASSERT_EQUAL(C.shadeColour, "#778899", "the shade is still asked after a cancelled colour")
	// A cancel of the shade keeps it.
	hci_click(H, C, C)
	settle()
	hci_answer(H, "#010203")
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(C.colour, "#010203", "the colour was set")
	TEST_ASSERT_EQUAL(C.shadeColour, "#778899", "a cancelled shade is kept")
	var/obj/item/pen/crayon/marker/rainbow/M = allocate(/obj/item/pen/crayon/marker/rainbow, tile(3, 2))
	hci_click(H, M, M)
	settle()
	hci_answer(H, "#0a0b0c")
	settle()
	hci_answer(H, "#0d0e0f")
	settle()
	TEST_ASSERT_EQUAL(M.colour, "#0a0b0c", "the rainbow marker picks its colour")
	TEST_ASSERT_EQUAL(M.shadeColour, "#0d0e0f", "and its shade")

/datum/unit_test/dq_hc_items/crayon_draws_on_the_floor_after_two_questions

/datum/unit_test/dq_hc_items/crayon_draws_on_the_floor_after_two_questions/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/floor = tile(2, 3)
	var/obj/item/pen/crayon/C = allocate(/obj/item/pen/crayon, tile(2, 2))
	C.uses = 2
	hci_click(H, floor, C)
	settle()
	hci_answer(H, "arrow")
	settle()
	TEST_ASSERT(!(locate(/obj/effect/decal/cleanable/crayon) in floor), "nothing is drawn before the second answer")
	hci_answer(H, "left")
	test_time(1 SECONDS)
	TEST_ASSERT(!(locate(/obj/effect/decal/cleanable/crayon) in floor), "drawing takes its time")
	test_time(10 SECONDS)
	var/obj/effect/decal/cleanable/crayon/D = locate() in floor
	TEST_ASSERT(D, "the drawing lands on the floor")
	TEST_ASSERT_EQUAL(C.uses, 1, "a use is spent")
	qdel(D)
	// Moving away while the question is open drops the answer.
	var/mob/living/carbon/human/H2 = person(tile(4, 4))
	var/turf/far = tile(4, 5)
	var/obj/item/pen/crayon/C2 = allocate(/obj/item/pen/crayon, tile(4, 4))
	hci_click(H2, far, C2)
	settle()
	H2.forceMove(tile(8, 8))
	hci_answer(H2, "rune")
	settle()
	TEST_ASSERT(!(locate(/obj/effect/decal/cleanable/crayon) in far), "an answer from out of reach draws nothing")

// ---------------------------------------------------------------------------------------------------------------------
// Desk bell
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/deskbell_radial_picks_up

/datum/unit_test/dq_hc_items/deskbell_radial_picks_up/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/deskbell/B = allocate(/obj/item/deskbell, tile(2, 2))
	hci_click(H, B, null)
	settle()
	hci_answer(H, "pick up")
	settle()
	TEST_ASSERT(H.is_in_hands(B), "the radial's pick up takes the bell")

/datum/unit_test/dq_hc_items/deskbell_stance_decides_whether_it_can_break

/datum/unit_test/dq_hc_items/deskbell_stance_decides_whether_it_can_break/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/deskbell/B = allocate(/obj/item/deskbell, tile(2, 2))
	for(var/i in 1 to 300)
		hci_click(H, B, null, I_HELP)
		hci_answer(H, "use")
	TEST_ASSERT(!B.broken, "a gentle ring never breaks the bell")
	for(var/i in 1 to 600)
		if(B.broken)
			break
		hci_click(H, B, null, I_HURT)
		hci_answer(H, "use")
	TEST_ASSERT(B.broken, "hammering rudely breaks it in the end")
	hci_click(H, B, null, I_HELP)
	settle()
	hci_answer(H, "pick up")
	settle()
	TEST_ASSERT(H.is_in_hands(B), "a broken bell can still be picked up")

/datum/unit_test/dq_hc_items/deskbell_item_in_harm_hammers

/datum/unit_test/dq_hc_items/deskbell_item_in_harm_hammers/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/deskbell/B = allocate(/obj/item/deskbell, tile(2, 2))
	var/obj/item/pen/P = allocate(/obj/item/pen, tile(3, 3))
	H.put_in_active_hand(P)
	H.set_use_stance(I_HURT)
	var/explained = explain_click(H, B, P, GESTURE_CLICK)
	H.set_use_stance(I_HELP)
	for(var/i in 1 to 300)
		hci_click(H, B, P, I_HELP)
	TEST_ASSERT(!B.broken, "ringing with an item in a gentle stance never breaks it")
	for(var/i in 1 to 600)
		if(B.broken)
			break
		hci_click(H, B, P, I_HURT)
	TEST_ASSERT(B.broken, "hammering with an item breaks it in the end: [explained]")

// ---------------------------------------------------------------------------------------------------------------------
// Religious icon
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/godfig_is_customised_and_named

/datum/unit_test/dq_hc_items/godfig_is_customised_and_named/run_gate()
	var/mob/living/carbon/human/H = person()
	var/datum/mind/M = own(new /datum/mind("godfig_test")) // the test deletes it: a dropped mind leaves its owned identity stamped with a dead owner
	M.transfer_to(H)
	var/obj/item/godfig/G = allocate(/obj/item/godfig, tile(2, 2))
	H.put_in_active_hand(G)
	hci2d1_menu(H, G, "Customize Figure")
	settle()
	hci_answer(H, "Robot")
	settle()
	TEST_ASSERT_EQUAL(G.icon_state, "robot", "the chosen figure is shown")
	TEST_ASSERT(findtext(G.desc, "synthetic humanoid"), "with its description")
	hci2d1_menu(H, G, "Name Figure")
	settle()
	hci_answer(H, "Zorp")
	settle()
	TEST_ASSERT_EQUAL(G.name, "icon of Zorp", "the figure is named")

// ---------------------------------------------------------------------------------------------------------------------
// Virus extrapolator
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/extrapolator_toggles_mode_and_takes_a_scanner

/datum/unit_test/dq_hc_items/extrapolator_toggles_mode_and_takes_a_scanner/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/extrapolator/E = allocate(/obj/item/extrapolator, tile(2, 2))
	TEST_ASSERT(E.scan, "starts in scan mode")
	hci_click(H, E, E)
	settle()
	TEST_ASSERT(!E.scan, "use in hand switches to extract")
	TEST_ASSERT_EQUAL(E.icon_state, "extrapolator_sample", "and shows the probe out")
	hci_click(H, E, E)
	settle()
	TEST_ASSERT(E.scan, "again switches back")
	TEST_ASSERT_EQUAL(E.icon_state, "extrapolator_scan", "and shows the probe in")
	var/obj/item/stock_parts/scanning_module/old = E.scanner
	TEST_ASSERT(old, "it starts with a scanner")
	hci_click(H, E, allocate(/obj/item/stock_parts/scanning_module, tile(3, 3)))
	settle()
	TEST_ASSERT_EQUAL(E.scanner, old, "a second scanner is not installed over the first")

/// A strain with two traits, as the extrapolator isolates them.
/proc/hci2d1_strain()
	var/datum/affliction/contagion/engineered/T = new
	rel_add(T, nameof(T.symptoms), new /datum/viral_trait/cough)
	rel_add(T, nameof(T.symptoms), new /datum/viral_trait/confusion)
	T.Finalize()
	T.Refresh()
	return T

/// Throws a culture bottle away with the strain copies its blood carries (nothing else owns them).
/proc/hci2d1_drop_culture(obj/item/reagent_containers/glass/beaker/vial/bottle)
	for(var/datum/reagent/R in bottle.reagents.reagent_list)
		var/list/viruses = R.data ? R.data["viruses"] : null
		for(var/datum/D in viruses)
			qdel(D)
	qdel(bottle)

/datum/unit_test/dq_hc_items/extrapolator_question_chain_ends_in_a_symptom_culture

/datum/unit_test/dq_hc_items/extrapolator_question_chain_ends_in_a_symptom_culture/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/X = tile(5, 5)
	var/mob/living/carbon/human/V1 = person(X)
	var/mob/living/carbon/human/V2 = person(X)
	var/datum/affliction/contagion/engineered/T = hci2d1_strain()
	TEST_ASSERT(V1.force_contagion(T), "the first carrier is infected")
	var/datum/affliction/contagion/flu/flu1 = new
	var/datum/affliction/contagion/flu/flu2 = new
	TEST_ASSERT(V1.force_contagion(flu1), "and with a second disease")
	TEST_ASSERT(V2.force_contagion(flu2), "the second carrier has the flu")
	var/datum/affliction/contagion/engineered/D = contagion_of(V1, /datum/affliction/contagion/engineered)
	TEST_ASSERT(D, "the strain is carried")
	var/obj/item/extrapolator/E = allocate(/obj/item/extrapolator, tile(2, 2))
	E.scan = FALSE
	H.put_in_active_hand(E)
	E.afterattack(X, H, TRUE)
	settle()
	hci_answer(H, V1)
	settle()
	hci_answer(H, D)
	settle()
	hci_answer(H, "Symptom")
	settle()
	var/datum/viral_trait/chosen = D.symptoms[1]
	hci_answer(H, chosen)
	test_time(60 SECONDS)
	var/obj/item/reagent_containers/glass/beaker/vial/bottle = H.get_inactive_hand()
	TEST_ASSERT(istype(bottle), "the culture bottle ends up in the other hand")
	TEST_ASSERT(findtext(bottle?.name, "culture bottle"), "and is a culture")
	hci2d1_drop_culture(bottle)
	qdel(T)
	qdel(flu1)
	qdel(flu2)

/datum/unit_test/dq_hc_items/extrapolator_isolates_a_whole_disease

/datum/unit_test/dq_hc_items/extrapolator_isolates_a_whole_disease/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(tile(5, 5))
	var/datum/affliction/contagion/engineered/T = hci2d1_strain()
	TEST_ASSERT(V.force_contagion(T), "the carrier is infected")
	var/obj/item/extrapolator/E = allocate(/obj/item/extrapolator, tile(2, 2))
	E.scan = FALSE
	H.put_in_active_hand(E)
	E.afterattack(V, H, TRUE)
	settle()
	hci_answer(H, "Disease")
	test_time(60 SECONDS)
	var/obj/item/reagent_containers/glass/beaker/vial/bottle = H.get_inactive_hand()
	TEST_ASSERT(istype(bottle), "the culture bottle ends up in the other hand")
	hci2d1_drop_culture(bottle)
	// A question answered after the extrapolator left the hand is dropped.
	E.extrapolate(H, V)
	settle()
	H.drop_item()
	hci_answer(H, "Disease")
	test_time(60 SECONDS)
	TEST_ASSERT(!istype(H.get_inactive_hand(), /obj/item/reagent_containers/glass/beaker/vial), "no culture is made without the extrapolator carried")
	qdel(T)

// ---------------------------------------------------------------------------------------------------------------------
// Toys
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/toy_water_balloon_fills_from_a_glass

/datum/unit_test/dq_hc_items/toy_water_balloon_fills_from_a_glass/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/balloon/B = allocate(/obj/item/toy/balloon, tile(2, 3))
	var/obj/item/reagent_containers/glass/beaker/G = allocate(/obj/item/reagent_containers/glass/beaker, tile(2, 2))
	G.reagents.add_reagent(REAGENT_ID_WATER, 20)
	hci_click(H, B, G)
	settle()
	TEST_ASSERT_EQUAL(B.reagents.total_volume, 10, "the balloon takes ten units from the glass")
	TEST_ASSERT_EQUAL(G.reagents.total_volume, 10, "which the glass loses")
	B.update_icon()
	settle()
	TEST_ASSERT_EQUAL(B.icon_state, "waterballoon", "a filled balloon shows full")

/datum/unit_test/dq_hc_items/toy_sword_extends_recolours_and_rainbows

/datum/unit_test/dq_hc_items/toy_sword_extends_recolours_and_rainbows/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/sword/S = allocate(/obj/item/toy/sword, tile(2, 2))
	TEST_ASSERT(!S.active, "starts retracted")
	var/retracted_overlays = length(S.overlays)
	hci_click(H, S, S)
	settle()
	TEST_ASSERT(S.active, "use extends the blade")
	TEST_ASSERT_EQUAL(S.w_class, ITEMSIZE_LARGE, "it is bulky when extended")
	S.update_icon()
	settle()
	TEST_ASSERT(length(S.overlays) > retracted_overlays, "an extended blade is drawn")
	hci_click(H, S, S)
	settle()
	TEST_ASSERT(!S.active, "use retracts it again")
	TEST_ASSERT_EQUAL(S.w_class, ITEMSIZE_SMALL, "and it is small again")
	var/obj/item/multitool/MT = allocate(/obj/item/multitool, tile(3, 3))
	hci_click(H, S, MT)
	settle()
	TEST_ASSERT(S.rainbow, "a multitool switches the rainbow on while retracted")
	hci_click(H, S, MT)
	settle()
	TEST_ASSERT(!S.rainbow, "and off again")

/datum/unit_test/dq_hc_items/toy_sword_is_recoloured_by_alt_click

/datum/unit_test/dq_hc_items/toy_sword_is_recoloured_by_alt_click/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/sword/S = allocate(/obj/item/toy/sword, tile(2, 2))
	hci_click(H, S, null, I_HELP, "alt=1")
	settle()
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT(SSrequests.open_for(H) || length(om_scheduler().test_prompts), "a colour question is open after the yes")
	hci_answer(H, "#33AA55")
	settle()
	TEST_ASSERT_EQUAL(S.lcolor, "#33aa55", "an alt-click, a yes and a colour recolour the blade ([hci2d1_open_text(H)])")
	hci_click(H, S, null, I_HELP, "alt=1")
	settle()
	hci_answer(H, FALSE)
	settle()
	TEST_ASSERT_EQUAL(S.lcolor, "#33aa55", "a no keeps the colour")

/datum/unit_test/dq_hc_items/toy_large_plushie_hides_an_item

/datum/unit_test/dq_hc_items/toy_large_plushie_hides_an_item/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 3)
	var/obj/structure/plushie/ian/P = allocate(/obj/structure/plushie/ian, T)
	var/obj/item/surgical/scalpel/knife = allocate(/obj/item/surgical/scalpel, tile(2, 2))
	var/obj/item/pen/tiny = allocate(/obj/item/pen, tile(3, 3))
	var/obj/item/threadneedle/needle = allocate(/obj/item/threadneedle, tile(3, 2))
	hci_click(H, P, tiny)
	settle()
	TEST_ASSERT(!P.stored_item, "a sealed plushie takes nothing")
	hci_click(H, P, knife)
	settle()
	TEST_ASSERT(P.opened, "a sharp thing opens it")
	hci_click(H, P, tiny)
	settle()
	TEST_ASSERT_EQUAL(P.stored_item, tiny, "an opened plushie takes the small item")
	hci_click(H, P, needle)
	settle()
	TEST_ASSERT(!P.opened, "a needle sews it shut")
	hci_click(H, P, knife)
	settle()
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		TEST_ASSERT_EQUAL(P.stored_item, tiny, "the item is inside before the [stance] touch")
		hci_click(H, P, null, stance)
		settle()
		TEST_ASSERT(!P.stored_item, "a [stance] touch takes the hidden item out")
		TEST_ASSERT_EQUAL(tiny.loc, T, "onto the floor")
		hci_click(H, P, tiny)
		settle()
		TEST_ASSERT_EQUAL(P.stored_item, tiny, "and it can go back in")

/datum/unit_test/dq_hc_items/toy_small_plushie_hides_an_item_and_is_named

/datum/unit_test/dq_hc_items/toy_small_plushie_hides_an_item_and_is_named/run_gate()
	var/mob/living/carbon/human/H = person()
	var/datum/mind/M = own(new /datum/mind("plushie_test")) // the test deletes it: a dropped mind leaves its owned identity stamped with a dead owner
	M.transfer_to(H)
	var/obj/item/toy/plushie/mouse/P = allocate(/obj/item/toy/plushie/mouse, tile(2, 2))
	var/obj/item/surgical/scalpel/knife = allocate(/obj/item/surgical/scalpel, tile(3, 2))
	var/obj/item/pen/tiny = allocate(/obj/item/pen, tile(3, 3))
	var/obj/item/threadneedle/needle = allocate(/obj/item/threadneedle, tile(4, 3))
	hci_click(H, P, knife)
	settle()
	TEST_ASSERT(P.opened, "a sharp thing opens it")
	hci_click(H, P, tiny)
	settle()
	TEST_ASSERT_EQUAL(P.stored_item, tiny, "an opened plushie takes the small item")
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		hci_click(H, P, P, stance)
		settle()
		TEST_ASSERT(!P.stored_item, "using it in a [stance] stance shakes the item out")
		hci_click(H, P, tiny)
		settle()
		TEST_ASSERT_EQUAL(P.stored_item, tiny, "and it can go back in")
	hci_click(H, P, needle)
	settle()
	TEST_ASSERT(!P.opened, "a needle sews it shut")
	H.put_in_active_hand(P)
	var/datum/op_result/rename_result = hci2d1_menu(H, P, "Name Plushie")
	settle()
	TEST_ASSERT(!isnull(rename_result), "the rename is on the menu")
	TEST_ASSERT(SSrequests.open_for(H), "and asks for a name ([hci2d1_open_text(H)] / [rename_result?.outcome] / [rename_result?.reason])")
	hci_answer(H, "Squeaky")
	settle()
	TEST_ASSERT_EQUAL(P.name, "Squeaky", "the plushie is renamed")
	var/obj/item/toy/plushie/teshari/strix/S = allocate(/obj/item/toy/plushie/teshari/strix, tile(5, 5))
	var/old_name = S.name
	H.drop_item()
	H.put_in_active_hand(S)
	hci2d1_menu(H, S, "Name Plushie")
	settle()
	hci_answer(H, "Nope")
	settle()
	TEST_ASSERT_EQUAL(S.name, old_name, "a plushie that refuses a rename keeps its name")

/datum/unit_test/dq_hc_items/toy_drake_plushie_lights_follow_alt_click

/datum/unit_test/dq_hc_items/toy_drake_plushie_lights_follow_alt_click/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/plushie/borgplushie/drake/D = allocate(/obj/item/toy/plushie/borgplushie/drake, tile(2, 2))
	var/dark_overlays = length(D.overlays)
	hci_click(H, D, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(D.lights_glowing, "an alt-click turns the lights on")
	D.update_icon()
	settle()
	TEST_ASSERT(length(D.overlays) > dark_overlays, "the lit fabric is drawn")
	hci_click(H, D, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(!D.lights_glowing, "and off again")

/datum/unit_test/dq_hc_items/toy_rock_draws_a_face_with_a_held_pen

/datum/unit_test/dq_hc_items/toy_rock_draws_a_face_with_a_held_pen/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/rock/R = allocate(/obj/item/toy/rock, tile(2, 2))
	var/obj/item/pen/P = allocate(/obj/item/pen, tile(3, 3))
	hci_click(H, R, P)
	settle()
	hci_answer(H, "roxie")
	settle()
	TEST_ASSERT_EQUAL(R.icon_state, "roxie", "the chosen face is drawn")
	hci_click(H, R, P)
	settle()
	hci_answer(H, "Cancel")
	settle()
	TEST_ASSERT_EQUAL(R.icon_state, "roxie", "Cancel keeps the face")
	hci_click(H, R, P)
	settle()
	H.drop_item()
	hci_answer(H, "fred")
	settle()
	TEST_ASSERT_EQUAL(R.icon_state, "roxie", "an answer once the pen is gone from the hand is dropped")

/datum/unit_test/dq_hc_items/toy_nuke_plays_its_alarm_once_per_cooldown

/datum/unit_test/dq_hc_items/toy_nuke_plays_its_alarm_once_per_cooldown/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/nuke/N = allocate(/obj/item/toy/nuke, tile(2, 2))
	hci_click(H, N, N)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.icon_state, "nuketoy", "the alarm starts")
	var/cooldown_end = N.cooldown
	hci_click(H, N, N)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.cooldown, cooldown_end, "a second press during the cooldown starts nothing")
	test_time(20 SECONDS)
	TEST_ASSERT_EQUAL(N.icon_state, "nuketoycool", "the toy cools down")
	test_time(4 MINUTES)
	TEST_ASSERT_EQUAL(N.icon_state, "nuketoyidle", "and goes idle")
	var/obj/item/disk/nuclear/D = allocate(/obj/item/disk/nuclear, tile(3, 3))
	hci_click(H, N, D)
	settle()
	TEST_ASSERT_EQUAL(N.icon_state, "nuketoyidle", "the disk does nothing to it")

/datum/unit_test/dq_hc_items/toy_minigibber_takes_a_figure_and_grinds_it

/datum/unit_test/dq_hc_items/toy_minigibber_takes_a_figure_and_grinds_it/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/minigibber/G = allocate(/obj/item/toy/minigibber, tile(2, 2))
	var/obj/item/pen/other = allocate(/obj/item/pen, tile(3, 3))
	hci_click(H, G, other)
	settle()
	TEST_ASSERT(!G.stored_minature, "a pen is not fed to it")
	var/obj/item/toy/figure/prisoner/F = allocate(/obj/item/toy/figure/prisoner, tile(3, 2))
	hci_click(H, G, F)
	settle()
	TEST_ASSERT_EQUAL(G.stored_minature, F, "a held figure is fed in after a moment")
	hci_click(H, G, G)
	settle()
	TEST_ASSERT(!G.stored_minature, "using it grinds the figure")
	TEST_ASSERT(QDELETED(F), "the figure is gone")

/datum/unit_test/dq_hc_items/toy_snake_popper_pops_once_and_is_reloaded

/datum/unit_test/dq_hc_items/toy_snake_popper_pops_once_and_is_reloaded/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/toy/snake_popper/P = allocate(/obj/item/toy/snake_popper, T)
	P.real = 0
	hci_click(H, P, P)
	settle()
	TEST_ASSERT(P.popped, "using it pops it")
	TEST_ASSERT_EQUAL(P.icon_state, "tastybread_popped", "and shows it")
	var/obj/item/toy/plushie/snakeplushie/S = locate() in range(2, T)
	TEST_ASSERT(S, "a plush snake comes out")
	hci_click(H, P, P)
	settle()
	TEST_ASSERT(P.popped, "a second press does nothing")
	hci_click(H, P, S)
	settle()
	TEST_ASSERT(!P.popped, "putting the snake back reloads it")
	TEST_ASSERT_EQUAL(P.icon_state, "tastybread", "and shows it")
	test_time(1 MINUTES) // the confetti burst plays itself out
	for(var/obj/effect/effect/confetti/C in range(4, T))
		qdel(C)

/datum/unit_test/dq_hc_items/toy_desk_toy_toggles_by_use_and_alt_click

/datum/unit_test/dq_hc_items/toy_desk_toy_toggles_by_use_and_alt_click/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/desk/newtoncradle/D = allocate(/obj/item/toy/desk/newtoncradle, tile(2, 2))
	var/base = D.icon_state
	hci_click(H, D, D)
	settle()
	TEST_ASSERT(D.on, "use switches it on")
	D.update_icon()
	settle()
	TEST_ASSERT_EQUAL(D.icon_state, "[base]-on", "and shows it")
	hci_click(H, D, null, I_HELP, "alt=1")
	settle()
	TEST_ASSERT(!D.on, "an alt-click switches it off")
	D.update_icon()
	settle()
	TEST_ASSERT_EQUAL(D.icon_state, base, "and shows it")

/datum/unit_test/dq_hc_items/toy_acorn_branch_gives_one_acorn_to_its_owner

/datum/unit_test/dq_hc_items/toy_acorn_branch_gives_one_acorn_to_its_owner/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(tile(4, 4))
	var/obj/item/toy/acorn_branch/B = allocate(/obj/item/toy/acorn_branch, tile(2, 2))
	hci_click(H, B, B)
	settle()
	TEST_ASSERT_EQUAL(B.registered_mob, H, "the first user is registered")
	var/obj/item/reagent_containers/food/snacks/acorn/A = H.get_inactive_hand()
	TEST_ASSERT(istype(A), "an acorn lands in the free hand")
	hci_click(H, B, B)
	settle()
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), A, "a second pull is refused while it recharges")
	hci_click(other, B, B)
	settle()
	TEST_ASSERT_EQUAL(B.registered_mob, H, "nobody else takes it over")
	TEST_ASSERT(!istype(other.get_inactive_hand(), /obj/item/reagent_containers/food/snacks/acorn), "and gets no acorn")
	qdel(A)

/datum/unit_test/dq_hc_items/toy_balloon_structure_reacts_to_every_touch

/datum/unit_test/dq_hc_items/toy_balloon_structure_reacts_to_every_touch/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/balloon/bat/B = allocate(/obj/structure/balloon/bat, tile(2, 3))
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		H.next_click = 0
		hci_click(H, B, null, stance)
		TEST_ASSERT(H.next_click > 0, "a [stance] touch costs the toucher a click cooldown")
	TEST_ASSERT(!QDELETED(B), "the balloon survives")

/datum/unit_test/dq_hc_items/toy_mecha_plays_and_is_picked_up_and_fights

/datum/unit_test/dq_hc_items/toy_mecha_plays_and_is_picked_up_and_fights/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/toy/mecha/ripley/M = allocate(/obj/item/toy/mecha/ripley, tile(2, 2))
	hci_click(H, M, null)
	settle()
	TEST_ASSERT(H.is_in_hands(M), "an empty hand picks it up")
	TEST_ASSERT(!COOLDOWN_FINISHED(M, timer), "and playing with it starts its cooldown")
	M.timer = 0 // the cooldown runs on the world clock, which the test clock does not move
	hci_click(H, M, M)
	settle()
	TEST_ASSERT(!COOLDOWN_FINISHED(M, timer), "use plays with it too")
	M.timer = 0
	var/obj/item/toy/mecha/fireripley/E = allocate(/obj/item/toy/mecha/fireripley, tile(2, 3))
	hci_click(H, E, M)
	TEST_ASSERT(M.in_combat && E.in_combat, "a held mech clicked on another starts the brawl")
	hci_click(H, E, M)
	TEST_ASSERT(M.in_combat, "a second click while fighting changes nothing")
	qdel(E)
	M.in_combat = FALSE
	M.timer = 0
	var/obj/item/toy/mecha/ripley/far_mech = allocate(/obj/item/toy/mecha/ripley, tile(2, 4))
	hci_click(H, far_mech, M)
	TEST_ASSERT(M.in_combat && far_mech.in_combat, "a mech held across a gap of one tile still starts the brawl (its reach is two)")

// ---------------------------------------------------------------------------------------------------------------------
// Blueprints, the wire reader and the area-making paper
// ---------------------------------------------------------------------------------------------------------------------

/// Follows a link of a page held by `H`: the href reaches the item's Topic() as a click on the page's link does.
/proc/hci2d1_topic(mob/living/carbon/human/H, datum/target, key, value = "1")
	var/list/href_list = list("src" = REF(target))
	href_list[key] = value
	usr = H // ALLOW(sys_usr_outside_verb): the test stands in for BYOND's own Topic() entry, where usr is the clicking mob
	return target.Topic(list2params(href_list), href_list)

/// Every turf of the test room and its walls with the area it is in, to put back what a blueprint moved.
/proc/hci2d1_area_snapshot(turf/center)
	var/list/snapshot = list()
	for(var/turf/T in range(10, center))
		snapshot[T] = T.loc
	return snapshot

/// Puts the turfs back in their areas and drops the areas that were made.
/proc/hci2d1_area_restore(list/snapshot)
	var/list/made = list()
	for(var/turf/T as anything in snapshot)
		var/area/was = snapshot[T]
		if(T.loc != was)
			made |= T.loc
			ChangeArea(T, was)
	for(var/area/gone in made)
		qdel(gone)

/datum/unit_test/dq_hc_items/blueprint_rename_area

/datum/unit_test/dq_hc_items/blueprint_rename_area/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/areaeditor/blueprints/BP = allocate(/obj/item/areaeditor/blueprints, tile(2, 2))
	var/area/room = get_area(H)
	var/old_name = room.name
	TEST_ASSERT_EQUAL(BP.get_area_type(room), AREA_STATION, "the test room is a station area")
	hci2d1_topic(H, BP, "edit_area")
	settle()
	TEST_ASSERT(!SSrequests.open_for(H) && !length(om_scheduler().test_prompts), "an editor not in the hand's link does nothing")
	H.put_in_active_hand(BP)
	hci2d1_topic(H, BP, "edit_area")
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(room.name, old_name, "a cancelled question keeps the name")
	hci2d1_topic(H, BP, "edit_area")
	settle()
	hci_answer(H, "Hci Test Room")
	settle()
	TEST_ASSERT_EQUAL(room.name, "Hci Test Room", "the answer renames the area the holder stands in")
	rename_area(room, old_name)
	hci2d1_topic(H, BP, "edit_area")
	settle()
	H.drop_item()
	hci_answer(H, "Dropped Room")
	settle()
	TEST_ASSERT_EQUAL(room.name, old_name, "an answer once the editor left the hand is dropped")

/datum/unit_test/dq_hc_items/blueprint_expand_makes_a_new_area

/datum/unit_test/dq_hc_items/blueprint_expand_makes_a_new_area/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/areaeditor/blueprints/BP = allocate(/obj/item/areaeditor/blueprints, tile(2, 2))
	H.put_in_active_hand(BP)
	var/area/room = get_area(H)
	var/list/snapshot = hci2d1_area_snapshot(tile(3, 3))
	hci2d1_topic(H, BP, "create_area")
	settle()
	hci_answer(H, "New Area")
	settle()
	hci_answer(H, "Hci Annex")
	settle()
	var/area/made = get_area(H)
	TEST_ASSERT_EQUAL(made.name, "Hci Annex", "the holder's turf is in the new area")
	TEST_ASSERT(made != room, "which is not the old one")
	TEST_ASSERT(!BP.in_use, "the editor is free again")
	hci2d1_area_restore(snapshot)
	TEST_ASSERT_EQUAL(get_area(H), room, "(put back)")
	// A cancelled name or a walk away drops the change.
	hci2d1_topic(H, BP, "create_area")
	settle()
	hci_answer(H, "New Area")
	settle()
	H.forceMove(tile(4, 4))
	hci_answer(H, "Walked Off")
	settle()
	TEST_ASSERT_EQUAL(get_area(H), room, "an answer from another turf than the one the question started on is dropped")
	H.forceMove(tile(2, 2))
	hci2d1_topic(H, BP, "create_area")
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(get_area(H), room, "a cancelled choice changes nothing")

/datum/unit_test/dq_hc_items/blueprint_whole_room_is_confirmed_before_it_changes

/datum/unit_test/dq_hc_items/blueprint_whole_room_is_confirmed_before_it_changes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/areaeditor/blueprints/BP = allocate(/obj/item/areaeditor/blueprints, tile(2, 2))
	H.put_in_active_hand(BP)
	var/area/room = get_area(H)
	var/list/snapshot = hci2d1_area_snapshot(tile(3, 3))
	hci2d1_topic(H, BP, "create_area_whole")
	settle()
	hci_answer(H, "New Area")
	settle()
	hci_answer(H, "Hci Whole Room")
	settle()
	hci_answer(H, FALSE)
	settle()
	TEST_ASSERT_EQUAL(get_area(H), room, "a no at the last question changes nothing")
	hci2d1_topic(H, BP, "create_area_whole")
	settle()
	hci_answer(H, "New Area")
	settle()
	hci_answer(H, "Hci Whole Room")
	settle()
	hci_answer(H, TRUE)
	settle()
	var/area/made = get_area(H)
	TEST_ASSERT_EQUAL(made.name, "Hci Whole Room", "a yes moves the whole room into the new area")
	TEST_ASSERT(made != room, "which is not the old one")
	hci2d1_area_restore(snapshot)

/datum/unit_test/dq_hc_items/blueprint_charges_move_between_editors

/datum/unit_test/dq_hc_items/blueprint_charges_move_between_editors/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/areaeditor/blueprints/engineers/mine = allocate(/obj/item/areaeditor/blueprints/engineers, tile(2, 2))
	var/obj/item/areaeditor/blueprints/master = allocate(/obj/item/areaeditor/blueprints, tile(3, 3))
	var/obj/item/areaeditor/blueprints/engineers/other = allocate(/obj/item/areaeditor/blueprints/engineers, tile(3, 2))
	mine.charges = 5
	hci_click(H, mine, master)
	settle()
	TEST_ASSERT_EQUAL(mine.charges, mine.initial_charges, "a master editor refills it")
	mine.charges = 5
	other.charges = 10
	hci_click(H, mine, other)
	settle()
	hci_answer(H, 7)
	settle()
	TEST_ASSERT_EQUAL(mine.charges, 12, "the number asked for moves over")
	TEST_ASSERT_EQUAL(other.charges, 3, "from the other editor")
	hci_click(H, mine, other)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_EQUAL(mine.charges, 12, "a cancel moves nothing")
	mine.charges = mine.initial_charges
	other.charges = 10
	hci_click(H, mine, other)
	settle()
	TEST_ASSERT_EQUAL(other.charges, 10, "a full editor takes nothing")

/datum/unit_test/dq_hc_items/blueprint_legend_links_follow_the_wire_schematics

/datum/unit_test/dq_hc_items/blueprint_legend_links_follow_the_wire_schematics/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/areaeditor/blueprints/BP = allocate(/obj/item/areaeditor/blueprints, tile(2, 2))
	H.put_in_active_hand(BP)
	hci2d1_topic(H, BP, "view_legend")
	TEST_ASSERT(!BP.legend, "an editor that cannot read wires ignores the legend link")
	BP.wire_schematics = 1
	hci2d1_topic(H, BP, "view_legend")
	TEST_ASSERT_EQUAL(BP.legend, TRUE, "one that can opens the legend")
	hci2d1_topic(H, BP, "view_wireset", "/datum/wires/airlock")
	TEST_ASSERT_EQUAL(BP.legend, "/datum/wires/airlock", "and a wire set from it")
	hci2d1_topic(H, BP, "exit_legend")
	TEST_ASSERT(!BP.legend, "the back link leaves the legend")
	BP.wire_schematics = 0
	hci2d1_topic(H, BP, "view_wireset", "/datum/wires/airlock")
	TEST_ASSERT(!BP.legend, "an editor that cannot read wires ignores a wire set link")

/datum/unit_test/dq_hc_items/blueprint_wire_reader_follows_its_links

/datum/unit_test/dq_hc_items/blueprint_wire_reader_follows_its_links/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/wire_reader/R = allocate(/obj/item/wire_reader, tile(2, 2))
	TEST_ASSERT_EQUAL(R.legend, TRUE, "starts on the legend")
	hci2d1_topic(H, R, "view_wireset", "/datum/wires/airlock")
	TEST_ASSERT_EQUAL(R.legend, "/datum/wires/airlock", "a wire set link shows that set")
	hci2d1_topic(H, R, "view_legend")
	TEST_ASSERT_EQUAL(R.legend, TRUE, "the back link shows the legend")

/datum/unit_test/dq_hc_items/blueprint_colour_highlights_come_and_go

/datum/unit_test/dq_hc_items/blueprint_colour_highlights_come_and_go/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/areaeditor/blueprints/BP = allocate(/obj/item/areaeditor/blueprints, tile(2, 2))
	hci2d1_menu(H, BP, "Show Area Colors")
	TEST_ASSERT(!length(BP.areaColor_turfs), "not carried: nothing is shown")
	H.put_in_active_hand(BP)
	hci2d1_menu(H, BP, "Show Area Colors")
	settle()
	TEST_ASSERT(length(BP.areaColor_turfs), "the nearby areas are highlighted")
	hci2d1_menu(H, BP, "Remove Area Colors")
	settle()
	TEST_ASSERT(!length(BP.areaColor_turfs), "and cleared")
	hci2d1_menu(H, BP, "Show Room Colors")
	settle()
	TEST_ASSERT(length(BP.areaColor_turfs), "the room the holder stands in is highlighted")
	H.drop_item()
	TEST_ASSERT(!length(BP.areaColor_turfs), "dropping the editor clears the highlight")

/datum/unit_test/dq_hc_items/blueprint_paper_makes_one_area

/datum/unit_test/dq_hc_items/blueprint_paper_makes_one_area/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/paper/P = allocate(/obj/item/paper, tile(2, 2))
	H.put_in_active_hand(P)
	var/area/room = get_area(H)
	var/was_outdoors = room.outdoors
	room.outdoors = TRUE // an area anyone may build in
	var/list/snapshot = hci2d1_area_snapshot(tile(3, 3))
	hci2d1_menu(H, P, "Create Area")
	settle()
	hci_answer(H, "Hci Paper Room")
	settle()
	var/area/made = get_area(H)
	TEST_ASSERT_EQUAL(made.name, "Hci Paper Room", "the answer names a new area around the user")
	TEST_ASSERT(!COOLDOWN_FINISHED(P, area_cooldown), "and starts the paper's cooldown")
	hci2d1_area_restore(snapshot)
	var/open_before = SSrequests.open_for(H)
	hci2d1_menu(H, P, "Create Area")
	settle()
	TEST_ASSERT_EQUAL(SSrequests.open_for(H), open_before, "a second try within the minute asks nothing")
	room.outdoors = was_outdoors
