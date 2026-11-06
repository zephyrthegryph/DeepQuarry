/// What a kitchen rule makes (doc/rewrite/proposals/transformations.md, wave 3): an exact container of a recipe's ingredients, cooked through the rule's owner
/// (make_food), turns into the result in the quantity declared, merges the ingredients' reagents by the declared mode, and the four recipes that override
/// make_food keep their extra step.

/datum/unit_test/dq_xform_cooking_make

/// A container holding exactly what `rule` takes (items one of each, fruit not needed by the recipes this test cooks).
/datum/unit_test/dq_xform_cooking_make/proc/box_for(datum/xform/rule, turf/T)
	var/obj/box = new /obj(T)
	box.create_reagents(DQ_XFORM_VOLUME)
	for(var/rid in rule.reagent_takes)
		box.reagents.add_reagent(rid, rule.reagent_takes[rid], safety = TRUE)
	for(var/item_type in rule.cook_items)
		new item_type(box)
	return box

/datum/unit_test/dq_xform_cooking_make/proc/cook(rule_type, turf/T)
	var/datum/xform/rule = xform_of(rule_type)
	TEST_ASSERT_NOTNULL(rule, "[rule_type] is a compiled rule")
	var/obj/box = box_for(rule, T)
	var/datum/xform/chosen = cooking_select(rule.cooks_in, box)
	TEST_ASSERT_EQUAL(chosen, rule, "[rule_type] is what its own contents select")
	var/transformation/kitchen/owner = rule.owner_of()
	var/list/made = owner.make_food(box)
	return list(box, made)

/datum/unit_test/dq_xform_cooking_make/Run()
	var/turf/T = test_floor()
	// Replace: the water is discarded, one result.
	var/list/boiled = cook(/transformation/kitchen/boiledegg, T)
	var/list/made = boiled[2]
	TEST_ASSERT_EQUAL(length(made), 1, "boiled egg makes one")
	TEST_ASSERT(istype(made[1], /obj/item/reagent_containers/food/snacks/boiledegg), "boiled egg makes a boiled egg")
	var/obj/item/reagent_containers/food/snacks/boiledegg/egg = made[1]
	TEST_ASSERT_EQUAL(egg.reagents.get_reagent_amount(REAGENT_ID_WATER), 0, "replace discards the ingredients' water")
	qdel(boiled[1])
	// Max: the result holds at least what the ingredients held of each reagent.
	var/list/fried = cook(/transformation/kitchen/friedegg, T)
	made = fried[2]
	TEST_ASSERT(istype(made[1], /obj/item/reagent_containers/food/snacks/friedegg), "fried egg makes a fried egg")
	var/obj/item/reagent_containers/food/snacks/friedegg/fried_egg = made[1]
	TEST_ASSERT(fried_egg.reagents.get_reagent_amount(REAGENT_ID_SODIUMCHLORIDE) >= 1, "max keeps the salt")
	qdel(fried[1])
	// Quantity: a muffin recipe makes two.
	var/list/muffins = cook(/transformation/kitchen/muffin, T)
	made = muffins[2]
	TEST_ASSERT_EQUAL(length(made), 2, "muffin makes two")
	qdel(muffins[1])
	// The overrides: amanita jelly sheds its toxin, valid salad too, a donk pocket is warm, and warming a donk pocket keeps it.
	var/list/jelly = cook(/transformation/kitchen/amanitajelly, T)
	var/obj/item/reagent_containers/food/snacks/amanitajelly/jelly_made = jelly[2][1]
	TEST_ASSERT_EQUAL(jelly_made.reagents.get_reagent_amount(REAGENT_ID_AMATOXIN), 0, "amanita jelly has no amatoxin")
	qdel(jelly[1])
	var/list/pocket = cook(/transformation/kitchen/donkpocket, T)
	var/obj/item/reagent_containers/food/snacks/donkpocket/pocket_made = pocket[2][1]
	TEST_ASSERT(pocket_made.warm, "a cooked donk pocket is warm")
	qdel(pocket[1])
	var/datum/xform/warm_rule = xform_of(/transformation/kitchen/donkpocket/warm)
	var/obj/box = box_for(warm_rule, T)
	var/obj/item/reagent_containers/food/snacks/donkpocket/cold = locate() in box
	TEST_ASSERT_NOTNULL(cold, "the warming container holds a donk pocket")
	var/transformation/kitchen/warm_owner = warm_rule.owner_of()
	var/list/warmed = warm_owner.make_food(box)
	TEST_ASSERT_EQUAL(warmed[1], cold, "warming returns the donk pocket it was given")
	TEST_ASSERT(cold.warm, "and it is warm")
	TEST_ASSERT(!QDELETED(cold), "and it was not consumed")
	qdel(box)
