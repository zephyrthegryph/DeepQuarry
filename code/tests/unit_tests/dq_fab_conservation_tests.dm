// Material conservation: nothing is made out of nothing.
//
// What a fabricator or a stack recipe costs must cover what the product breaks down into. The sweeps below make every product the way a player gets it and count what
// recycling it (a material container, a crusher, a destructive analyzer) would return, against what it cost:
//
//   designs   every registered design, printed the way the lathes print it: the cost is the design's materials (a lathe: effective_materials(), the exosuit and
//             prosthetics fabricators: the design's own table), the product is create_item() with its recorded materials set to that cost
//             (split_materials_uniformly(), what fabricator_print_one() does), a stack design a batch of its initial amount.
//   recipes   every stack recipe of every material and of every stack that has a list of its own, made by stack_recipe_product() (the one proc the build uses),
//             against the units of the stack it takes.
//
// A material the product returns beyond what it cost (a unit of slack per part for rounding) is a gain and fails the test. A product that returns less than it cost is a
// process loss (the item does not record what it took, or a cap holds it down): counted and logged, never a failure. Every finding is logged as a CONSERVATION: line.
//
// The exhaustive tier sweeps everything; the normal tier runs a fixed stride of each sweep (doc/testing.md "Tiers").

/// A list of material (or material name) -> units, with a composite material (reinforced glass) broken into what it is made of, as get_material_composition() does.
/proc/dq_fab_basic(list/matter)
	. = list()
	for(var/key in matter)
		var/datum/material/M = istype(key, /datum/material) ? key : get_material_by_name(key)
		var/amount = matter[key]
		if(!istype(M) || !isnum(amount))
			continue
		if(length(M.composite_material))
			for(var/sub in M.composite_material)
				var/datum/material/S = GET_MATERIAL_REF(sub)
				.[S] += amount * (M.composite_material[sub] / SHEET_MATERIAL_AMOUNT)
		else
			.[M] += amount

/// What recycling `made` and every item in it returns, by material (what a material container takes: each item's composition, a stack's times its amount).
/proc/dq_fab_recovered(obj/item/made)
	. = list()
	for(var/obj/item/part as anything in made.get_all_contents_type(/obj/item))
		var/list/composition = part.get_material_composition()
		for(var/key in composition)
			.[key] += composition[key]

/// The parts of `made` and what is in it.
/proc/dq_fab_part_count(obj/item/made)
	return length(made.get_all_contents_type(/obj/item))

/// Total units in a material list.
/proc/dq_fab_total(list/matter)
	. = 0
	for(var/key in matter)
		. += matter[key]

/// The materials `back` holds beyond what `paid` covers: "name +units" per material over by more than `slack`.
/proc/dq_fab_excess(list/paid, list/back, slack)
	. = list()
	for(var/datum/material/M as anything in back)
		var/over = back[M] - (paid[M] || 0)
		if(over > slack)
			. += "[M.name] +[round(over)] (cost [round(paid[M] || 0)], returns [round(back[M])])"

/// Every recipe in a recipe list, groups opened.
/proc/dq_fab_flatten(list/recipes, list/into)
	for(var/entry in recipes)
		if(istype(entry, /datum/xform_group))
			var/datum/xform_group/group = entry
			dq_fab_flatten(group.recipes, into)
		else if(istype(entry, /datum/xform))
			into += entry

/datum/unit_test/dq_fab_conservation
	abstract_type = /datum/unit_test/dq_fab_conservation
	tier = TEST_TIER_EXHAUSTIVE
	is_sweep_test = TRUE
	timeout = 600
	/// Findings that fail the test.
	var/list/gains
	/// Products that cannot be recycled at all (a structure, a machine) or could not be made in a test.
	var/skipped = 0
	/// Products that could not be made without a runtime (a defect of their own, logged by name).
	var/errored = 0
	var/checked = 0
	/// Per fabricator kind: how many designs were counted, and how many of them gained or lost.
	var/list/by_kind

/// Every nth unit of the sweep: 1 for the exhaustive sweep.
/datum/unit_test/dq_fab_conservation/proc/stride()
	return 1

/datum/unit_test/dq_fab_conservation/proc/note_kind(kind, outcome)
	if(!by_kind)
		by_kind = list()
	var/list/row = by_kind[kind]
	if(!row)
		row = list("checked" = 0, "gain" = 0, "loss" = 0, "skipped" = 0)
		by_kind[kind] = row
	row[outcome]++

