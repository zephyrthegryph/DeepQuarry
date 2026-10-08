// Behaviour-preservation tests for droppers and syringes (phase 2, reagent containers, step 3): what the click does on a container, on a tank, on
// yourself and on somebody else, the waits a person's eyes or skin cost, the syringe's modes, the stab, the broken needle and the examine. They use the
// base and the click helpers of dq_p2_reagent_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The syringe's mode now: "capped", "draw", "inject" or "broken".
/proc/rc_syringe_mode(obj/item/reagent_containers/syringe/S)
	switch(S.mode)
		if(0)
			return "draw"
		if(1)
			return "inject"
		if(2)
			return "broken"
	return "capped"

/// Puts the syringe in the mode named.
/proc/rc_syringe_set_mode(obj/item/reagent_containers/syringe/S, mode)
	switch(mode)
		if("draw")
			S.set_mode(0)
		if("inject")
			S.set_mode(1)
		if("broken")
			S.set_mode(2)
		else
			S.set_mode(10)
	S.update_icon()

/// The units of blood in the person's holder.
/proc/rc_blood_units(mob/living/L)
	return round(L.reagents.total_volume, 0.01)

/// The units in the person's stomach.
/proc/rc_stomach_units(mob/living/carbon/L)
	return round(L.ingested.total_volume, 0.01)

/// The person sets the amount of a needle container, giving `value` when asked.
/proc/rc_needle_set_amount(mob/actor, obj/item/reagent_containers/C, value)
	rc_set_amount_menu(actor, C, value)

/// A syringe of `type` holding `amount` units of water, in `mode`.
/datum/unit_test/dq_p2_reagents/proc/rc_syringe(type, amount = 0, mode = "draw")
	var/obj/item/reagent_containers/syringe/S = rc_filled(type, amount)
	rc_syringe_set_mode(S, mode)
	return S

// ---------------------------------------------------------------------------------------------------------------------
// What they are
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/needles_start_as_declared

/datum/unit_test/dq_p2_reagents/needles_start_as_declared/run_gate()
	var/list/expected = list(
		list(/obj/item/reagent_containers/dropper, 5, 5, 1, 5),
		list(/obj/item/reagent_containers/dropper/industrial, 10, 10, 1, 10),
		list(/obj/item/reagent_containers/syringe, 15, 5, 5, null),
		list(/obj/item/reagent_containers/syringe/ld50_syringe, 50, 50, 5, null),
		list(/obj/item/reagent_containers/syringe/inaprovaline, 15, 5, 5, null),
	)
	for(var/list/row in expected)
		var/path = row[1]
		var/obj/item/reagent_containers/C = allocate(path)
		TEST_ASSERT_EQUAL(rc_capacity(C), row[2], "[path]: capacity")
		TEST_ASSERT_EQUAL(rc_amount(C), row[3], "[path]: the amount of one transfer")
		var/list/range = rc_amount_range(C)
		TEST_ASSERT_EQUAL(range[1], row[4], "[path]: the least amount")
		TEST_ASSERT_EQUAL(range[2], row[5], "[path]: the most amount")
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "capped", "a new syringe is capped")
	var/obj/item/reagent_containers/syringe/inaprovaline/stocked = allocate(/obj/item/reagent_containers/syringe/inaprovaline)
	TEST_ASSERT_EQUAL(rc_units(stocked), 15, "a stocked syringe holds its reagent")
	var/obj/item/reagent_containers/syringe/old/old = allocate(/obj/item/reagent_containers/syringe/old)
	TEST_ASSERT_EQUAL(rc_syringe_mode(old), "broken", "an old syringe is broken")
	var/obj/item/reagent_containers/syringe/ld50_syringe/choral/choral = allocate(/obj/item/reagent_containers/syringe/ld50_syringe/choral)
	TEST_ASSERT_EQUAL(rc_syringe_mode(choral), "inject", "the lethal injection syringe is ready to inject")
	TEST_ASSERT_EQUAL(rc_units(choral), 50, "and full")

// ---------------------------------------------------------------------------------------------------------------------
// Dropper
// ---------------------------------------------------------------------------------------------------------------------

