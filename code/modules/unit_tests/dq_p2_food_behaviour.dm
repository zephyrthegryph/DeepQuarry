// Behaviour-preservation tests for food containers (phase 2, food, step 1): condiment bottles, shakers, packets and cartons, and the cooking
// containers of the oven, fryer and grill (dishes, baskets, racks). They use the base and the click helpers of dq_p2_reagent_behaviour.dm.
//
// Rules the tests keep: input goes through the click helpers and the adapter block below, which is the only place that names today's accessors; every
// input is followed by a settle; nothing depends on message text or on an op key.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The person sets the amount of a condiment from the context menu, giving `value` when asked.
/proc/fd_set_amount_menu(mob/actor, obj/item/reagent_containers/C, value)
	GLOB.om_rerun_answers["[REF(C)]:reagent_container_verb_set_transfer"] = list("a1" = value)
	C.reagent_container_verb_set_transfer(actor, null, null)
	GLOB.om_rerun_answers -= "[REF(C)]:reagent_container_verb_set_transfer"

/// The person sets the amount of a condiment by alt-clicking it, giving `value` when asked.
/proc/fd_set_amount_alt(mob/actor, obj/item/reagent_containers/C, value)
	GLOB.om_rerun_answers["[REF(C)]:transfer_amount_alt"] = list("a2" = value)
	C.transfer_amount_alt(actor, null, null)
	GLOB.om_rerun_answers -= "[REF(C)]:transfer_amount_alt"

/// The icon states of the overlays a condiment carton draws now, as plain text.
/proc/fd_overlays(obj/item/reagent_containers/food/condiment/C)
	. = list()
	for(var/entry in C.appearance_overlays())
		if(isicon(entry))
			continue
		if(istext(entry))
			. += entry
		else
			var/image/I = entry
			. += I.icon_state

/// The person empties a cooking container from the context menu.
/proc/fd_empty_menu(mob/actor, obj/item/reagent_containers/cooking_container/C)
	C.cooking_container_verb_empty(actor, null, null)

/// The solid things in a cooking container.
/proc/fd_solids(obj/item/reagent_containers/cooking_container/C)
	. = list()
	for(var/obj/O in C.contents)
		. += O

/// The people-visible icon states of a cooking container's overlays.
/proc/fd_cooking_overlays(obj/item/reagent_containers/cooking_container/C)
	. = list()
	for(var/entry in C.appearance_overlays())
		if(isicon(entry))
			continue
		if(istext(entry))
			. += entry
		else
			var/image/I = entry
			. += I.icon_state

/datum/unit_test/dq_p2_reagents/proc/fd_condiment(type = /obj/item/reagent_containers/food/condiment/ketchup, turf/T)
	return allocate(type, T || run_loc_floor_bottom_left)

// ---------------------------------------------------------------------------------------------------------------------
// Condiments: what they are
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/condiments_start_as_declared

/datum/unit_test/dq_p2_reagents/condiments_start_as_declared/run_gate()
	var/list/expected = list(
		// type, volume, first amount, smallest, largest, contents id, contents units
		list(/obj/item/reagent_containers/food/condiment/ketchup, 50, 2, 1, 10, REAGENT_ID_KETCHUP, 50),
		list(/obj/item/reagent_containers/food/condiment/small/saltshaker, 20, 1, 1, 20, REAGENT_ID_SODIUMCHLORIDE, 20),
		list(/obj/item/reagent_containers/food/condiment/small/peppergrinder, 20, 1, 1, 20, REAGENT_ID_BLACKPEPPER, 20),
		list(/obj/item/reagent_containers/food/condiment/small/packet/salt, 5, 1, 1, 5, REAGENT_ID_SODIUMCHLORIDE, 5),
		list(/obj/item/reagent_containers/food/condiment/small/packet/jelly, 10, 1, 1, 5, REAGENT_ID_CHERRYJELLY, 10),
		list(/obj/item/reagent_containers/food/condiment/carton/flour, 220, 5, 1, 10, REAGENT_ID_FLOUR, 200),
		list(/obj/item/reagent_containers/food/condiment/carton/sugar, 120, 5, 1, 10, REAGENT_ID_SUGAR, 100),
		list(/obj/item/reagent_containers/food/condiment/spacespice, 40, 1, 1, 40, REAGENT_ID_SPACESPICE, 40),
		list(/obj/item/reagent_containers/food/condiment/enzyme, 50, 2, 1, 10, REAGENT_ID_ENZYME, 50),
	)
	for(var/list/row in expected)
		var/path = row[1]
		var/obj/item/reagent_containers/food/condiment/C = fd_condiment(path)
		TEST_ASSERT_EQUAL(rc_capacity(C), row[2], "[path]: capacity")
		TEST_ASSERT_EQUAL(rc_amount(C), row[3], "[path]: the first transfer amount")
		var/list/range = rc_amount_range(C)
		TEST_ASSERT_EQUAL(range[1], row[4], "[path]: the smallest amount")
		TEST_ASSERT_EQUAL(range[2], row[5], "[path]: the largest amount")
		TEST_ASSERT(rc_open(C), "[path]: an open container")
		TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(row[6]), row[7], "[path]: what it holds")

