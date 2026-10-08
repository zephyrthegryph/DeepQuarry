// Behaviour-preservation tests for the reagent container domain (phase 2): beakers, buckets, kettles, bottles and the other glass containers.
// They pin what a player can observe of a container through public inputs (clicks in each stance, the use-in-hand click, the alt-click, the
// menu pick, window answers, time), so the same file passes before and after the containers move from the legacy interactions and afterattack
// overrides to the reagent_container() capability.
//
// Rules the tests keep:
//   - Input goes through the click helper (the real inbox path: the target's and the held item's ops, else the legacy click chain) and the
//     small adapter block below, which is the only place that names today's accessors.
//   - Every input is followed by rc_settle() (kernel time), because a wait may differ between the two implementations.
//   - Nothing here depends on message text, on an op key or on a click result being non-null.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The container is open: pouring in and out is allowed.
/proc/rc_open(atom/C)
	return !!C.is_open_container()

/// The amount one transfer moves now.
/proc/rc_amount(obj/item/reagent_containers/C)
	return reagent_transfer_amount(C)

/// The smallest and largest amount a person can set.
/proc/rc_amount_range(obj/item/reagent_containers/C)
	return list(C.min_transfer_amount, C.max_transfer_amount)

/// The units the container holds at most.
/proc/rc_capacity(obj/item/reagent_containers/C)
	return C.reagents.maximum_volume

/// The label on the container (empty text: none).
/proc/rc_label(obj/item/reagent_containers/glass/C)
	return C.label_text

/// The icon states of the overlays the container draws now (the fill gauge, the lid, the label), as plain text.
/proc/rc_overlays(obj/item/reagent_containers/glass/C)
	. = list()
	var/datum/look/L = new
	C.draw(L)
	for(var/entry in L.overlays)
		if(istext(entry))
			. += entry
		else
			var/image/I = entry
			. += I.icon_state

/// The person sets the amount from the context menu, giving `value` when asked.
/proc/rc_set_amount_menu(mob/actor, obj/item/reagent_containers/C, value)
	test_menu(actor, C, "reagent_container.set_amount")
	test_answer(actor, value)

/// The mob's venom was expressed long ago (its cooldown has run out).
/proc/rc_milk_cooldown_over(mob/living/L)
	L.venom_milking_cd = 0

// ---------------------------------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------------------------------

/// An item that counts how much water it was wetted with (what a dip does to it).
/obj/item/p2_reagent_probe
	name = "wetness probe"
	w_class = ITEMSIZE_TINY
	var/wetness = 0

/obj/item/p2_reagent_probe/water_act(amount)
	wetness += amount
	return ..()

/datum/unit_test/dq_p2_reagents
	abstract_type = /datum/unit_test/dq_p2_reagents
	var/list/rc_extra

/datum/unit_test/dq_p2_reagents/Run()
	test_driver_begin()
	test_rng(1)
	run_gate()
	for(var/atom/A as anything in rc_extra)
		if(!QDELETED(A))
			qdel(A)
	for(var/obj/effect/effect/water/puff in range(10, run_loc_floor_bottom_left))
		qdel(puff) // what a spray left in the air
	own_turf_contents(run_loc_floor_bottom_left)
	test_driver_end()

/datum/unit_test/dq_p2_reagents/proc/run_gate()
	return

/// Time for any wait a click may start.
/datum/unit_test/dq_p2_reagents/proc/rc_settle()
	test_time(10 SECONDS)

/// A conscious person with hands.
/datum/unit_test/dq_p2_reagents/proc/rc_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	dq_give_zone_sel(H)
	return H

/// A container of `type` holding `amount` units of water.
/datum/unit_test/dq_p2_reagents/proc/rc_filled(type, amount = 0, turf/T)
	var/obj/item/reagent_containers/C = allocate(type, T || run_loc_floor_bottom_left)
	if(amount > 0)
		C.reagents.add_reagent(REAGENT_ID_WATER, amount)
	return C

/// The actor clicks `target` with `held` in hand (nothing: an empty hand), in `stance`, and waits.
/datum/unit_test/dq_p2_reagents
	/// The op result of the last rc_click() (for a failure message).
	var/datum/op_result/rc_last_click

/datum/unit_test/dq_p2_reagents/proc/rc_click(mob/living/carbon/human/H, atom/target, obj/item/held, stance = I_HELP, settle = TRUE)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	H.set_use_stance(stance)
	H.next_click = 0
	var/datum/input_event/click/click = new(H, target, null, null, "left=1")
	input_submit(click)
	rc_last_click = click.result
	if(settle)
		rc_settle()
	H.set_use_stance(I_HELP)

/// The actor uses `held` in hand (clicks the item itself).
/datum/unit_test/dq_p2_reagents/proc/rc_use(mob/living/carbon/human/H, obj/item/held)
	rc_click(H, held, held)

/// The actor alt-clicks `target` with `held` in hand and waits.
/datum/unit_test/dq_p2_reagents/proc/rc_alt_click(mob/living/carbon/human/H, atom/target, obj/item/held)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, target, null, null, "left=1;alt=1"))
	rc_settle()