/// The one line a finding is logged with.
/datum/unit_test/dq_fab_conservation/proc/finding(kind, label, list/excess, paid_total, back_total, parts)
	var/line = "CONSERVATION: [kind] [label]: cost [round(paid_total)] units, returns [round(back_total)] units over [parts] part\s[length(excess) ? " - GAIN: [jointext(excess, "; ")]" : ""]"
	if(length(excess) || GLOB.fab_trace) // a loss is only counted unless the trace is on: there are many
		log_world(line)
	return line

/datum/unit_test/dq_fab_conservation/proc/report(what)
	var/total_gain = 0
	var/total_loss = 0
	for(var/kind in by_kind)
		var/list/row = by_kind[kind]
		log_world("CONSERVATION: [what] [kind]: [row["checked"]] checked, [row["gain"]] gain, [row["loss"]] loss, [row["skipped"]] skipped")
		total_gain += row["gain"]
		total_loss += row["loss"]
	log_world("CONSERVATION: [what] total: [checked] checked, [total_gain] gain, [total_loss] loss (returns less than it cost), [skipped] skipped, [errored] could not be made")
	TEST_NOTICE(src, "[what]: [checked] checked, [total_gain] gain, [total_loss] return less than they cost, [skipped] skipped, [errored] could not be made")
	if(length(gains))
		TEST_FAIL("[length(gains)] [what] return more material than they cost, so material is made from nothing: [jointext(gains.Copy(1, min(length(gains), 12) + 1), " | ")]")

/// Designs printed the way the lathes print them.
/datum/unit_test/dq_fab_conservation/designs

/datum/unit_test/dq_fab_conservation/designs/Run()
	var/list/ids = list()
	for(var/id in SSresearch.techweb_designs)
		ids += id
	ids = sortList(ids)
	gains = list()
	var/stride = stride()
	for(var/index in 1 to length(ids))
		if(((index - 1) % stride) || !sweep_owns(index - 1))
			continue
		check_design(SSresearch.techweb_designs[ids[index]])
		CHECK_TICK
	TEST_ASSERT(checked > 0 || GLOB.dq_test_shard_count > 1, "no design was checked")
	report("designs")

/datum/unit_test/dq_fab_conservation/designs/proc/kind_of(datum/design_techweb/D)
	if(D.build_type & (MECHFAB | PROSFAB))
		return "mechfab/prosfab"
	if(D.build_type & AUTOLATHE)
		return "autolathe"
	if(D.build_type & IMPRINTER)
		return "circuit imprinter"
	if(D.build_type & (PROTOLATHE | CHASSIS))
		return "protolathe"
	return "other"

/datum/unit_test/dq_fab_conservation/designs/proc/check_design(datum/design_techweb/D)
	if(!D || D.id == DESIGN_ID_IGNORE || D.make_reagent || length(D.reagents_list))
		return
	var/kind = kind_of(D)
	var/product_path = saved_type_path(D.build_path)
	if(!ispath(product_path, /obj/item))
		skipped++
		note_kind(kind, "skipped")
		return
	// the cost the machine takes for one run: a lathe the effective table (template slots with their default materials), the exosuit and prosthetics fabricators the table as it is
	var/list/needed = list()
	var/list/source = (D.build_type & (MECHFAB | PROSFAB)) ? D.materials : D.effective_materials(null)
	for(var/key in source)
		var/datum/material/M = istype(key, /datum/material) ? key : get_material_by_name(key)
		if(istype(M))
			needed[M] += source[key]
	var/obj/item/made
	try
		if(ispath(product_path, /obj/item/stack))
			var/obj/item/stack/stack_type = product_path
			made = new stack_type(null, initial(stack_type.amount))
		else
			made = D.create_item(null, null)
			if(isitem(made))
				split_materials_uniformly(needed, 1, made)
	catch(var/exception/e)
		errored++
		log_world("CONSERVATION: [kind] [D.id] ([product_path]) could not be made: [e.name] at [e.file]:[e.line]")
		return
	if(!isitem(made))
		skipped++
		note_kind(kind, "skipped")
		if(made)
			qdel(made)
		return
	var/list/paid = dq_fab_basic(needed)
	var/list/back = dq_fab_recovered(made)
	var/parts = dq_fab_part_count(made)
	var/list/excess = dq_fab_excess(paid, back, parts)
	var/paid_total = dq_fab_total(paid)
	var/back_total = dq_fab_total(back)
	checked++
	note_kind(kind, "checked")
	var/label = "[D.id] ([product_path])"
	if(length(excess))
		gains += finding(kind, label, excess, paid_total, back_total, parts)
		note_kind(kind, "gain")
	else if(back_total + parts < paid_total)
		finding(kind, label, null, paid_total, back_total, parts)
		note_kind(kind, "loss")
	qdel(made)