/// An empty bottle is a plain bottle.
/datum/unit_test/dq_p2_reagents/empty_condiment_is_a_plain_bottle

/datum/unit_test/dq_p2_reagents/empty_condiment_is_a_plain_bottle/run_gate()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment(/obj/item/reagent_containers/food/condiment)
	TEST_ASSERT_EQUAL(rc_units(C), 0, "it starts empty")
	TEST_ASSERT_EQUAL(C.name, "Condiment Container", "its mapped name stays until it holds something")
	C.reagents.add_reagent(REAGENT_ID_KETCHUP, 10)
	TEST_ASSERT_EQUAL(C.name, REAGENT_KETCHUP, "ketchup names it")
	TEST_ASSERT_EQUAL(C.icon_state, "ketchup", "and draws it")
	C.reagents.clear_reagents()
	TEST_ASSERT_EQUAL(C.name, "Condiment Bottle", "emptied, it is a bottle again")
	TEST_ASSERT_EQUAL(C.icon_state, "emptycondiment", "and draws empty")

/// A bottle is named for its main reagent, and a mix says it is a mix.
/datum/unit_test/dq_p2_reagents/condiment_is_named_for_its_contents

/datum/unit_test/dq_p2_reagents/condiment_is_named_for_its_contents/run_gate()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment(/obj/item/reagent_containers/food/condiment)
	var/list/expected = list(
		list(REAGENT_ID_MUSTARD, REAGENT_MUSTARD, "mustard"),
		list(REAGENT_ID_CAPSAICIN, "Hotsauce", "hotsauce"),
		list(REAGENT_ID_SODIUMCHLORIDE, "Salt Shaker", "saltshaker"),
		list(REAGENT_ID_SOYSAUCE, REAGENT_SOYSAUCE, "soysauce"),
		list(REAGENT_ID_FROSTOIL, "Coldsauce", "coldsauce"),
		list(REAGENT_ID_BARBECUE, "barbecue sauce", "barbecue"),
		list(REAGENT_ID_SPACESPICE, "bottle of space spice", "spacespicebottle"),
	)
	for(var/list/row in expected)
		C.reagents.clear_reagents()
		C.reagents.add_reagent(row[1], 10)
		TEST_ASSERT_EQUAL(C.name, row[2], "[row[1]]: the name")
		TEST_ASSERT_EQUAL(C.icon_state, row[3], "[row[1]]: the icon")
	C.reagents.clear_reagents()
	C.reagents.add_reagent(REAGENT_ID_WATER, 10)
	TEST_ASSERT_EQUAL(C.name, "Misc Condiment Bottle", "anything else is a misc bottle")
	TEST_ASSERT_EQUAL(C.icon_state, "mixedcondiments", "drawn as mixed")
	C.reagents.add_reagent(REAGENT_ID_SUGAR, 5)
	TEST_ASSERT_EQUAL(C.icon_state, "mixedcondiments", "and a mix stays one")

/// The small shakers, packets and the spice bottle keep their own names whatever they hold.
/datum/unit_test/dq_p2_reagents/small_condiments_keep_their_names

/datum/unit_test/dq_p2_reagents/small_condiments_keep_their_names/run_gate()
	var/obj/item/reagent_containers/food/condiment/small/saltshaker/S = fd_condiment(/obj/item/reagent_containers/food/condiment/small/saltshaker)
	S.reagents.clear_reagents()
	S.reagents.add_reagent(REAGENT_ID_KETCHUP, 5)
	TEST_ASSERT_EQUAL(S.name, "salt shaker", "a salt shaker stays one")
	TEST_ASSERT_EQUAL(S.icon_state, "saltshakersmall", "and keeps its icon")
	var/obj/item/reagent_containers/food/condiment/spacespice/spice = fd_condiment(/obj/item/reagent_containers/food/condiment/spacespice)
	spice.reagents.clear_reagents()
	TEST_ASSERT_EQUAL(spice.name, "space spices", "so does the spice bottle")