/// The person labels the container: a pen is used on it and the label is written when it is asked for.
/datum/unit_test/dq_p2_reagents/proc/rc_label_with_pen(mob/living/carbon/human/H, obj/item/reagent_containers/glass/C, obj/item/pen/pen, text)
	rc_click(H, C, pen, I_HELP, FALSE)
	test_answer(H, text)
	rc_settle()

/// The person alt-clicks `target` with `held` in hand and gives `value` when asked the amount.
/datum/unit_test/dq_p2_reagents/proc/rc_alt_set_amount(mob/living/carbon/human/H, atom/target, obj/item/held, value)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, target, null, null, "left=1;alt=1"))
	test_answer(H, value)
	rc_settle()

// ---------------------------------------------------------------------------------------------------------------------
// What each container is
// ---------------------------------------------------------------------------------------------------------------------

/// Capacity, the amount one transfer moves to start with, the range of amounts a person can set, and whether it starts open.
/datum/unit_test/dq_p2_reagents/containers_start_as_declared

/datum/unit_test/dq_p2_reagents/containers_start_as_declared/run_gate()
	var/list/expected = list(
		list(/obj/item/reagent_containers/glass/beaker, 60, 10, 1, 60),
		list(/obj/item/reagent_containers/glass/beaker/large, 120, 10, 1, 120),
		list(/obj/item/reagent_containers/glass/beaker/noreact, 60, 10, 1, 60),
		list(/obj/item/reagent_containers/glass/beaker/bluespace, 300, 10, 1, 300),
		list(/obj/item/reagent_containers/glass/beaker/vial, 30, 10, 1, 30),
		list(/obj/item/reagent_containers/glass/beaker/measuring_cup, 60, 10, 1, 60),
		list(/obj/item/reagent_containers/glass/beaker/stopperedbottle, 120, 10, 1, 120),
		list(/obj/item/reagent_containers/glass/bucket, 120, 20, 1, 120),
		list(/obj/item/reagent_containers/glass/bucket/wood, 120, 20, 1, 120),
		list(/obj/item/reagent_containers/glass/kettle, 60, 10, 1, 20),
		list(/obj/item/reagent_containers/glass/cooler_bottle, 2000, 20, 1, 120),
		list(/obj/item/reagent_containers/glass/pint_mug, 60, 10, 1, 60),
	)
	for(var/list/row in expected)
		var/path = row[1]
		var/obj/item/reagent_containers/C = allocate(path)
		TEST_ASSERT_EQUAL(rc_capacity(C), row[2], "[path]: capacity")
		TEST_ASSERT_EQUAL(rc_amount(C), row[3], "[path]: the first transfer amount")
		var/list/range = rc_amount_range(C)
		TEST_ASSERT_EQUAL(range[1], row[4], "[path]: the smallest amount")
		TEST_ASSERT_EQUAL(range[2], row[5], "[path]: the largest amount")
		TEST_ASSERT(rc_open(C), "[path]: open from the start (no lid on)")
		TEST_ASSERT_EQUAL(C.reagents.total_volume, 0, "[path]: empty")

/// What a type starts with in it, and the flags that are not the lid.
/datum/unit_test/dq_p2_reagents/starting_contents_and_flags

/datum/unit_test/dq_p2_reagents/starting_contents_and_flags/run_gate()
	var/obj/item/reagent_containers/glass/beaker/cryoxadone/C = allocate(/obj/item/reagent_containers/glass/beaker/cryoxadone)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_CRYOXADONE), 30, "the prefilled beaker holds its 30 units")
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "and nothing else")
	TEST_ASSERT_EQUAL(rc_capacity(C), 60, "in a beaker's 60")
	var/obj/item/reagent_containers/glass/beaker/vial/dermaline/V = allocate(/obj/item/reagent_containers/glass/beaker/vial/dermaline)
	TEST_ASSERT_EQUAL(V.reagents.get_reagent_amount(REAGENT_ID_DERMALINE), 30, "a vial of dermaline holds 30")
	TEST_ASSERT_EQUAL(rc_capacity(V), 30, "in a vial's 30")
	var/obj/item/reagent_containers/glass/beaker/vial/supermatter/S = allocate(/obj/item/reagent_containers/glass/beaker/vial/supermatter)
	TEST_ASSERT_EQUAL(S.reagents.total_volume, 5, "a small prefill is kept as it is")
	var/obj/item/reagent_containers/glass/beaker/noreact/N = allocate(/obj/item/reagent_containers/glass/beaker/noreact)
	TEST_ASSERT(N.flags & NOREACT, "the cryostasis beaker keeps its reactions off")
	var/obj/item/reagent_containers/glass/beaker/plain = allocate(/obj/item/reagent_containers/glass/beaker)
	TEST_ASSERT(!(plain.flags & NOREACT), "an ordinary beaker reacts")
	TEST_ASSERT_EQUAL(plain.get_rating(), 1, "the ordinary beaker's rating")
	var/obj/item/reagent_containers/glass/beaker/large/big = allocate(/obj/item/reagent_containers/glass/beaker/large)
	var/obj/item/reagent_containers/glass/beaker/bluespace/blue = allocate(/obj/item/reagent_containers/glass/beaker/bluespace)
	TEST_ASSERT_EQUAL(big.get_rating(), 3, "the large beaker's rating")
	TEST_ASSERT_EQUAL(blue.get_rating(), 5, "the bluespace beaker's rating")
	var/obj/item/reagent_containers/glass/beaker/vial/tiny = allocate(/obj/item/reagent_containers/glass/beaker/vial)
	TEST_ASSERT_EQUAL(tiny.w_class, ITEMSIZE_TINY, "a vial is tiny")
	TEST_ASSERT_EQUAL(plain.w_class, ITEMSIZE_SMALL, "a beaker is small")