/// An empty dropper takes one transfer from an open container and from a tank; not from a closed container; nothing from an empty one.
/datum/unit_test/dq_p2_reagents/dropper_takes_from_open_containers_and_tanks

/datum/unit_test/dq_p2_reagents/dropper_takes_from_open_containers_and_tanks/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 0)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, B, D)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "the dropper took one transfer from an open beaker")
	TEST_ASSERT_EQUAL(rc_units(B), 25, "which left it")
	D.reagents.clear_reagents()
	var/obj/item/reagent_containers/glass/beaker/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, empty, D)
	TEST_ASSERT_EQUAL(rc_units(D), 0, "nothing from an empty beaker")
	var/obj/item/reagent_containers/glass/beaker/shut = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	cap_key_set(shut, REAGENT_CONTAINER_LID_OPEN, FALSE)
	TEST_ASSERT(!rc_open(shut), "the beaker's lid is on")
	rc_click(H, shut, D)
	TEST_ASSERT_EQUAL(rc_units(D), 0, "nothing from a closed container")
	TEST_ASSERT_EQUAL(rc_units(shut), 30, "and it lost nothing")
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	rc_click(H, tank, D)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "a tank is drawn from")

/// A dropper that holds something squirts it into an open container, by its amount; a full one takes nothing; a closed one is refused.
/datum/unit_test/dq_p2_reagents/dropper_squirts_into_containers

/datum/unit_test/dq_p2_reagents/dropper_squirts_into_containers/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 5)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, D)
	TEST_ASSERT_EQUAL(rc_units(D), 0, "the dropper emptied")
	TEST_ASSERT_EQUAL(rc_units(B), 5, "into the beaker")
	D.reagents.add_reagent(REAGENT_ID_WATER, 5)
	var/obj/item/reagent_containers/glass/beaker/full = rc_filled(/obj/item/reagent_containers/glass/beaker, 60)
	rc_click(H, full, D)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "a full beaker takes nothing")
	var/obj/item/reagent_containers/glass/beaker/shut = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	cap_key_set(shut, REAGENT_CONTAINER_LID_OPEN, FALSE)
	rc_click(H, shut, D)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "a closed container is refused")
	TEST_ASSERT_EQUAL(rc_units(shut), 0, "and gets nothing")
	var/obj/item/reagent_containers/dropper/industrial/big = rc_filled(/obj/item/reagent_containers/dropper/industrial, 10)
	var/obj/item/reagent_containers/glass/beaker/another = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, another, big)
	TEST_ASSERT_EQUAL(rc_units(another), 10, "the industrial dropper moves its ten")

/// The set-amount of a dropper (an alt-click): from 1 to its largest.
/datum/unit_test/dq_p2_reagents/dropper_amount_can_be_set

/datum/unit_test/dq_p2_reagents/dropper_amount_can_be_set/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 5)
	rc_needle_set_amount(H, D, 2)
	TEST_ASSERT_EQUAL(rc_amount(D), 2, "the dropper moves 2 now")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, D)
	TEST_ASSERT_EQUAL(rc_units(B), 2, "and that is what it squirted")

/// A dropper on a person: it waits two seconds, then part of the amount is swallowed and part is in the blood.
/datum/unit_test/dq_p2_reagents/dropper_squirts_into_eyes_after_a_wait

/datum/unit_test/dq_p2_reagents/dropper_squirts_into_eyes_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 5)
	var/blood_before = rc_blood_units(patient)
	var/stomach_before = rc_stomach_units(patient)
	rc_click(H, patient, D, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "nothing leaves the dropper at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "nor after one second")
	rc_settle()
	TEST_ASSERT(rc_units(D) < 5, "after the wait the dropper has squirted")
	TEST_ASSERT(rc_stomach_units(patient) > stomach_before, "part of it was swallowed")
	TEST_ASSERT(rc_blood_units(patient) > blood_before, "and part of it is in the blood")

/// Glasses over the eyes keep the squirt out: it splashes the glasses.
/datum/unit_test/dq_p2_reagents/dropper_is_stopped_by_eyewear

/datum/unit_test/dq_p2_reagents/dropper_is_stopped_by_eyewear/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	TEST_ASSERT(patient.equip_to_slot_if_possible(mask, SLOT_ID_MASK), "the patient wears a mask")
	TEST_ASSERT(mask.body_parts_covered & EYES, "which covers the eyes")
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 5)
	var/blood_before = rc_blood_units(patient)
	var/stomach_before = rc_stomach_units(patient)
	rc_click(H, patient, D)
	TEST_ASSERT_EQUAL(rc_blood_units(patient), blood_before, "nothing reached the blood")
	TEST_ASSERT_EQUAL(rc_stomach_units(patient), stomach_before, "nor the stomach")
	TEST_ASSERT(rc_units(D) < 5, "the dropper was spent on the mask")