/// A carton draws a fill level by quarters, and none when it is empty.
/datum/unit_test/dq_p2_reagents/carton_draws_its_fill

/datum/unit_test/dq_p2_reagents/carton_draws_its_fill/run_gate()
	var/obj/item/reagent_containers/food/condiment/carton/flour/C = fd_condiment(/obj/item/reagent_containers/food/condiment/carton/flour)
	TEST_ASSERT(("flour-100" in fd_overlays(C)), "a nearly full carton draws its top level: [json_encode(fd_overlays(C))]")
	C.reagents.remove_any(100)
	TEST_ASSERT(("flour-50" in fd_overlays(C)), "about half draws half: [json_encode(fd_overlays(C))]")
	C.reagents.clear_reagents()
	TEST_ASSERT_EQUAL(length(fd_overlays(C)), 0, "an empty one draws nothing")

// ---------------------------------------------------------------------------------------------------------------------
// Condiments: sipping, feeding, pouring, filling, adding to food
// ---------------------------------------------------------------------------------------------------------------------

/// A click on yourself: one transfer into the stomach, in every stance (a condiment does no harm).
/datum/unit_test/dq_p2_reagents/condiment_is_swallowed

/datum/unit_test/dq_p2_reagents/condiment_is_swallowed/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/before = rc_stomach_units(H)
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(C), 48, "one transfer of 2 left the bottle")
	TEST_ASSERT(rc_stomach_units(H) > before, "and is in the stomach")
	for(var/stance in list(I_DISARM, I_GRAB, I_HURT))
		var/units = rc_units(C)
		rc_click(H, H, C, stance, FALSE)
		TEST_ASSERT_EQUAL(rc_units(C), units - 2, "a sip in the [stance] stance too")

/// The amount set is what a sip is.
/datum/unit_test/dq_p2_reagents/condiment_sip_follows_the_set_amount

/datum/unit_test/dq_p2_reagents/condiment_sip_follows_the_set_amount/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	fd_set_amount_menu(H, C, 7)
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(C), 43, "a sip of 7")
	fd_set_amount_alt(H, C, 3)
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(C), 40, "an alt-click set it to 3")

/// Somebody else is fed after three seconds.
/datum/unit_test/dq_p2_reagents/condiment_is_fed_to_another

/datum/unit_test/dq_p2_reagents/condiment_is_fed_to_another/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/before = rc_stomach_units(patient)
	rc_click(H, patient, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(C), 50, "nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(C), 50, "nor after a second")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(C), 48, "after the wait the patient has had a sip")
	TEST_ASSERT(rc_stomach_units(patient) > before, "into the stomach")

/// A mask over the mouth, or an empty bottle, stops a sip.
/datum/unit_test/dq_p2_reagents/condiment_is_stopped_by_a_mask_or_nothing

/datum/unit_test/dq_p2_reagents/condiment_is_stopped_by_a_mask_or_nothing/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	TEST_ASSERT(H.equip_to_slot_if_possible(mask, SLOT_ID_MASK), "a mask is worn")
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(C), 50, "nothing is swallowed through a mask")
	var/mob/living/carbon/human/other = rc_actor()
	var/obj/item/reagent_containers/food/condiment/empty = fd_condiment(/obj/item/reagent_containers/food/condiment)
	var/before = rc_stomach_units(other)
	rc_click(other, other, empty, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_stomach_units(other), before, "an empty bottle gives nothing")

/// An open container is poured into by the set amount, clamped to what the target takes.
/datum/unit_test/dq_p2_reagents/condiment_is_poured_into_a_container

/datum/unit_test/dq_p2_reagents/condiment_is_poured_into_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, C)
	TEST_ASSERT_EQUAL(rc_units(B), 2, "the beaker has the 2")
	TEST_ASSERT_EQUAL(rc_units(C), 48, "and the bottle lost them")
	var/obj/item/reagent_containers/glass/beaker/vial/V = rc_filled(/obj/item/reagent_containers/glass/beaker/vial, 29)
	rc_click(H, V, C)
	TEST_ASSERT_EQUAL(rc_units(V), 30, "a nearly full vial takes only what fits")
	TEST_ASSERT_EQUAL(rc_units(C), 47, "and the bottle gives only that")
	rc_click(H, V, C)
	TEST_ASSERT_EQUAL(rc_units(C), 47, "a full one takes nothing")
	var/obj/item/reagent_containers/food/condiment/empty = fd_condiment(/obj/item/reagent_containers/food/condiment)
	rc_click(H, B, empty)
	TEST_ASSERT_EQUAL(rc_units(B), 2, "an empty bottle gives nothing")