// ---------------------------------------------------------------------------------------------------------------------
// The lid
// ---------------------------------------------------------------------------------------------------------------------

/// Using the container in hand puts its lid on and takes it off.
/datum/unit_test/dq_p2_reagents/lid_toggles_when_used_in_hand

/datum/unit_test/dq_p2_reagents/lid_toggles_when_used_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	for(var/path in list(/obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/bucket, /obj/item/reagent_containers/glass/kettle))
		var/obj/item/reagent_containers/C = rc_filled(path, 20)
		TEST_ASSERT(rc_open(C), "[path] starts open")
		rc_use(H, C)
		TEST_ASSERT(!rc_open(C), "[path]: using it puts the lid on")
		TEST_ASSERT_EQUAL(C.reagents.total_volume, 20, "[path]: and the contents are untouched")
		rc_use(H, C)
		TEST_ASSERT(rc_open(C), "[path]: using it again takes the lid off")

/// A closed container gives nothing: it does not pour, and does not splash.
/datum/unit_test/dq_p2_reagents/closed_container_neither_pours_nor_splashes

/datum/unit_test/dq_p2_reagents/closed_container_neither_pours_nor_splashes/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_use(H, C)
	TEST_ASSERT(!rc_open(C), "the lid is on")
	rc_click(H, target, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "a help-stance click does not pour")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 0, "nothing arrives")
	rc_click(H, target, C, I_HURT)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "a hostile click does not splash it either")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 0, "nothing arrives")
	var/turf/T = get_turf(H)
	rc_click(H, T, C, I_HURT)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "nor over the floor")

// ---------------------------------------------------------------------------------------------------------------------
// Pouring
// ---------------------------------------------------------------------------------------------------------------------

/// A click pours the amount set, no more than the source holds and no more than the target takes.
/datum/unit_test/dq_p2_reagents/pour_moves_the_set_amount_and_clamps

/datum/unit_test/dq_p2_reagents/pour_moves_the_set_amount_and_clamps/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/source = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 100)
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, target, source)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 90, "the first click gives the standard 10")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 10, "and the target has it")
	rc_set_amount_menu(H, source, 25)
	rc_click(H, target, source)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 65, "the amount set (25) leaves")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 35, "and arrives")
	rc_set_amount_menu(H, source, 60)
	rc_click(H, target, source)
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 60, "the target takes only what fits (25 of 60)")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 40, "and the source loses only that")
	rc_click(H, target, source)
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 60, "a full target takes nothing more")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 40, "and nothing leaves the source")
	var/obj/item/reagent_containers/small = rc_filled(/obj/item/reagent_containers/glass/beaker, 4)
	var/obj/item/reagent_containers/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, empty, small)
	TEST_ASSERT_EQUAL(empty.reagents.total_volume, 4, "a source with less than one transfer gives all it has")
	TEST_ASSERT_EQUAL(small.reagents.total_volume, 0, "and is empty")

/// An empty source, a closed target and a thing that holds no liquid are all refused: the state does not change.
/datum/unit_test/dq_p2_reagents/pour_refused_when_it_cannot_go

/datum/unit_test/dq_p2_reagents/pour_refused_when_it_cannot_go/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/source = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/obj/item/reagent_containers/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	var/obj/item/reagent_containers/closed = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_use(H, closed)
	var/obj/item/cell/cell = allocate(/obj/item/cell)
	rc_click(H, source, empty)
	TEST_ASSERT_EQUAL(empty.reagents.total_volume, 0, "an empty beaker held over a full one gives nothing")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 30, "and takes nothing from it")
	rc_click(H, closed, source)
	TEST_ASSERT_EQUAL(closed.reagents.total_volume, 0, "a closed target is not poured into")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 30, "and the source keeps its liquid")
	rc_click(H, cell, source)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 30, "a power cell holds no liquid: nothing leaves")

/// A hostile click still pours into an open container (it splashes only where it cannot pour).
/datum/unit_test/dq_p2_reagents/hostile_click_on_an_open_container_pours

/datum/unit_test/dq_p2_reagents/hostile_click_on_an_open_container_pours/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/source = rc_filled(/obj/item/reagent_containers/glass/beaker, 40)
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, target, source, I_HURT)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 30, "one transfer left the source, not all of it")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 10, "and it is in the target")

/// Surfaces a container is put on, and machines that take containers, are not poured into or splashed.
/datum/unit_test/dq_p2_reagents/containers_placed_on_things_are_not_poured

