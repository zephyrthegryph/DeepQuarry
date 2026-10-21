/**
 * Stack recipe pin (doc/rewrite/proposals/transformations.md section 12), recorded on the legacy recipe lists (the old stack recipe datums) before they became
 * /transformation/stack rules, and kept byte-identical through the conversion.
 *
 * One row per recipe of every stack the game makes: a stack of each concrete type is made and its `recipes` list read in order, nested lists included (the
 * material stacks get the recipes of their material, built per material at run time). A row is keyed by the stack type and the recipe's place
 * (`/obj/item/stack/material/steel#12`, `#7/3` for the third recipe of the seventh entry, a recipe list), and holds the title, the result, what it costs
 * and makes, the build time, the placement flags, the materials and whether it takes the stack's colour. A recipe list's own row holds its title.
 *
 * Rows are `key => value` in code/modules/unit_tests/snapshots/xform/stack_recipes.txt (see dq_xform_pins.dm); an empty file is recorded by the next run.
 */
#define DQ_STACK_PIN_NAME "stack_recipes"

/datum/unit_test/dq_xform_stack_pin

/datum/unit_test/dq_xform_stack_pin/proc/flatten(prefix, list/recipes, list/rows)
	var/at = 0
	for(var/recipe in recipes)
		at++
		var/place = "[prefix][prefix == "" ? "" : "/"][at]"
		if(istype(recipe, /datum/xform_group))
			var/datum/xform_group/group = recipe
			rows[place] = "list: [group.title]"
			flatten(place, group.recipes, rows)
		else if(istype(recipe, /datum/xform))
			var/datum/xform/R = recipe
			rows[place] = "[R.title]; result=[R.result]; req=[R.cost]; res=[R.result_amount]; max=[R.max_made]; time=[R.build_time]; one_per_turf=[R.one_per_turf]; on_floor=[R.on_floor]; material=[R.use_material]; color=[R.pass_color]; recycle=[R.matter_material]"
		else
			rows[place] = "other: [recipe]"

/datum/unit_test/dq_xform_stack_pin/Run()
	var/turf/T = test_floor()
	var/list/rows = list()
	for(var/stack_type in typesof(/obj/item/stack))
		var/obj/item/stack/S = new stack_type(T)
		if(!QDELETED(S) && length(S.recipes))
			var/list/mine = list()
			flatten("", S.recipes, mine)
			for(var/place in mine)
				rows["[stack_type]#[place]"] = mine[place]
		if(!QDELETED(S))
			qdel(S)
	var/failure = dq_xform_pin_compare(DQ_STACK_PIN_NAME, rows)
	TEST_ASSERT(isnull(failure), failure)
