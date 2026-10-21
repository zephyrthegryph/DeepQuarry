// Stack recipes as transformations (doc/rewrite/proposals/transformations.md, wave 5, chosen mode; decision D12 (b)): what an actor chooses to make from a
// stack. A recipe is a type under /transformation/stack with a transformation(...) entry whose `takes` is the cost, `makes` the result and `chosen` the rest:
//
//   takes = list(stack_term(STACK_SELF, 3))              units of the stack being used
//   makes = list(item_term(/obj/structure/x, 1))         what one batch makes (the amount is the old res_amount)
//   chosen(title = "{display_name} door", subject = /datum/material/steel, max_made = 20, build_time = 5 SECONDS, one_per_turf = TRUE, on_floor = TRUE,
//          material = STACK_MATERIAL_SELF, pass_color = TRUE, recycle = STACK_MATERIAL_SELF, group = "low walls", replaces = TRUE, drops = list("old title"))
//
// `subject` is who the recipe is for: a /datum/material type (a material gets the recipes of its type and of every type above it, top down) or a stack type
// (exactly that stack). A rule in a material level is expanded over each material it applies to, at first use: {display_name} and {name} in the title and in
// `material`/`recycle` become the material's, and `holds` (a condition, or a proc of the material) says whether the material gets the recipe. `replaces` starts
// the level's list afresh instead of extending the one above; `drops` removes titles the levels above made; `group` puts the recipe in a named sub-list.
//
// The expanded recipes are /datum/xform copies (title, result, cost, result_amount, max_made, build_time, one_per_turf, on_floor, use_material, pass_color,
// matter_material), shared by every stack of the material and never written.

/// A group of recipes shown under one title (the old /datum/stack_recipe_list).
/datum/xform_group
	var/title = "ERROR"
	var/list/recipes

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/xform_group)

/// The rest of a stack recipe (everything but the cost and the result). An interned entry nested in a transformation()'s `chosen` argument.
/proc/chosen(title = null, subject = null, max_made = null, build_time = null, one_per_turf = null, on_floor = null, material = null, pass_color = null, recycle = null, group = null, replaces = null, drops = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_XCHOSEN, null, list("title" = title, "subject" = subject, "max_made" = max_made, "build_time" = build_time, "one_per_turf" = one_per_turf, \
		"on_floor" = on_floor, "material" = material, "pass_color" = pass_color, "recycle" = recycle, "group" = group, "replaces" = replaces, "drops" = drops))

/// Reads a rule's `chosen` entry into its flyweight.
/proc/xform_compile_chosen(datum/xform/X, datum/entry/chosen)
	var/list/arguments = chosen.args
	X.title = arguments["title"]
	X.subject = arguments["subject"]
	X.max_made = arguments["max_made"] || 1
	X.build_time = arguments["build_time"] || 0
	X.one_per_turf = arguments["one_per_turf"] || 0
	X.on_floor = arguments["on_floor"] || 0
	X.use_material = arguments["material"]
	X.pass_color = arguments["pass_color"]
	X.matter_material = arguments["recycle"] || X.use_material
	X.group = arguments["group"]
	X.replaces = !!arguments["replaces"]
	X.drops = arguments["drops"]
	if(length(X.takes))
		X.cost = X.takes[1][3]
	if(length(X.makes))
		var/list/made = X.makes[1]
		X.result = made[2]
		X.result_amount = made[3]
	if(!X.title)
		X.title = "ERROR"

/// This rule's recipe for `material` (null for a stack's own list): a copy with the material's names written into the text.
/datum/xform/proc/expand_for(datum/material/material)
	RETURN_TYPE(/datum/xform)
	var/datum/xform/copy = new
	copy.rule_type = rule_type
	copy.medium = medium
	copy.regime = regime
	copy.takes = takes
	copy.makes = makes
	copy.subject = subject
	copy.cost = cost
	copy.result = result
	copy.result_amount = result_amount
	copy.max_made = max_made
	copy.build_time = build_time
	copy.one_per_turf = one_per_turf
	copy.on_floor = on_floor
	copy.pass_color = pass_color
	copy.group = group
	copy.title = title
	copy.use_material = use_material
	copy.matter_material = matter_material
	if(material)
		copy.title = replacetext(replacetext(title, "{display_name}", material.display_name), "{name}", material.name)
		if(use_material)
			copy.use_material = replacetext(use_material, "{name}", material.name)
		if(matter_material)
			copy.matter_material = replacetext(matter_material, "{name}", material.name)
	return copy