/datum/unit_test/dq_p2_reagents/containers_placed_on_things_are_not_poured/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/obj/structure/table/table = allocate(/obj/structure/table)
	rc_click(H, table, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "a help-stance click on a table keeps the liquid")
	rc_click(H, table, C, I_HURT)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "and so does a hostile one")
	var/obj/machinery/chemical_dispenser/dispenser = allocate(/obj/machinery/chemical_dispenser)
	rc_click(H, dispenser, C)
	TEST_ASSERT_EQUAL(dispenser.container, C, "a chemical dispenser takes the beaker as its container")
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "with its contents")

/// A bucket and the other containers pour as they are set: the same rules.
/datum/unit_test/dq_p2_reagents/bucket_pours_its_own_amount

/datum/unit_test/dq_p2_reagents/bucket_pours_its_own_amount/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/bucket = rc_filled(/obj/item/reagent_containers/glass/bucket, 100)
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	rc_click(H, target, bucket)
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 20, "a bucket pours 20 at a time")
	var/obj/item/reagent_containers/kettle = rc_filled(/obj/item/reagent_containers/glass/kettle, 30)
	var/obj/item/reagent_containers/cup = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, cup, kettle)
	TEST_ASSERT_EQUAL(cup.reagents.total_volume, 10, "a kettle pours 10 at a time")

// ---------------------------------------------------------------------------------------------------------------------
// Filling from a tank
// ---------------------------------------------------------------------------------------------------------------------

/// A container taps a closed tank for the tank's amount, whatever it is set to itself, until it is full or the tank is empty.
/datum/unit_test/dq_p2_reagents/filled_from_a_closed_tank_by_the_tanks_amount

/datum/unit_test/dq_p2_reagents/filled_from_a_closed_tank_by_the_tanks_amount/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	var/tank_before = tank.reagents.total_volume
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_set_amount_menu(H, C, 5)
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 10, "the tank gave its own 10, not the beaker's 5")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before - 10, "from the tank")
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 20, "a beaker with something in it still draws")
	C.reagents.add_reagent(REAGENT_ID_WATER, 35)
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 60, "it stops at the brim: only what fits comes out (5 of the 10)")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before - 25, "and the tank lost only that (10 + 10 + 5)")
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 60, "a full container takes nothing")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before - 25, "and the tank keeps its water")
	tank.reagents.clear_reagents()
	var/obj/item/reagent_containers/other = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, tank, other)
	TEST_ASSERT_EQUAL(other.reagents.total_volume, 0, "an empty tank gives nothing")

/// A hostile click draws from a closed tank too; a tank with its top open is poured into.
/datum/unit_test/dq_p2_reagents/open_tank_is_poured_into_and_closed_tank_is_tapped

/datum/unit_test/dq_p2_reagents/open_tank_is_poured_into_and_closed_tank_is_tapped/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	var/tank_before = tank.reagents.total_volume
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, tank, C, I_HURT)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 10, "a hostile click taps the closed tank as well (ran [rc_last_click?.key] [rc_last_click?.outcome] [rc_last_click?.reason])")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before - 10, "taking its water")
	rc_alt_click(H, tank, null)
	TEST_ASSERT(tank.open_top, "an alt-click opens the tank's top")
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 0, "now a click pours the container into the tank")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before, "which has its water back")
	var/obj/item/reagent_containers/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, tank, empty)
	TEST_ASSERT_EQUAL(empty.reagents.total_volume, 0, "an open tank is not tapped")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before, "and loses nothing")

// ---------------------------------------------------------------------------------------------------------------------
// Splashing
// ---------------------------------------------------------------------------------------------------------------------

/// A hostile click splashes the container's contents over an object or the floor: it ends up with less than it had (a splash spills some of
/// it on the floor first, by chance), and an empty one splashes nothing.
/datum/unit_test/dq_p2_reagents/hostile_click_splashes_over_things

/datum/unit_test/dq_p2_reagents/hostile_click_splashes_over_things/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/D = rc_filled(/obj/item/reagent_containers/glass/beaker, 40)
	var/obj/item/p2_reagent_probe/probe = allocate(/obj/item/p2_reagent_probe)
	rc_click(H, probe, D, I_HURT)
	TEST_ASSERT(D.reagents.total_volume < 40, "an object splashed with it: the beaker is down to [D.reagents.total_volume] (not one transfer's 10 less, a splash)")
	TEST_ASSERT(D.reagents.total_volume < 30, "more than one transfer left it")
	var/obj/item/reagent_containers/E = rc_filled(/obj/item/reagent_containers/glass/beaker, 40)
	var/turf/T = get_turf(H)
	rc_click(H, T, E, I_HURT)
	TEST_ASSERT(E.reagents.total_volume < 30, "the floor splashed with it: more than one transfer left it")
	var/obj/item/reagent_containers/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, probe, empty, I_HURT)
	TEST_ASSERT_EQUAL(empty.reagents.total_volume, 0, "an empty container splashes nothing")
	var/obj/item/reagent_containers/closed_target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_use(H, closed_target)
	var/obj/item/reagent_containers/F = rc_filled(/obj/item/reagent_containers/glass/beaker, 25)
	rc_click(H, closed_target, F, I_HURT)
	TEST_ASSERT(F.reagents.total_volume < 25, "a closed container is splashed like any thing: the beaker gives up more than nothing")

