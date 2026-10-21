// Crafting recipes as transformations (doc/rewrite/proposals/transformations.md, wave 5, chosen mode): what a person makes from things around them in the
// crafting window. A recipe is a type under /transformation/crafting with a transformation(...) entry whose `makes` is the result and `crafted` the rest:
//
//   makes = list(item_term(/obj/item/x, 1))
//   crafted(reqs = list(list(/obj/item/stack/rods = 2), list(/obj/item/shard = 1, /obj/item/butterflyblade = 1)),   // each group is "this OR that", with amounts
//           parts = ..., tool_paths = ..., tool_behaviors = ..., chem_catalysts = ..., machinery = ..., build_time = 12 SECONDS,
//           category = CAT_CLOTHING, subcategory = CAT_NONE, always_available = FALSE, extra_text = "...", one_per_turf = TRUE)
//
// The window reads crafting_recipes(): each rule made into a /datum/xform that carries what the crafting steps read, the way the old recipe datum did once its
// constructor had run (a material product splits its sheet cost into a material template; every recipe forbids its own result as an ingredient; the
// requirements are sorted by cmp_crafting_req_priority). A recipe that does more than make its result overrides check_requirements(user, collected) or
// on_craft_completion(user, result) on its type (called on the rule's owner instance).

/// The rest of a crafting recipe (everything but the result). An interned entry nested in a transformation()'s `crafted` argument.
/proc/crafted(reqs = null, parts = null, tool_behaviors = null, tool_paths = null, chem_catalysts = null, machinery = null, build_time = null, category = null, subcategory = null, always_available = null, extra_text = null, one_per_turf = null, material_template = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_XCRAFTED, null, list("reqs" = reqs, "parts" = parts, "tool_behaviors" = tool_behaviors, "tool_paths" = tool_paths, "chem_catalysts" = chem_catalysts, \
		"machinery" = machinery, "build_time" = build_time, "category" = category, "subcategory" = subcategory, "always_available" = always_available, \
		"extra_text" = extra_text, "one_per_turf" = one_per_turf, "material_template" = material_template))

/// Reads a rule's `crafted` entry into its flyweight (the declared lists, as written).
/proc/xform_compile_crafted(datum/xform/X, datum/entry/crafted)
	var/list/arguments = crafted.args
	X.reqs = arguments["reqs"]
	X.parts = arguments["parts"]
	X.tool_behaviors = arguments["tool_behaviors"]
	X.tool_paths = arguments["tool_paths"]
	X.chem_catalysts = arguments["chem_catalysts"]
	X.machinery = arguments["machinery"]
	X.build_time = isnull(arguments["build_time"]) ? 3 SECONDS : arguments["build_time"]
	X.category = isnull(arguments["category"]) ? CAT_NONE : arguments["category"]
	X.subcategory = isnull(arguments["subcategory"]) ? CAT_NONE : arguments["subcategory"]
	X.always_available = isnull(arguments["always_available"]) ? TRUE : arguments["always_available"]
	X.additional_req_text = arguments["extra_text"]
	X.one_per_turf = arguments["one_per_turf"] || FALSE
	X.material_template = arguments["material_template"]
	if(length(X.makes))
		var/list/made = X.makes[1]
		X.result = made[2]
		X.result_amount = made[3]

/// A copy of a list of requirement groups, each group a copy.
/proc/crafting_copy_reqs(list/reqs)
	if(!reqs)
		return null
	var/list/copy = list()
	for(var/list/group in reqs)
		copy += list(group.Copy())
	return copy

/// This rule as the crafting window and steps read it: a copy with the requirements split, sorted and the result forbidden as an ingredient.
/datum/xform/proc/expand_crafted()
	RETURN_TYPE(/datum/xform)
	var/datum/xform/copy = new
	copy.rule_type = rule_type
	copy.medium = medium
	copy.regime = regime
	copy.name = name
	copy.makes = makes
	copy.result = result
	copy.result_amount = result_amount
	copy.build_time = build_time
	copy.category = category
	copy.subcategory = subcategory
	copy.always_available = always_available
	copy.additional_req_text = additional_req_text
	copy.one_per_turf = one_per_turf
	copy.material_template = material_template
	copy.parts = parts
	copy.chem_catalysts = chem_catalysts
	copy.machinery = machinery
	var/list/remaining_requirements = list()
	var/material_cost = 0
	var/application = material_application_for_product(result)
	for(var/list/requirement_group in reqs)
		if(length(requirement_group) == 1)
			var/obj/item/stack/material/requirement_path = requirement_group[1]
			if(application && ispath(requirement_path, /obj/item/stack/material))
				material_cost += requirement_group[requirement_path] * SHEET_MATERIAL_AMOUNT
				continue
		remaining_requirements += list(requirement_group.Copy())
	copy.reqs = crafting_copy_reqs(reqs)
	if(application && material_cost)
		var/inferred_template = material_template_for_product(result, application)
		if(inferred_template)
			copy.material_template = inferred_template
			copy.material_total = material_cost
			copy.reqs = remaining_requirements
	if(!(result in copy.reqs))
		LAZYADD(copy.blacklist, result)
	if(tool_behaviors)
		copy.tool_behaviors = string_list(tool_behaviors)
	if(tool_paths)
		copy.tool_paths = string_list(tool_paths)
	if(copy.reqs)
		copy.reqs = sortList(copy.reqs, GLOBAL_PROC_REF(cmp_crafting_req_priority))
	return copy

/// Every crafting recipe, in declaration order. Built on first use (the rules compile at setup; the material registry is read here).
GLOBAL_LIST_EMPTY(crafting_recipe_list) // list of all table craft recipes

/proc/crafting_recipes()
	RETURN_TYPE(/list)
	if(!length(GLOB.crafting_recipe_list))
		for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_CRAFTING))
			GLOB.crafting_recipe_list += rule.expand_crafted()
	return GLOB.crafting_recipe_list

/// Computes the total reagents volume of a recipe's parts.
/datum/xform/proc/get_parts_reagents_volume()
	. = 0
	for(var/list/L in parts)
		for(var/path in L)
			if(ispath(path, /datum/reagent))
				. += L[path]

/// The root of the crafting recipes. The hooks a recipe can override are called on its owner instance (xform.owner_of()).
/transformation/crafting

CAPABILITIES(/transformation/crafting)
	transformation(medium = MEDIUM_CONTENTS, regime = REGIME_CRAFTING)

/// Run custom pre-craft checks for this recipe.
/// user: The /mob that initiated the crafting
/// collected_requirements: A list of lists of /obj/item instances that satisfy reqs. Top level list is keyed by requirement path.
/transformation/crafting/proc/check_requirements(mob/user, list/collected_requirements)
	return TRUE

/transformation/crafting/proc/on_craft_completion(mob/user, atom/result)
	return
