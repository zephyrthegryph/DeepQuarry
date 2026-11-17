// Recycling a spawned (not printed) item must not out-earn what the same thing costs to print. Every item type is held to it.
//
// dq_fab_conservation (dq_fab_conservation_tests.dm) rewrites a printed product's composition to what the lathe took, so it cannot see the composition a type declares: the
// items a player never prints (kit contents, vendor stock, mapped gear) go straight into a crusher with the declared one. These tests read the declared composition of every
// item type, without an instance (dq_type_material_totals()), and check it:
//
//   keys      every material a composition names is a registered material (a mistyped id is a null material, and crushing the item runtimes).
//   designs   an item type that a design prints (or whose nearest parent type is printed) breaks down into no more than the design costs, counted in material units.
//   cap       an item type with no design anywhere above it stays under DQ_RECYCLE_CAP_UNITS.
//
// A stack's declared composition is per unit; its recycled worth is that times its amount (breakdown_units(), /obj/item/stack/get_material_composition()).

/// The most material units an item type with no design may break down into (ten sheets).
#define DQ_RECYCLE_CAP_UNITS 20000

/// Every item type a composition test looks at: a real item, not a projectile (which sits in the item tree and is never recycled).
/proc/dq_recycle_item_types()
	. = list()
	for(var/path in subtypesof(/obj/item))
		if(ispath(path, /obj/item/projectile))
			continue
		. += path

/// What a type's declared composition breaks down into, by total units (a stack's per unit times the amount a new one holds), or null when it has none.
/proc/dq_recycle_type_total(path)
	var/list/totals = dq_type_material_totals(path)
	if(!length(totals))
		return null
	. = 0
	for(var/key in totals)
		if(isnum(totals[key]))
			. += totals[key]
	if(ispath(path, /obj/item/stack))
		var/obj/item/stack/stack_type = path
		. *= max(initial(stack_type.amount), 1)

/// Every key of every item type's declared composition names a registered material.
/datum/unit_test/dq_recycle_keys_resolve

/datum/unit_test/dq_recycle_keys_resolve/Run()
	var/list/bad = list()
	var/checked = 0
	for(var/path in dq_recycle_item_types())
		var/list/totals = dq_type_material_totals(path)
		if(!length(totals))
			continue
		checked++
		for(var/key in totals)
			if(!istext(key) || !GLOB.name_to_material[key])
				bad += "[path] names '[key]'"
				break
	TEST_ASSERT(checked > 0, "no item type declares a composition")
	TEST_ASSERT(!length(bad), "[length(bad)] item types name a material that is not registered (crushing one dereferences a null material): [jointext(bad.Copy(1, min(length(bad), 12) + 1), " | ")]")

/// The cost of the cheapest design that prints each item type: path -> units. A mechfab design is its own table, a lathe's the effective one.
/proc/dq_recycle_design_costs()
	. = list()
	for(var/id in SSresearch.techweb_designs)
		var/datum/design_techweb/D = SSresearch.techweb_designs[id]
		if(!D || D.id == DESIGN_ID_IGNORE || D.make_reagent || length(D.reagents_list))
			continue
		var/path = saved_type_path(D.build_path)
		if(!ispath(path, /obj/item))
			continue
		var/list/source = (D.build_type & (MECHFAB | PROSFAB)) ? mechfab_cost(D) : D.effective_materials(null)
		var/cost = 0
		for(var/key in source)
			if(isnum(source[key]))
				cost += source[key]
		if(!cost)
			continue
		if(isnull(.[path]) || cost < .[path])
			.[path] = cost

/datum/unit_test/dq_recycle_conservation

/datum/unit_test/dq_recycle_conservation/Run()
	var/list/costs = dq_recycle_design_costs()
	var/list/gains = list()
	var/list/over_cap = list()
	var/with_design = 0
	var/without_design = 0
	for(var/path in dq_recycle_item_types())
		var/total = dq_recycle_type_total(path)
		if(!total)
			continue
		// the design that prints this type, else the nearest parent type's
		var/design_path
		var/design_cost
		for(var/printed in costs)
			if(ispath(path, printed) && (!design_path || ispath(printed, design_path)))
				design_path = printed
				design_cost = costs[printed]
		if(design_path)
			with_design++
			if(total > design_cost)
				gains += "[path] returns [round(total)] units, [design_path] costs [round(design_cost)]"
		else
			without_design++
			if(total > DQ_RECYCLE_CAP_UNITS)
				over_cap += "[path] returns [round(total)] units"
	TEST_ASSERT(with_design > 0, "no item type was matched to a design")
	for(var/line in gains)
		log_world("CONSERVATION: declared composition above its design: [line]")
	for(var/line in over_cap)
		log_world("CONSERVATION: no design, above the cap of [DQ_RECYCLE_CAP_UNITS] units: [line]")
	TEST_NOTICE(src, "[with_design] item types with a design above them ([length(gains)] return more than it costs), [without_design] without ([length(over_cap)] above the cap)")
	TEST_ASSERT(!length(gains), "[length(gains)] item types break down into more than the design that prints them costs: [jointext(gains.Copy(1, min(length(gains), 12) + 1), " | ")]")
	TEST_ASSERT(!length(over_cap), "[length(over_cap)] item types with no design break down into more than [DQ_RECYCLE_CAP_UNITS] units: [jointext(over_cap.Copy(1, min(length(over_cap), 12) + 1), " | ")]")

#undef DQ_RECYCLE_CAP_UNITS