/// A hostile click on an open container pours too.
/datum/unit_test/dq_p2_reagents/condiment_hostile_click_pours

/datum/unit_test/dq_p2_reagents/condiment_hostile_click_pours/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, C, I_HURT)
	TEST_ASSERT_EQUAL(rc_units(B), 2, "the beaker has the 2")

/// A tank with its top shut fills a bottle by the tank's own amount.
/datum/unit_test/dq_p2_reagents/condiment_is_filled_from_a_tank

/datum/unit_test/dq_p2_reagents/condiment_is_filled_from_a_tank/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment(/obj/item/reagent_containers/food/condiment)
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(rc_units(C), tank.amount_per_transfer_from_this, "the bottle is filled by the tank's amount")

/// A condiment adds what it holds to a solid food (which is not an open container), by the set amount.
/datum/unit_test/dq_p2_reagents/condiment_is_added_to_food

/datum/unit_test/dq_p2_reagents/condiment_is_added_to_food/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/food = allocate(/obj/item/reagent_containers/food/snacks/aesirsalad, run_loc_floor_bottom_left)
	var/before = rc_units(food)
	rc_click(H, food, C)
	TEST_ASSERT_EQUAL(rc_units(food), before + 2, "the food has the 2 units of ketchup")
	TEST_ASSERT_EQUAL(rc_units(C), 48, "and the bottle lost them")
	var/obj/item/reagent_containers/food/condiment/empty = fd_condiment(/obj/item/reagent_containers/food/condiment)
	rc_click(H, food, empty)
	TEST_ASSERT_EQUAL(rc_units(food), before + 2, "an empty bottle adds nothing")

/// A food with no room takes nothing.
/datum/unit_test/dq_p2_reagents/condiment_is_not_added_to_full_food

/datum/unit_test/dq_p2_reagents/condiment_is_not_added_to_full_food/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/food = allocate(/obj/item/reagent_containers/food/snacks/aesirsalad, run_loc_floor_bottom_left)
	food.reagents.add_reagent(REAGENT_ID_WATER, food.reagents.get_free_space())
	var/before = rc_units(food)
	rc_click(H, food, C)
	TEST_ASSERT_EQUAL(rc_units(food), before, "a full food takes nothing")
	TEST_ASSERT_EQUAL(rc_units(C), 50, "and the bottle keeps it")

/// A condiment is put on a table like any item, and not poured onto it.
/datum/unit_test/dq_p2_reagents/condiment_is_put_on_a_table

/datum/unit_test/dq_p2_reagents/condiment_is_put_on_a_table/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/condiment/C = fd_condiment()
	var/obj/structure/table/table = allocate(/obj/structure/table)
	rc_click(H, table, C)
	TEST_ASSERT_EQUAL(rc_units(C), 50, "nothing is poured")
	rc_click(H, table, C, I_HURT)
	TEST_ASSERT_EQUAL(rc_units(C), 50, "not in a hostile stance either")

// ---------------------------------------------------------------------------------------------------------------------
// Cooking containers
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/proc/fd_cooking(type = /obj/item/reagent_containers/cooking_container/oven, turf/T)
	return allocate(type, T || run_loc_floor_bottom_left)

/// A thing of `type` to put in.
/datum/unit_test/dq_p2_reagents/proc/fd_thing(type, turf/T)
	return allocate(type, T || run_loc_floor_bottom_left)

/datum/unit_test/dq_p2_reagents/cooking_containers_start_as_declared

/datum/unit_test/dq_p2_reagents/cooking_containers_start_as_declared/run_gate()
	var/list/expected = list(
		// type, reagent capacity, space, short name
		list(/obj/item/reagent_containers/cooking_container/oven, 120, 30, "shelf"),
		list(/obj/item/reagent_containers/cooking_container/fryer, 80, 20, "basket"),
		list(/obj/item/reagent_containers/cooking_container/grill, 80, 20, "rack"),
	)
	for(var/list/row in expected)
		var/path = row[1]
		var/obj/item/reagent_containers/cooking_container/C = fd_cooking(path)
		TEST_ASSERT_EQUAL(rc_capacity(C), row[2], "[path]: reagent capacity")
		TEST_ASSERT_EQUAL(C.max_space, row[3], "[path]: room for things")
		TEST_ASSERT_EQUAL(C.shortname, row[4], "[path]: its short name")
		TEST_ASSERT(rc_open(C), "[path]: open to reagents")
		TEST_ASSERT(C.flags & NOREACT, "[path]: reactions are off in it")
		TEST_ASSERT_EQUAL(C.food_items, 0, "[path]: nothing in it")