/// A hostile click on a person does nothing with an open container: the attack handler takes the click, and the old splash of a person
/// (and of yourself) is never reached. A help click feeds instead (tested below).
/datum/unit_test/dq_p2_reagents/hostile_click_on_a_person_splashes_them

/datum/unit_test/dq_p2_reagents/hostile_click_on_a_person_splashes_them/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/victim = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 40)
	var/before = victim.ingested.total_volume
	rc_click(H, victim, C, I_HURT)
	TEST_ASSERT(C.reagents.total_volume < 40, "a person clicked in a hostile stance is splashed: the beaker loses some")
	TEST_ASSERT_EQUAL(victim.ingested.total_volume, before, "and nobody swallows anything")

// ---------------------------------------------------------------------------------------------------------------------
// Drinking and feeding
// ---------------------------------------------------------------------------------------------------------------------

/// A click on yourself drinks one transfer, and it goes into the stomach (ingested), not the blood.
/datum/unit_test/dq_p2_reagents/drinking_from_a_beaker

/datum/unit_test/dq_p2_reagents/drinking_from_a_beaker/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/blood_before = H.reagents.total_volume
	var/ingested_before = H.ingested.total_volume
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 20, "a click on yourself drinks the standard 10")
	TEST_ASSERT_EQUAL(H.ingested.total_volume - ingested_before, 10, "into the stomach")
	TEST_ASSERT_EQUAL(H.reagents.total_volume, blood_before, "and not the blood")
	rc_set_amount_menu(H, C, 4)
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 16, "the amount set (4) is drunk next")
	var/obj/item/reagent_containers/few = rc_filled(/obj/item/reagent_containers/glass/beaker, 3)
	rc_click(H, H, few, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(few.reagents.total_volume, 0, "a drink of less than a transfer takes what there is")
	var/obj/item/reagent_containers/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	var/before = H.ingested.total_volume
	rc_click(H, H, empty, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(H.ingested.total_volume, before, "an empty beaker gives nothing to drink")

/// A drink needs a mouth that is free, and a container that is not closed.
/datum/unit_test/dq_p2_reagents/drinking_refused_by_a_mask_or_a_lid

/datum/unit_test/dq_p2_reagents/drinking_refused_by_a_mask_or_a_lid/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	H.equip_to_slot_or_del(mask, SLOT_ID_MASK)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_MASK), mask, "the person wears a gas mask")
	var/before = H.ingested.total_volume
	rc_click(H, H, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "a mask over the mouth refuses the drink")
	TEST_ASSERT_EQUAL(H.ingested.total_volume, before, "and nothing is swallowed")
	H.unEquip(mask)
	rc_use(H, C)
	TEST_ASSERT(!rc_open(C), "with the lid on")
	rc_click(H, H, C)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "a closed beaker is not drunk from")
	TEST_ASSERT_EQUAL(H.ingested.total_volume, before, "and nothing is swallowed")

/// Feeding someone else takes three seconds, is given to them when the time is up, and stops if the feeder goes away.
/datum/unit_test/dq_p2_reagents/feeding_another_takes_three_seconds

/datum/unit_test/dq_p2_reagents/feeding_another_takes_three_seconds/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	var/before = patient.ingested.total_volume
	H.drop_item()
	H.put_in_active_hand(C)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, patient, null, null, "left=1"))
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(patient.ingested.total_volume, before, "nothing is given in the first two seconds")
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 30, "and the beaker is untouched")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(patient.ingested.total_volume - before, 10, "when the time is up the patient has swallowed one transfer")
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 20, "from the beaker")
	var/swallowed = patient.ingested.total_volume
	// the feeder walks away before the end
	var/turf/far = locate(run_loc_floor_top_right.x, run_loc_floor_top_right.y, run_loc_floor_top_right.z)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, patient, null, null, "left=1"))
	test_time(1 SECONDS)
	H.forceMove(far)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(C.reagents.total_volume, 20, "a feeder who walks away has given nothing")
	TEST_ASSERT(patient.ingested.total_volume <= swallowed, "and the patient has no more than before")

/// A closed container clicked on a creature milks its venom, once in a while.
/datum/unit_test/dq_p2_reagents/closed_container_milks_venom

/datum/unit_test/dq_p2_reagents/closed_container_milks_venom/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/snake = rc_actor()
	snake.trait_injection_selected = REAGENT_ID_TOXIN
	snake.trait_injection_amount = 7
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, snake, C)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 0, "an open beaker does not milk")
	rc_use(H, C)
	TEST_ASSERT(!rc_open(C), "with the lid on")
	rc_click(H, snake, C)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 7, "the venom comes into the beaker")
	rc_click(H, snake, C)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 7, "a second try at once gives nothing more")
	rc_milk_cooldown_over(snake)
	rc_click(H, snake, C)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 14, "after the time has passed it gives again")
	var/mob/living/carbon/human/plain = rc_actor()
	rc_click(H, plain, C)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 14, "a creature with no venom gives none")

// ---------------------------------------------------------------------------------------------------------------------
// The amount
// ---------------------------------------------------------------------------------------------------------------------

/// The amount is set from the menu and by an alt-click; each container keeps its own.
/datum/unit_test/dq_p2_reagents/set_the_amount_by_menu_and_by_alt_click

