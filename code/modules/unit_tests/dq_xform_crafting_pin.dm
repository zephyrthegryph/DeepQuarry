/**
 * Crafting recipe pin (doc/rewrite/proposals/transformations.md section 12), recorded on the legacy crafting recipe datums before they became
 * /transformation/crafting rules, and kept byte-identical through the conversion.
 *
 * One row per recipe, keyed by its path below the root of the recipe types: everything the crafting window and the crafting steps read once the recipe is
 * made (so the requirements as sorted and split by the constructor): name, result, requirements, blacklist, tools, catalysts, machinery, parts, time, category,
 * whether it is always available, its extra text, whether only one may stand on a turf, and its material template and total.
 *
 * Rows are `key => value` in code/modules/unit_tests/snapshots/xform/crafting.txt (see dq_xform_pins.dm); an empty file is recorded by the next run.
 */
#define DQ_CRAFTING_PIN_NAME "crafting"

/datum/unit_test/dq_xform_crafting_pin

/// A list of paths (a plain list, or an assoc of path => amount) as text, groups separated by |.
/proc/dq_crafting_pin_text(list/things)
	var/list/parts = list()
	for(var/thing in things)
		if(islist(thing))
			parts += "{[dq_crafting_pin_text(thing)]}"
		else if(!isnull(things[thing]) && !islist(things[thing]))
			parts += "[thing]=[things[thing]]"
		else
			parts += "[thing]"
	return jointext(parts, ",")

/datum/unit_test/dq_xform_crafting_pin/Run()
	var/list/rows = list()
	for(var/datum/xform/R as anything in crafting_recipes())
		var/key = copytext("[R.rule_type]", length("/transformation/crafting/") + 1)
		rows[key] = "name=[R.name]; result=[R.result]; reqs=[dq_crafting_pin_text(R.reqs)]; blacklist=[dq_crafting_pin_text(R.blacklist)]; tool_behaviors=[dq_crafting_pin_text(R.tool_behaviors)]; tool_paths=[dq_crafting_pin_text(R.tool_paths)]; chem_catalysts=[dq_crafting_pin_text(R.chem_catalysts)]; machinery=[dq_crafting_pin_text(R.machinery)]; parts=[dq_crafting_pin_text(R.parts)]; time=[R.build_time]; category=[R.category]; subcategory=[R.subcategory]; always=[R.always_available]; extra=[R.additional_req_text]; one_per_turf=[R.one_per_turf]; material_template=[R.material_template]; material_total=[R.material_total]"
	var/failure = dq_xform_pin_compare(DQ_CRAFTING_PIN_NAME, rows)
	TEST_ASSERT(isnull(failure), failure)