/// subject type => its rules, in declaration order. Built on first use.
GLOBAL_LIST_EMPTY(stack_rules_by_subject)
/// material name => the stack recipes of the material (a list of /datum/xform and /datum/xform_group), built on first use and kept off the frozen material.
GLOBAL_LIST_EMPTY(stack_recipes_of_material)
/// stack type => the stack recipes of a stack that has a list of its own.
GLOBAL_LIST_EMPTY(stack_recipes_of_stack)

/proc/stack_rules_for(subject)
	RETURN_TYPE(/list)
	if(!length(GLOB.stack_rules_by_subject))
		for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_CHOSEN))
			LAZYADD(GLOB.stack_rules_by_subject[rule.subject], rule)
	return GLOB.stack_rules_by_subject[subject]

/// Adds `recipe` to `into` (a list of recipes and groups): to its group when it has one (a path of group titles joined with ::; a group is made where its
/// first recipe is), else on its own.
/proc/stack_recipe_add(list/into, datum/xform/recipe)
	if(!recipe.group)
		into += recipe
		return
	var/list/into_list = into
	for(var/title in splittext(recipe.group, "::"))
		var/datum/xform_group/found
		for(var/datum/xform_group/group in into_list)
			if(group.title == title)
				found = group
				break
		if(!found)
			found = new
			found.title = title
			found.recipes = list()
			into_list += found
		into_list = found.recipes
	into_list += recipe

/// The stack recipes of a material: the rules of every level of its type from the top down that hold for it, in order.
/proc/stack_material_recipes(datum/material/material)
	RETURN_TYPE(/list)
	var/list/cached = GLOB.stack_recipes_of_material[material.name]
	if(islist(cached))
		return cached
	var/list/levels = list()
	for(var/level_type = material.type, ispath(level_type, /datum/material), level_type = type2parent(level_type))
		levels.Insert(1, level_type)
	var/list/recipes = list()
	for(var/level_type in levels)
		var/list/rules = stack_rules_for(level_type)
		var/list/dropped = list()
		for(var/datum/xform/rule as anything in rules)
			if(rule.replaces)
				recipes = list()
				break
		for(var/datum/xform/rule as anything in rules)
			if(rule.drops)
				dropped |= rule.drops
			if(!length(rule.takes))
				continue
			if(!xform_cond_holds(rule, material, rule.holds))
				continue
			stack_recipe_add(recipes, rule.expand_for(material))
		if(length(dropped))
			for(var/datum/xform/recipe in recipes.Copy())
				if(recipe.title in dropped)
					recipes -= recipe
	GLOB.stack_recipes_of_material[material.name] = recipes
	return recipes

/// The stack recipes of a stack with a list of its own (rods, sandbags, wax, a cyborg's recycler): the rules whose subject is the stack type.
/proc/stack_own_recipes(stack_type)
	RETURN_TYPE(/list)
	var/list/cached = GLOB.stack_recipes_of_stack[stack_type]
	if(islist(cached))
		return cached
	var/list/recipes = list()
	for(var/datum/xform/rule as anything in stack_rules_for(stack_type))
		stack_recipe_add(recipes, rule.expand_for(null))
	GLOB.stack_recipes_of_stack[stack_type] = recipes
	return recipes

/// The root of the stack recipes. A condition of the material is named with TYPE_PROC_REF(/transformation/stack, x) and answers for the material.
/transformation/stack

CAPABILITIES(/transformation/stack)
	transformation(medium = MEDIUM_CONTENTS, regime = REGIME_CHOSEN)

/// Materials sturdy enough for furniture and doors.
/transformation/stack/proc/sturdy(datum/material/material)
	return material.integrity >= 50

/// Sturdy materials whose icons are the solid wall set.
/transformation/stack/proc/solid(datum/material/material)
	return material.integrity >= 50 && material.icon_base == "solid"

/// Materials hard enough for blades and cutlery.
/transformation/stack/proc/hard(datum/material/material)
	return material.hardness > 50