/// Examine: what it holds to two tiles, and that it is empty.
/datum/unit_test/dq_p2_reagents/dropper_examine

/datum/unit_test/dq_p2_reagents/dropper_examine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 3)
	var/text = jointext(D.examine(H), " ")
	TEST_ASSERT(findtext(text, "3"), "examine says how much is in it: [text]")
	D.reagents.clear_reagents()
	text = jointext(D.examine(H), " ")
	TEST_ASSERT(findtext(text, "empty"), "and that it is empty: [text]")
	D.forceMove(run_loc_floor_top_right)
	D.reagents.add_reagent(REAGENT_ID_WATER, 4)
	text = jointext(D.examine(H), " ")
	TEST_ASSERT(!findtext(text, "4 units") && !findtext(text, "empty"), "from far away it says nothing of its contents: [text]")

/// The look follows whether it holds anything.
/datum/unit_test/dq_p2_reagents/dropper_look_follows_fill

/datum/unit_test/dq_p2_reagents/dropper_look_follows_fill/run_gate()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 0)
	appearance_flush()
	TEST_ASSERT_EQUAL(D.icon_state, "dropper0", "an empty dropper looks empty")
	D.reagents.add_reagent(REAGENT_ID_WATER, 2)
	appearance_flush()
	TEST_ASSERT_EQUAL(D.icon_state, "dropper1", "a filled one looks filled")

// ---------------------------------------------------------------------------------------------------------------------
// Syringe: modes
// ---------------------------------------------------------------------------------------------------------------------

/// Using a syringe in hand uncaps it, then toggles draw and inject; a broken one stays broken.
/datum/unit_test/dq_p2_reagents/syringe_modes_by_use_in_hand

/datum/unit_test/dq_p2_reagents/syringe_modes_by_use_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe)
	rc_use(H, S)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "draw", "the first use uncaps it for drawing")
	rc_use(H, S)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "inject", "the next is for injecting")
	rc_use(H, S)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "draw", "and back")
	rc_syringe_set_mode(S, "broken")
	rc_use(H, S)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "broken", "a broken syringe stays broken")

/// The look: capped, broken, and a fill gauge by thirds.
/datum/unit_test/dq_p2_reagents/syringe_look_follows_mode_and_fill

/datum/unit_test/dq_p2_reagents/syringe_look_follows_mode_and_fill/run_gate()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "capped")
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "capped", "a capped syringe looks capped")
	rc_syringe_set_mode(S, "broken")
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "broken", "a broken one looks broken")
	rc_syringe_set_mode(S, "draw")
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "0", "an empty one reads 0")
	S.reagents.add_reagent(REAGENT_ID_WATER, 10)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "10", "ten units read 10")
	S.reagents.add_reagent(REAGENT_ID_WATER, 5)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "15", "a full one reads 15")

// ---------------------------------------------------------------------------------------------------------------------
// Syringe: containers
// ---------------------------------------------------------------------------------------------------------------------

/// Drawing from an open container takes one transfer a click; when it is full the syringe is set to inject; a closed container is refused.
/datum/unit_test/dq_p2_reagents/syringe_draws_from_containers

/datum/unit_test/dq_p2_reagents/syringe_draws_from_containers/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 60)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "one transfer is drawn")
	TEST_ASSERT_EQUAL(rc_units(B), 55, "from the beaker")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "draw", "it is still drawing")
	rc_click(H, B, S)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "three clicks fill it")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "inject", "and it is set to inject")
	var/obj/item/reagent_containers/syringe/other = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	var/obj/item/reagent_containers/glass/beaker/shut = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	cap_key_set(shut, REAGENT_CONTAINER_LID_OPEN, FALSE)
	rc_click(H, shut, other)
	TEST_ASSERT_EQUAL(rc_units(other), 0, "nothing is drawn through a closed lid")
	var/obj/item/reagent_containers/glass/beaker/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, empty, other)
	TEST_ASSERT_EQUAL(rc_units(other), 0, "nor from an empty one")
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	rc_click(H, tank, other)
	TEST_ASSERT_EQUAL(rc_units(other), 5, "a tank is drawn from")