/datum/unit_test/dq_fab_conservation/designs/representative
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_fab_conservation/designs/representative/stride()
	return 7

/// Stack recipes, made by the proc the build uses.
/datum/unit_test/dq_fab_conservation/recipes

/datum/unit_test/dq_fab_conservation/recipes/Run()
	// each entry: list(label, datum/xform recipe, list(per-unit materials of the stack))
	var/list/entries = list()
	for(var/name in GLOB.name_to_material)
		var/datum/material/M = GLOB.name_to_material[name]
		if(!istype(M) || !M.stack_type)
			continue
		var/list/flat = list()
		dq_fab_flatten(stack_material_recipes(M), flat)
		var/list/unit = dq_fab_basic(M.get_matter())
		for(var/datum/xform/recipe as anything in flat)
			entries += list(list("[M.name] sheet: [recipe.title]", recipe, unit))
	stack_rules_for(/datum/material) // builds the rule table
	for(var/subject in GLOB.stack_rules_by_subject)
		if(!ispath(subject, /obj/item/stack))
			continue
		var/obj/item/stack/stack_type = subject
		var/obj/item/stack/sample = new stack_type(null)
		var/list/unit = list()
		var/list/composition = sample.get_material_composition()
		for(var/key in composition)
			unit[key] = composition[key] / max(sample.amount, 1)
		qdel(sample)
		var/list/flat = list()
		dq_fab_flatten(stack_own_recipes(subject), flat)
		for(var/datum/xform/recipe as anything in flat)
			entries += list(list("[subject]: [recipe.title]", recipe, unit))
	gains = list()
	var/stride = stride()
	for(var/index in 1 to length(entries))
		if(((index - 1) % stride) || !sweep_owns(index - 1))
			continue
		var/list/entry = entries[index]
		check_recipe(entry[1], entry[2], entry[3])
		CHECK_TICK
	TEST_ASSERT(checked > 0 || GLOB.dq_test_shard_count > 1, "no recipe was checked")
	report("stack recipes")

/datum/unit_test/dq_fab_conservation/recipes/proc/check_recipe(label, datum/xform/recipe, list/unit)
	var/kind = "recipe"
	if(!ispath(saved_type_path(recipe.result), /obj/item))
		skipped++
		note_kind(kind, "skipped")
		return
	var/required = recipe.cost
	var/produced = min(recipe.result_amount, recipe.max_made)
	if(required <= 0 || produced <= 0)
		skipped++
		note_kind(kind, "skipped")
		return
	var/obj/item/made
	try
		made = stack_recipe_product(recipe, null, required, produced)
	catch(var/exception/e)
		errored++
		log_world("CONSERVATION: recipe [label] ([recipe.result], use material [recipe.use_material || "none"]) could not be made: [e.name] at [e.file]:[e.line]")
		return
	if(!isitem(made))
		skipped++
		note_kind(kind, "skipped")
		if(made)
			qdel(made)
		return
	if(istype(made, /obj/item/stack))
		var/obj/item/stack/S = made
		S.set_amount(produced, TRUE)
	var/list/paid = list()
	for(var/datum/material/M as anything in unit)
		paid[M] = unit[M] * required
	var/list/back = dq_fab_recovered(made)
	var/parts = dq_fab_part_count(made)
	var/list/excess = dq_fab_excess(paid, back, parts)
	var/paid_total = dq_fab_total(paid)
	var/back_total = dq_fab_total(back)
	checked++
	note_kind(kind, "checked")
	if(length(excess))
		gains += finding(kind, "[label] ([recipe.result])", excess, paid_total, back_total, parts)
		note_kind(kind, "gain")
	else if(back_total + parts < paid_total)
		finding(kind, "[label] ([recipe.result])", null, paid_total, back_total, parts)
		note_kind(kind, "loss")
	qdel(made)

/datum/unit_test/dq_fab_conservation/recipes/representative
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_fab_conservation/recipes/representative/stride()
	return 13