/datum/unit_test/dq_p2_reagents/set_the_amount_by_menu_and_by_alt_click/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/A = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	var/obj/item/reagent_containers/B = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	rc_set_amount_menu(H, A, 40)
	TEST_ASSERT_EQUAL(rc_amount(A), 40, "the menu sets the amount")
	TEST_ASSERT_EQUAL(rc_amount(B), 10, "and another beaker keeps its own")
	rc_alt_set_amount(H, A, null, 1)
	TEST_ASSERT_EQUAL(rc_amount(A), 1, "the alt-click sets the smallest amount")
	rc_alt_set_amount(H, A, null, 120)
	TEST_ASSERT_EQUAL(rc_amount(A), 120, "and the largest")
	var/obj/item/reagent_containers/bucket = rc_filled(/obj/item/reagent_containers/glass/bucket, 0)
	rc_set_amount_menu(H, bucket, 33)
	TEST_ASSERT_EQUAL(rc_amount(bucket), 33, "any whole amount in range works: a bucket takes 33")

/// Alt-clicking the container in hand asks for the amount through the real input.
/datum/unit_test/dq_p2_reagents/alt_click_in_hand_asks_for_the_amount

/datum/unit_test/dq_p2_reagents/alt_click_in_hand_asks_for_the_amount/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_alt_set_amount(H, C, C, 22)
	TEST_ASSERT_EQUAL(rc_amount(C), 22, "the alt-click on the beaker in hand sets what was answered")

// ---------------------------------------------------------------------------------------------------------------------
// Examine
// ---------------------------------------------------------------------------------------------------------------------

/// What a person reads when they look: what is in it, and that the lid is on.
/datum/unit_test/dq_p2_reagents/examine_says_what_is_inside_and_the_lid

/datum/unit_test/dq_p2_reagents/examine_says_what_is_inside_and_the_lid/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	var/text = jointext(C.examine(H), "\n")
	TEST_ASSERT(findtext(text, "empty"), "an empty beaker says it is empty")
	C.reagents.add_reagent(REAGENT_ID_WATER, 37)
	text = jointext(C.examine(H), "\n")
	TEST_ASSERT(findtext(text, "37"), "a beaker with 37 units says so")
	TEST_ASSERT(!findtext(text, "lid") && !findtext(text, "Airtight"), "an open beaker says nothing of a lid")
	rc_use(H, C)
	text = jointext(C.examine(H), "\n")
	TEST_ASSERT(findtext(text, "lid") || findtext(text, "Airtight"), "a closed beaker says its lid is on")
	var/mob/living/carbon/human/far_away = rc_actor(run_loc_floor_top_right)
	var/far_text = jointext(C.examine(far_away), "\n")
	TEST_ASSERT(!findtext(far_text, "37"), "from far away the contents are not read")

// ---------------------------------------------------------------------------------------------------------------------
// Labels, dips and the look
// ---------------------------------------------------------------------------------------------------------------------

/// A pen on a beaker labels it: the name carries the label, long ones are cut, over-long ones are refused, an empty one clears it.
/datum/unit_test/dq_p2_reagents/labelling_with_a_pen

/datum/unit_test/dq_p2_reagents/labelling_with_a_pen/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/C = allocate(/obj/item/reagent_containers/glass/beaker)
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	var/base = C.name
	rc_label_with_pen(H, C, pen, "acid")
	TEST_ASSERT_EQUAL(rc_label(C), "acid", "the label is what was written")
	TEST_ASSERT_EQUAL(C.name, "[base] (acid)", "the name carries it")
	TEST_ASSERT(findtext(C.desc, "acid"), "and so does the description")
	rc_label_with_pen(H, C, pen, "a label that is longer than twenty letters")
	TEST_ASSERT_EQUAL(C.name, "[base] (a label that is long...)", "a long label is cut to twenty letters in the name")
	rc_label_with_pen(H, C, pen, "x" + repeat_string_p2("y", 60))
	TEST_ASSERT_EQUAL(C.name, "[base] (a label that is long...)", "a label over fifty letters is refused and the old one stays")
	rc_label_with_pen(H, C, pen, "")
	TEST_ASSERT(!length(rc_label(C)), "an empty label clears the label")

/proc/repeat_string_p2(text, n)
	. = ""
	for(var/i in 1 to n)
		. += text

/// A small thing dipped into an open container is wetted by what is in it, in a hostile, disarm or grab stance; a help click only labels.
/datum/unit_test/dq_p2_reagents/dipping_things_into_a_container

/datum/unit_test/dq_p2_reagents/dipping_things_into_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/C = rc_filled(/obj/item/reagent_containers/glass/beaker, 50)
	var/obj/item/p2_reagent_probe/probe = allocate(/obj/item/p2_reagent_probe)
	rc_click(H, C, probe, I_HELP)
	TEST_ASSERT_EQUAL(probe.wetness, 0, "a help-stance click does not dip")
	rc_click(H, C, probe, I_HURT)
	TEST_ASSERT(probe.wetness > 0, "a hostile click dips the item into it")
	var/after_hurt = probe.wetness
	rc_click(H, C, probe, I_GRAB)
	TEST_ASSERT(probe.wetness > after_hurt, "so does a grab click")
	rc_use(H, C)
	var/closed_wetness = probe.wetness
	rc_click(H, C, probe, I_HURT)
	TEST_ASSERT_EQUAL(probe.wetness, closed_wetness, "a closed container is not dipped into")

