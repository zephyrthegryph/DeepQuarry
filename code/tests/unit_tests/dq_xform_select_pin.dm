/**
 * Kitchen selection pin (doc/rewrite/proposals/transformations.md section 12, pin 3), recorded on the legacy /datum/recipe code before the recipes became
 * /transformation/kitchen rules, and kept byte-identical through the conversion.
 *
 * For every recipe of every appliance list (cooking_rules_for()), a container holding exactly the recipe's reagents (the amounts it lists), its items
 * (one of each type) and its fruit (one grown item per count, of a seed with that kitchen tag) is offered to cooking_select() with that appliance's list:
 *   exact / loose   the recipe it selects when extraneous ingredients fail it (exact) or are ignored (loose)
 *   +reagent        the same after one unit of a reagent no recipe lists is added
 *   +item           the same after one item no recipe lists is added
 * and the facts the conversion must keep: result, quantity, time, mix, coating, appliance, wiki flag, the reagents, items and fruit.
 * A recipe whose fixture cannot be built (an item that refuses to be made, a fruit tag with no seed) records `fixture=unbuilt` and the missing part.
 *
 * Rows are `key => value` in code/modules/unit_tests/snapshots/xform/kitchen_select.txt (see dq_xform_pins.dm); an empty file is recorded by the next run.
 */
#define DQ_KITCHEN_PIN_NAME "kitchen_select"

/// The recipe a selection names, as its path below /transformation/kitchen, or "-".
/proc/dq_kitchen_pin_name(datum/xform/R)
	if(!R)
		return "-"
	return copytext("[R.rule_type]", length("/transformation/kitchen/") + 1)

/// A seed key whose kitchen tag is `tag`, or null.
/proc/dq_kitchen_seed_for(tag)
	for(var/key in SSplants.seeds)
		var/datum/seed/S = SSplants.seeds[key]
		if(S?.kitchen_tag == tag)
			return key
	return null

/datum/unit_test/dq_xform_select_pin

/// The container for one recipe: its reagents, items and fruit, plus nothing else. Returns null (and sets `missing`) when a part cannot be made.
/datum/unit_test/dq_xform_select_pin/proc/fixture(datum/xform/R, turf/T, list/missing)
	var/obj/box = new /obj(T)
	box.create_reagents(DQ_XFORM_VOLUME)
	for(var/rid in R.reagent_takes)
		box.reagents.add_reagent(rid, R.reagent_takes[rid], safety = TRUE)
	for(var/item_type in R.cook_items)
		if(ispath(item_type, /obj/item/holder))
			missing += "[item_type]" // a holder is made around a mob
			continue
		var/obj/O = new item_type(box)
		if(QDELETED(O))
			missing += "[item_type]"
	for(var/tag in R.fruit_takes)
		var/seed_key = dq_kitchen_seed_for(tag)
		if(!seed_key)
			missing += "fruit:[tag]"
			continue
		for(var/i in 1 to R.fruit_takes[tag])
			var/obj/G = new /obj/item/reagent_containers/food/snacks/grown(box, seed_key)
			if(QDELETED(G))
				missing += "fruit:[tag]"
	return box

/datum/unit_test/dq_xform_select_pin/proc/choose(appliance, obj/box)
	return "exact=[dq_kitchen_pin_name(cooking_select(appliance, box, TRUE))]; loose=[dq_kitchen_pin_name(cooking_select(appliance, box, FALSE))]"

/datum/unit_test/dq_xform_select_pin/Run()
	var/turf/T = test_floor()
	var/list/rows = list()
	for(var/appliance in cooking_appliances())
		for(var/datum/xform/R as anything in cooking_rules_for(appliance))
			var/key = "[appliance]/[dq_kitchen_pin_name(R)]"
			var/list/facts = list("result=[R.result]", "quantity=[R.result_amount]", "time=[R.cook_time]", "mix=[R.mix]", "coating=[R.coating]", "wiki=[R.wiki]")
			var/list/parts = list()
			for(var/rid in R.reagent_takes)
				parts += "[rid]=[R.reagent_takes[rid]]"
			facts += "reagents=[jointext(parts, ",")]"
			facts += "items=[jointext(R.cook_items || list(), ",")]"
			parts = list()
			for(var/tag in R.fruit_takes)
				parts += "[tag]=[R.fruit_takes[tag]]"
			facts += "fruit=[jointext(parts, ",")]"
			var/list/missing = list()
			var/obj/box = fixture(R, T, missing)
			if(length(missing))
				rows[key] = "[jointext(facts, "; ")]; fixture=unbuilt [jointext(missing, ",")]"
				qdel(box)
				continue
			var/text = "[jointext(facts, "; ")]; [choose(appliance, box)]"
			box.reagents.add_reagent(REAGENT_ID_FUEL, 1, safety = TRUE)
			text += "; +reagent: [choose(appliance, box)]"
			box.reagents.clear_reagents()
			for(var/rid in R.reagent_takes)
				box.reagents.add_reagent(rid, R.reagent_takes[rid], safety = TRUE)
			var/obj/extra = new /obj/item/trash/candle(box)
			text += "; +item: [choose(appliance, box)]"
			qdel(extra)
			rows[key] = text
			qdel(box)
	var/failure = dq_xform_pin_compare(DQ_KITCHEN_PIN_NAME, rows)
	TEST_ASSERT(isnull(failure), failure)