/// Food, paper and the few hats go in a cooking container by a click, until there is no room (the sum of the sizes).
/datum/unit_test/dq_p2_reagents/cooking_container_takes_food_until_full

/datum/unit_test/dq_p2_reagents/cooking_container_takes_food_until_full/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/fryer/C = fd_cooking(/obj/item/reagent_containers/cooking_container/fryer)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/food = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, food)
	TEST_ASSERT_EQUAL(food.loc, C, "the food is in the basket")
	TEST_ASSERT_EQUAL(C.food_items, 1, "and counted")
	var/obj/item/paper/paper = fd_thing(/obj/item/paper)
	rc_click(H, C, paper)
	TEST_ASSERT_EQUAL(paper.loc, C, "paper goes in too")
	TEST_ASSERT_EQUAL(C.food_items, 2, "counted")
	var/obj/item/clothing/head/beret/beret = fd_thing(/obj/item/clothing/head/beret)
	rc_click(H, C, beret)
	TEST_ASSERT_EQUAL(beret.loc, C, "so does a beret")

/// Something that is not on the list stays out.
/datum/unit_test/dq_p2_reagents/cooking_container_refuses_other_things

/datum/unit_test/dq_p2_reagents/cooking_container_refuses_other_things/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/oven/C = fd_cooking()
	var/obj/item/cell/cell = fd_thing(/obj/item/cell)
	rc_click(H, C, cell)
	TEST_ASSERT_NOTEQUAL(cell.loc, C, "a power cell is not put in")
	TEST_ASSERT_EQUAL(C.food_items, 0, "nothing is counted")
	var/obj/item/reagent_containers/glass/beaker/beaker = fd_thing(/obj/item/reagent_containers/glass/beaker)
	rc_click(H, C, beaker)
	TEST_ASSERT_NOTEQUAL(beaker.loc, C, "nor a beaker: it pours")
	var/obj/item/organ/internal/brain/brain = fd_thing(/obj/item/organ/internal/brain)
	var/obj/item/reagent_containers/cooking_container/fryer/fryer = fd_cooking(/obj/item/reagent_containers/cooking_container/fryer)
	rc_click(H, fryer, brain)
	TEST_ASSERT_NOTEQUAL(brain.loc, fryer, "a brain is not put in a fryer basket")
	rc_click(H, C, brain)
	TEST_ASSERT_EQUAL(brain.loc, C, "but is put in an oven dish")

/// The grill takes what its special recipes want.
/datum/unit_test/dq_p2_reagents/grill_takes_its_special_things

/datum/unit_test/dq_p2_reagents/grill_takes_its_special_things/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/grill/G = fd_cooking(/obj/item/reagent_containers/cooking_container/grill)
	var/obj/item/stack/rods/rods = fd_thing(/obj/item/stack/rods)
	rc_click(H, G, rods)
	TEST_ASSERT_EQUAL(rods.loc, G, "rods go on the rack")
	var/obj/item/reagent_containers/cooking_container/oven/oven = fd_cooking()
	var/obj/item/stack/rods/more = fd_thing(/obj/item/stack/rods)
	rc_click(H, oven, more)
	TEST_ASSERT_NOTEQUAL(more.loc, oven, "but not in an oven dish")

/// A thing that does not fit by size is refused, and the sum of the sizes counts.
/datum/unit_test/dq_p2_reagents/cooking_container_is_full_by_size

/datum/unit_test/dq_p2_reagents/cooking_container_is_full_by_size/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/fryer/C = fd_cooking(/obj/item/reagent_containers/cooking_container/fryer)
	C.max_space = 5
	var/obj/item/reagent_containers/food/snacks/aesirsalad/a = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/b = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/c = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, a)
	rc_click(H, C, b)
	TEST_ASSERT_EQUAL(a.loc, C, "the first fits")
	TEST_ASSERT_EQUAL(b.loc, C, "and the second (small things)")
	rc_click(H, C, c)
	TEST_ASSERT_NOTEQUAL(c.loc, C, "the third is more than the room")
	TEST_ASSERT_EQUAL(C.food_items, 2, "two are counted")
	TEST_ASSERT(C.can_fit(fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)) != TRUE || C.max_space >= 3 * ITEMSIZE_SMALL, "can_fit says what the room is")