/// The fill gauge and the lid are drawn as the container is.
/datum/unit_test/dq_p2_reagents/beaker_look_follows_fill_lid_and_label

/datum/unit_test/dq_p2_reagents/beaker_look_follows_fill_lid_and_label/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/C = allocate(/obj/item/reagent_containers/glass/beaker)
	TEST_ASSERT_EQUAL(length(rc_overlays(C)), 0, "an empty open beaker draws nothing over itself")
	C.reagents.add_reagent(REAGENT_ID_WATER, 6)
	TEST_ASSERT(("beaker-10" in rc_overlays(C)), "10% is the first step")
	C.reagents.add_reagent(REAGENT_ID_WATER, 24)
	TEST_ASSERT(("beaker-40" in rc_overlays(C)), "50% is the 40 step")
	C.reagents.add_reagent(REAGENT_ID_WATER, 30)
	TEST_ASSERT(("beaker-80" in rc_overlays(C)), "full is drawn as the 80 step (the 100 step is out of reach, as it has always been)")
	rc_use(H, C)
	TEST_ASSERT(("lid_beaker" in rc_overlays(C)), "the lid is drawn while it is on")
	rc_use(H, C)
	TEST_ASSERT(!("lid_beaker" in rc_overlays(C)), "and not once it is off")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	rc_label_with_pen(H, C, pen, "acid")
	TEST_ASSERT(("label_beaker" in rc_overlays(C)), "a label is drawn")

// ---------------------------------------------------------------------------------------------------------------------
// Buckets
// ---------------------------------------------------------------------------------------------------------------------

/// A mop, a bar of soap or a rag is wetted from a bucket, 5 units at a time, while the bucket has water.
/datum/unit_test/dq_p2_reagents/bucket_wets_a_mop

/datum/unit_test/dq_p2_reagents/bucket_wets_a_mop/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/bucket = rc_filled(/obj/item/reagent_containers/glass/bucket, 100)
	var/obj/item/mop/mop = allocate(/obj/item/mop)
	rc_click(H, bucket, mop)
	TEST_ASSERT_EQUAL(bucket.reagents.total_volume, 95, "the bucket gave 5")
	TEST_ASSERT_EQUAL(mop.reagents.total_volume, 5, "to the mop")
	var/obj/item/reagent_containers/dry = rc_filled(/obj/item/reagent_containers/glass/bucket, 0)
	var/obj/item/mop/other = allocate(/obj/item/mop)
	rc_click(H, dry, other)
	TEST_ASSERT_EQUAL(other.reagents.total_volume, 0, "an empty bucket wets nothing")

/// A proximity sensor makes a bucket into a bucket sensor; a sheet of steel into the start of a robot; wire cutters into a helmet.
/datum/unit_test/dq_p2_reagents/bucket_is_made_into_other_things

/datum/unit_test/dq_p2_reagents/bucket_is_made_into_other_things/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/turf/T = get_turf(H)
	var/obj/item/reagent_containers/glass/bucket/first = rc_filled(/obj/item/reagent_containers/glass/bucket, 0)
	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor)
	rc_click(H, first, prox)
	TEST_ASSERT(QDELETED(first), "the bucket is used up making the sensor")
	TEST_ASSERT(QDELETED(prox), "and so is the proximity sensor")
	var/found = FALSE
	for(var/obj/item/bucket_sensor/S in contents_of(T) + H.contents)
		found = TRUE
		qdel(S)
	TEST_ASSERT(found, "a bucket sensor was made")
	var/obj/item/reagent_containers/glass/bucket/second = rc_filled(/obj/item/reagent_containers/glass/bucket, 0)
	var/obj/item/stack/material/steel/steel = allocate(/obj/item/stack/material/steel)
	steel.set_amount(2)
	rc_click(H, second, steel)
	TEST_ASSERT_EQUAL(steel.get_amount(), 1, "a sheet of steel was spent")
	TEST_ASSERT(QDELETED(second), "and the bucket went into the frame")
	var/obj/item/reagent_containers/glass/bucket/third = rc_filled(/obj/item/reagent_containers/glass/bucket, 0)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	rc_click(H, third, cutters)
	TEST_ASSERT(QDELETED(third), "wire cutters cut the bucket into a helmet")
	var/helmets = 0
	for(var/obj/item/clothing/head/helmet/bucket/B in contents_of(T) + H.contents)
		helmets++
	TEST_ASSERT_EQUAL(helmets, 1, "a bucket helmet was made")

/// The wooden bucket: no electronics, a hatchet makes a helmet, a mop is wetted, and a wirecutter does nothing.
/datum/unit_test/dq_p2_reagents/wooden_bucket_is_its_own