/// Injecting into a container moves one transfer; an emptied syringe goes back to drawing; a full target is refused.
/datum/unit_test/dq_p2_reagents/syringe_injects_into_containers

/datum/unit_test/dq_p2_reagents/syringe_injects_into_containers/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 10, "inject")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "one transfer left the syringe")
	TEST_ASSERT_EQUAL(rc_units(B), 5, "into the beaker")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "inject", "it is still injecting")
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "the second transfer empties it")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "draw", "an emptied syringe goes back to drawing")
	S.reagents.add_reagent(REAGENT_ID_WATER, 10)
	rc_syringe_set_mode(S, "inject")
	var/obj/item/reagent_containers/glass/beaker/full = rc_filled(/obj/item/reagent_containers/glass/beaker, 60)
	rc_click(H, full, S)
	TEST_ASSERT_EQUAL(rc_units(S), 10, "a full container takes nothing")

/// An empty syringe set to inject goes back to drawing.
/datum/unit_test/dq_p2_reagents/syringe_empty_inject_goes_back_to_drawing

/datum/unit_test/dq_p2_reagents/syringe_empty_inject_goes_back_to_drawing/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "inject")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "draw", "the empty syringe was set to draw")

/// A capped syringe does nothing to a container.
/datum/unit_test/dq_p2_reagents/capped_syringe_does_nothing

/datum/unit_test/dq_p2_reagents/capped_syringe_does_nothing/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 5, "capped")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "a capped syringe takes nothing")
	TEST_ASSERT_EQUAL(rc_units(B), 30, "and gives nothing")

/// A broken syringe does nothing.
/datum/unit_test/dq_p2_reagents/broken_syringe_does_nothing

/datum/unit_test/dq_p2_reagents/broken_syringe_does_nothing/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 5, "broken")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "a broken syringe takes nothing")
	rc_click(H, patient, S, I_HELP)
	rc_click(H, patient, S, I_HURT)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "and injects nothing, stab included")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "broken", "it stays broken")

// ---------------------------------------------------------------------------------------------------------------------
// Syringe: blood
// ---------------------------------------------------------------------------------------------------------------------

/// Drawing your own blood is at once; the syringe takes its free space in blood and, being full, is set to inject.
/datum/unit_test/dq_p2_reagents/syringe_draws_own_blood_at_once

/datum/unit_test/dq_p2_reagents/syringe_draws_own_blood_at_once/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT(S.reagents.has_reagent(REAGENT_ID_BLOOD), "blood is in the syringe at once")
	TEST_ASSERT_EQUAL(rc_units(S), 15, "a full barrel")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "inject", "full: set to inject")

/// Drawing another's blood waits three seconds; a sample already in the syringe is refused.
/datum/unit_test/dq_p2_reagents/syringe_draws_blood_from_another_after_a_wait

/datum/unit_test/dq_p2_reagents/syringe_draws_blood_from_another_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "nor after a second")
	rc_settle()
	TEST_ASSERT(S.reagents.has_reagent(REAGENT_ID_BLOOD), "after the wait there is blood")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "inject", "and the full syringe is set to inject")
	rc_syringe_set_mode(S, "draw")
	S.reagents.remove_any(5)
	var/before = rc_units(S)
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), before, "a second draw is refused while the sample is there")

/// A lethal injection syringe is not for drawing blood, nor for stabbing.
/datum/unit_test/dq_p2_reagents/big_syringe_refuses_blood_and_stabs