/// Alt-click and the menu take every solid thing out onto the floor; reagents stay; an empty one says so.
/datum/unit_test/dq_p2_reagents/cooking_container_is_emptied

/datum/unit_test/dq_p2_reagents/cooking_container_is_emptied/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/oven/C = fd_cooking()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/a = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/b = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, a)
	rc_click(H, C, b)
	C.reagents.add_reagent(REAGENT_ID_WATER, 10)
	rc_alt_click(H, C, null)
	TEST_ASSERT_NOTEQUAL(a.loc, C, "the first is out")
	TEST_ASSERT_NOTEQUAL(b.loc, C, "and the second")
	TEST_ASSERT_EQUAL(C.food_items, 0, "nothing is counted")
	TEST_ASSERT_EQUAL(rc_units(C), 10, "the liquid stays")
	rc_click(H, C, a)
	fd_empty_menu(H, C)
	TEST_ASSERT_NOTEQUAL(a.loc, C, "the menu takes it out as well")
	TEST_ASSERT_EQUAL(C.food_items, 0, "and zero is counted")

/// A person too far away cannot empty it.
/datum/unit_test/dq_p2_reagents/cooking_container_is_not_emptied_from_afar

/datum/unit_test/dq_p2_reagents/cooking_container_is_not_emptied_from_afar/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/far = rc_actor(run_loc_floor_top_right)
	var/obj/item/reagent_containers/cooking_container/oven/C = fd_cooking()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/a = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, a)
	TEST_ASSERT_EQUAL(a.loc, C, "it is in")
	fd_empty_menu(far, C)
	TEST_ASSERT_EQUAL(a.loc, C, "somebody across the room does not empty it")

/// Examine names what is inside and the liquid.
/datum/unit_test/dq_p2_reagents/cooking_container_examine_lists_its_contents

/datum/unit_test/dq_p2_reagents/cooking_container_examine_lists_its_contents/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/oven/C = fd_cooking()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/a = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, a)
	C.reagents.add_reagent(REAGENT_ID_WATER, 10)
	var/text = jointext(C.examine(H), " ")
	TEST_ASSERT(findtext(text, a.name), "it names the food: [text]")
	TEST_ASSERT(findtext(text, "10u"), "and the liquid: [text]")

/// A beaker pours into a cooking container (open to reagents), and the label of a container names its first thing or liquid.
/datum/unit_test/dq_p2_reagents/cooking_container_takes_liquid_and_labels_itself

/datum/unit_test/dq_p2_reagents/cooking_container_takes_liquid_and_labels_itself/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/fryer/C = fd_cooking(/obj/item/reagent_containers/cooking_container/fryer)
	TEST_ASSERT_EQUAL(C.label(1), "basket 1 - empty", "an empty one says so")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, C, B)
	TEST_ASSERT_EQUAL(rc_units(C), 10, "a beaker pours into it")
	TEST_ASSERT(findtext(C.label(1), "Water"), "the label names the liquid: [C.label(1)]")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/a = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, a)
	TEST_ASSERT(findtext(C.label(2), a.name), "with a thing in it the label names the thing: [C.label(2)]")

/// A fill of things draws a rising level, and none when it is empty.
/datum/unit_test/dq_p2_reagents/cooking_container_draws_its_load

/datum/unit_test/dq_p2_reagents/cooking_container_draws_its_load/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/cooking_container/fryer/C = fd_cooking(/obj/item/reagent_containers/cooking_container/fryer)
	TEST_ASSERT_EQUAL(length(fd_cooking_overlays(C)), 0, "an empty one draws nothing extra")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/a = fd_thing(/obj/item/reagent_containers/food/snacks/aesirsalad)
	rc_click(H, C, a)
	TEST_ASSERT_EQUAL(length(fd_cooking_overlays(C)), 1, "one thing draws one layer: [json_encode(fd_cooking_overlays(C))]")
	TEST_ASSERT(("basket1" in fd_cooking_overlays(C)), "of the first level: [json_encode(fd_cooking_overlays(C))]")
	rc_alt_click(H, C, null)
	TEST_ASSERT_EQUAL(length(fd_cooking_overlays(C)), 0, "emptied, it draws nothing extra again")