/datum/unit_test/dq_p2_reagents/wooden_bucket_is_its_own/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/turf/T = get_turf(H)
	var/obj/item/reagent_containers/glass/bucket/wood/wood = rc_filled(/obj/item/reagent_containers/glass/bucket/wood, 100)
	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor)
	rc_click(H, wood, prox)
	TEST_ASSERT(!QDELETED(wood) && !QDELETED(prox), "a wooden bucket does not play well with electronics")
	var/obj/item/mop/mop = allocate(/obj/item/mop)
	rc_click(H, wood, mop)
	TEST_ASSERT_EQUAL(mop.reagents.total_volume, 5, "a mop is wetted from it")
	var/obj/item/material/knife/machete/hatchet/hatchet = allocate(/obj/item/material/knife/machete/hatchet)
	rc_click(H, wood, hatchet)
	TEST_ASSERT(QDELETED(wood), "a hatchet cuts it into a helmet")
	var/helmets = 0
	for(var/obj/item/clothing/head/helmet/bucket/wood/B in contents_of(T) + H.contents)
		helmets++
	TEST_ASSERT_EQUAL(helmets, 1, "a wooden bucket helmet was made")

// ---------------------------------------------------------------------------------------------------------------------
// The containers that inherit from the glass
// ---------------------------------------------------------------------------------------------------------------------

/// A paint can paints a floor with 5 units while it has more than 5, and otherwise is poured as a container.
/datum/unit_test/dq_p2_reagents/paint_can_paints_the_floor

/datum/unit_test/dq_p2_reagents/paint_can_paints_the_floor/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/paint/red/can = allocate(/obj/item/reagent_containers/glass/paint/red)
	var/start = can.reagents.total_volume
	TEST_ASSERT(start > 5, "a new can holds paint")
	var/turf/T = get_turf(H)
	rc_click(H, T, can)
	TEST_ASSERT_EQUAL(can.reagents.total_volume, start - 5, "a click on the floor spends 5 units")
	rc_click(H, T, can, I_HURT)
	TEST_ASSERT_EQUAL(can.reagents.total_volume, start - 10, "so does a hostile click (not the whole can)")
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, target, can)
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 10, "a click on another container pours the usual amount")

/// A rag wrings itself out over an open container (in a while, by how wet it is), and soaks from a bucket: its own rules, not a container's.
/datum/unit_test/dq_p2_reagents/rag_is_not_poured

/datum/unit_test/dq_p2_reagents/rag_is_not_poured/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/rag = allocate(/obj/item/reagent_containers/glass/rag)
	rag.reagents.add_reagent(REAGENT_ID_WATER, 5)
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, target, rag, I_HELP, FALSE)
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rag.reagents.total_volume, 5, "a rag held over a beaker does not pour at once")
	rc_settle()
	TEST_ASSERT_EQUAL(rag.reagents.total_volume, 0, "it is wrung out in a while")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 5, "into the beaker")
	var/obj/item/reagent_containers/bucket = rc_filled(/obj/item/reagent_containers/glass/bucket, 50)
	var/obj/item/reagent_containers/glass/rag/dry = allocate(/obj/item/reagent_containers/glass/rag)
	rc_click(H, bucket, dry)
	TEST_ASSERT_EQUAL(dry.reagents.total_volume, dry.reagents.maximum_volume, "a dry rag put to a bucket soaks it full")
	TEST_ASSERT_EQUAL(bucket.reagents.total_volume, 50 - dry.reagents.maximum_volume, "from the bucket")

/// A rag says what it holds when it is looked at from close by.
/datum/unit_test/dq_p2_reagents/rag_examine_says_what_is_in_it

/datum/unit_test/dq_p2_reagents/rag_examine_says_what_is_in_it/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/rag = allocate(/obj/item/reagent_containers/glass/rag)
	TEST_ASSERT(findtext(jointext(rag.examine(H), "\n"), "empty"), "a dry rag says it is empty")
	rag.reagents.add_reagent(REAGENT_ID_WATER, 4)
	TEST_ASSERT(findtext(jointext(rag.examine(H), "\n"), "4"), "a damp one says how much it holds")

/// An empty hand clicking a container on the floor picks it up.
/datum/unit_test/dq_p2_reagents/an_empty_hand_picks_a_container_up

/datum/unit_test/dq_p2_reagents/an_empty_hand_picks_a_container_up/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	for(var/path in list(/obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/glass/bucket, /obj/item/reagent_containers/glass/bottle))
		var/obj/item/reagent_containers/C = rc_filled(path, 20)
		rc_click(H, C, null)
		TEST_ASSERT_EQUAL(H.get_active_hand(), C, "[path]: an empty hand picks it up")
		TEST_ASSERT_EQUAL(C.reagents.total_volume, 20, "[path]: and what is in it stays")

/// A bottle is a glass container with a lid that keeps its name and look.
/datum/unit_test/dq_p2_reagents/bottle_is_a_container

/datum/unit_test/dq_p2_reagents/bottle_is_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/bottle/bottle = rc_filled(/obj/item/reagent_containers/glass/bottle, 40)
	TEST_ASSERT_EQUAL(rc_capacity(bottle), 60, "a bottle holds 60")
	TEST_ASSERT_EQUAL(rc_amount(bottle), 10, "and pours 10")
	var/obj/item/reagent_containers/target = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	TEST_ASSERT(!rc_open(bottle), "a bottle starts without its stopper off")
	rc_use(H, bottle)
	TEST_ASSERT(rc_open(bottle), "using it takes it off")
	rc_click(H, target, bottle)
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 10, "and it pours")