/datum/unit_test/dq_p2_reagents/big_syringe_refuses_blood_and_stabs/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/ld50_syringe/S = rc_syringe(/obj/item/reagent_containers/syringe/ld50_syringe, 0, "draw")
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "no blood is drawn with it")
	var/obj/item/reagent_containers/syringe/ld50_syringe/full = rc_syringe(/obj/item/reagent_containers/syringe/ld50_syringe, 50, "inject")
	rc_click(H, patient, full, I_HURT)
	TEST_ASSERT_EQUAL(rc_units(full), 50, "it is not used to stab")
	TEST_ASSERT_EQUAL(rc_syringe_mode(full), "inject", "and is not broken by it")

// ---------------------------------------------------------------------------------------------------------------------
// Syringe: injecting a person
// ---------------------------------------------------------------------------------------------------------------------

/// Injecting another: a warmup (two thirds of the time), then one transfer per cycle until it is empty; all of it lands in the blood.
/datum/unit_test/dq_p2_reagents/syringe_injects_another_after_a_warmup

/datum/unit_test/dq_p2_reagents/syringe_injects_another_after_a_warmup/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "inject")
	var/before = rc_blood_units(patient)
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "nor during the warmup")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 0, "all of it is injected in the end")
	TEST_ASSERT(rc_blood_units(patient) > before, "into the blood (the body already works on some of it)")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "draw", "and the empty syringe is set to draw")

/// The injection is one transfer per cycle: part way, only part has gone.
/datum/unit_test/dq_p2_reagents/syringe_injects_one_transfer_per_cycle

/datum/unit_test/dq_p2_reagents/syringe_injects_one_transfer_per_cycle/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "inject")
	rc_click(H, patient, S, I_HELP, FALSE)
	test_time(2.5 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 10, "after the warmup one transfer has gone")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "a cycle later another")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 0, "and the last")

/// Injecting yourself has the same cycles, with a shorter warmup.
/datum/unit_test/dq_p2_reagents/syringe_injects_yourself

/datum/unit_test/dq_p2_reagents/syringe_injects_yourself/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 10, "inject")
	var/before = rc_blood_units(H)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 10, "nothing at once")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 0, "it is all in the end")
	TEST_ASSERT(rc_blood_units(H) > before, "in your own blood (the body already works on some of it)")

/// The target gone before the warmup ends: nothing is injected.
/datum/unit_test/dq_p2_reagents/syringe_injection_stops_when_the_target_leaves

/datum/unit_test/dq_p2_reagents/syringe_injection_stops_when_the_target_leaves/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "inject")
	rc_click(H, patient, S, I_HELP, FALSE)
	test_time(1 SECONDS)
	patient.forceMove(run_loc_floor_top_right)
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 15, "nothing went in: the patient was gone before the warmup ended")

/// A hostile click stabs: some of the contents go in at once, and the syringe breaks.
/datum/unit_test/dq_p2_reagents/syringe_stab

/datum/unit_test/dq_p2_reagents/syringe_stab/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "inject")
	var/before = rc_blood_units(patient)
	rc_click(H, patient, S, I_HURT, FALSE)
	TEST_ASSERT(rc_units(S) < 15, "a stab puts some of the contents in at once")
	TEST_ASSERT(rc_blood_units(patient) > before, "into the blood")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "broken", "and breaks the syringe")

/// A stab with a nearly empty syringe injects nothing, and never a negative amount.
/datum/unit_test/dq_p2_reagents/syringe_stab_amount_is_never_negative

/datum/unit_test/dq_p2_reagents/syringe_stab_amount_is_never_negative/run_gate()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe)
	for(var/volume in list(0, 3, 5, 9, 10, 15))
		for(var/i in 1 to 20)
			var/amount = S.syringestab_amount(volume)
			TEST_ASSERT(amount >= 0, "volume [volume]: never negative")
			TEST_ASSERT(amount <= max(volume - 5, 0), "volume [volume]: never more than 5 short of the barrel")
			TEST_ASSERT(amount >= max(volume - 10, 0), "volume [volume]: never more than 10 short of the barrel")

// ---------------------------------------------------------------------------------------------------------------------
// More of what a click does
// ---------------------------------------------------------------------------------------------------------------------

/// Syringes and droppers are closed containers: nothing is poured into them, and they do not count as open.
/datum/unit_test/dq_p2_reagents/needles_are_not_open_containers

