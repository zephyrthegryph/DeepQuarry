/**
 * Grinding pin (doc/rewrite/proposals/transformations.md section 12), recorded on the legacy GLOB.sheet_reagents and GLOB.ore_reagents tables before they
 * became /transformation/grinding rules, and kept byte-identical through the conversion.
 *
 * For every sheet and ore the grinders know, one row: the reagent list the table names (in order, duplicates kept), and what grind_items_to_reagents() puts in
 * a large holder when it grinds three sheets (a stack of three) or one ore: each reagent and its amount. The supermatter stack is not ground (it explodes);
 * its row records only the table.
 *
 * Rows are `key => value` in code/modules/unit_tests/snapshots/xform/grinding.txt (see dq_xform_pins.dm); an empty file is recorded by the next run.
 */
#define DQ_GRINDING_PIN_NAME "grinding"

/datum/unit_test/dq_xform_grinding_pin

/datum/unit_test/dq_xform_grinding_pin/proc/outcome(item_type, turf/T)
	var/obj/box = new /obj(T)
	var/datum/reagents/R = new /datum/reagents(DQ_XFORM_VOLUME, box)
	box.reagents = R
	var/obj/item/thing
	if(ispath(item_type, /obj/item/stack))
		thing = new item_type(box, 3)
	else
		thing = new item_type(box)
	var/list/held = list(thing)
	grind_items_to_reagents(held, R)
	var/list/parts = list()
	for(var/datum/reagent/reagent as anything in R.reagent_list)
		parts += "[reagent.id]=[round(reagent.volume, 0.01)]"
	sortTim(parts, GLOBAL_PROC_REF(cmp_text_asc))
	qdel(box)
	return jointext(parts, ",")

/datum/unit_test/dq_xform_grinding_pin/Run()
	var/turf/T = test_floor()
	var/list/rows = list()
	for(var/item_type in GLOB.sheet_reagents)
		var/list/ids = GLOB.sheet_reagents[item_type]
		var/text = "sheet: [islist(ids) ? jointext(ids, ",") : ids]"
		if(!ispath(item_type, /obj/item/stack/material/supermatter))
			text += "; ground: [outcome(item_type, T)]"
		rows["[item_type]"] = text
	for(var/item_type in GLOB.ore_reagents)
		var/list/ids = GLOB.ore_reagents[item_type]
		rows["[item_type]"] = "ore: [islist(ids) ? jointext(ids, ",") : ids]; ground: [outcome(item_type, T)]"
	var/failure = dq_xform_pin_compare(DQ_GRINDING_PIN_NAME, rows)
	TEST_ASSERT(isnull(failure), failure)