/datum/unit_test/dq_p2_reagents/needles_are_not_open_containers/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 0)
	TEST_ASSERT(!rc_open(S), "a syringe is not an open container")
	TEST_ASSERT(!rc_open(D), "a dropper is not an open container")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, S, B)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "a beaker does not pour into a syringe")
	TEST_ASSERT_EQUAL(rc_units(B), 30, "and keeps what it had")

/// A syringe does not draw from or inject into a container whose lid is on.
/datum/unit_test/dq_p2_reagents/syringe_refuses_a_closed_container

/datum/unit_test/dq_p2_reagents/syringe_refuses_a_closed_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/shut = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	cap_key_set(shut, REAGENT_CONTAINER_LID_OPEN, FALSE)
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 10, "inject")
	rc_click(H, shut, S)
	TEST_ASSERT_EQUAL(rc_units(S), 10, "nothing goes into a closed container")
	TEST_ASSERT_EQUAL(rc_units(shut), 30, "and nothing is added to it")

/// A harm-intent click on a container is no stab: the syringe works as in any stance.
/datum/unit_test/dq_p2_reagents/syringe_works_on_containers_in_every_stance

/datum/unit_test/dq_p2_reagents/syringe_works_on_containers_in_every_stance/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		var/before = rc_units(S)
		rc_click(H, B, S, stance)
		TEST_ASSERT_EQUAL(rc_units(S) - before, 5, "in the [stance] stance the syringe draws one transfer")
		S.reagents.clear_reagents()
		rc_syringe_set_mode(S, "draw")

/// A capped syringe does nothing to a person in a friendly stance; a hostile click stabs with it all the same (the cap is no guard).
/datum/unit_test/dq_p2_reagents/capped_syringe_does_nothing_to_a_person

/datum/unit_test/dq_p2_reagents/capped_syringe_does_nothing_to_a_person/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "capped") // full: a stab moves rand(5, 10) of 15 (of 10 it may move none)
	var/before = rc_blood_units(patient)
	rc_click(H, patient, S, I_HELP)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "a capped syringe injects nothing")
	TEST_ASSERT_EQUAL(rc_blood_units(patient), before, "and the patient has nothing more")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "capped", "it stays capped")
	rc_click(H, patient, S, I_HURT, FALSE)
	TEST_ASSERT(rc_units(S) < 15, "a hostile click stabs with it all the same")
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "broken", "and breaks it")

/// A full syringe that is set to draw switches to inject when it is clicked on something; an empty one set to inject goes the other way.
/datum/unit_test/dq_p2_reagents/syringe_switches_when_full_or_empty

/datum/unit_test/dq_p2_reagents/syringe_switches_when_full_or_empty/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "draw")
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_syringe_mode(S), "inject", "a full syringe that is drawing is set to inject")
	TEST_ASSERT_EQUAL(rc_units(B), 30, "and took nothing")
	TEST_ASSERT_EQUAL(rc_units(S), 15, "nor gave any")

/// Droppers and syringes are not drunk from: a click on yourself with a filled dropper starts the eye squirt, not a drink.
/datum/unit_test/dq_p2_reagents/dropper_on_yourself_goes_to_the_eyes

/datum/unit_test/dq_p2_reagents/dropper_on_yourself_goes_to_the_eyes/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/dropper/D = rc_filled(/obj/item/reagent_containers/dropper, 5)
	var/stomach_before = rc_stomach_units(H)
	rc_click(H, H, D, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(D), 5, "nothing leaves at once")
	rc_settle()
	TEST_ASSERT(rc_units(D) < 5, "after the wait the dropper has squirted into your eyes")
	TEST_ASSERT(rc_stomach_units(H) > stomach_before, "and some of it is swallowed")

/// An injection does not go into a limb that is not there, nor a robotic one.
/datum/unit_test/dq_p2_reagents/syringe_refuses_a_missing_or_robotic_limb

/datum/unit_test/dq_p2_reagents/syringe_refuses_a_missing_or_robotic_limb/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 15, "inject")
	H.zone_sel.set_selecting(BP_L_ARM)
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.robotize()
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "a robotic limb is not injected")
	arm.droplimb(TRUE, DROPLIMB_EDGE)
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "nor one that is missing")
	H.zone_sel.set_selecting(BP_TORSO)
