// Cooking (doc/rewrite/proposals/transformations.md, wave 3): a recipe is a /transformation/kitchen rule in MEDIUM_CONTENTS, REGIME_COOKING.
//
//   takes = list(reagent(id, n), item_term(type, 1), fruit_term(kitchen_tag, n))   the contents of the cooking container: the reagents it holds (and no others),
//                                                                                   the items (one term per item; non-exact by default) and the grown items by kitchen tag
//   makes = list(item_term(type, n))                                                n copies of the result, made inside the container
//   cooks_in   the appliance bitfield the recipe is made in (MICROWAVE, OVEN, ...); cooking_rules_for() lists the rules of one appliance type
//   mix        how the ingredients' reagents are merged into the result (RECIPE_REAGENT_MAX / MIN / SUM / REPLACE)
//   coating    the coating every snack in the recipe must carry: null requires none, -1 does not care, a type is that coating
//   cook_time  how long a machine cooks it
//
// Selection (cooking_select) is the old select_recipe(): every rule of the appliance whose reagents, items and fruit hold is a candidate, the one with the most
// terms wins, and a tie goes to the later rule in the list (the order the types are declared in). dq_xform_select_pin pins it.
//
// A rule that does more than make its result overrides the owner's hooks: before_cook(container) and after_cook(container) around a machine's cooking,
// make_food(container) to change what is made (call ..() to make the result, then fix up what it returns).

/// The kitchen rules by appliance type (the exact bitfield a machine declares), in the order they are tried. Built on first use.
GLOBAL_ALIST_EMPTY(cooking_by_appliance)

/// The kitchen rules of one appliance type. The list is shared: read it, never write it.
/proc/cooking_rules_for(appliancetype)
	RETURN_TYPE(/list)
	if(!length(GLOB.cooking_by_appliance))
		for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_COOKING))
			LAZYADD(GLOB.cooking_by_appliance[rule.cooks_in], rule)
	return GLOB.cooking_by_appliance[appliancetype]

/// Every appliance type some recipe is made in.
/proc/cooking_appliances()
	cooking_rules_for(MICROWAVE)
	var/list/appliances = list()
	for(var/appliance, rules in GLOB.cooking_by_appliance)
		appliances += appliance
	return appliances

/// The things a machine can be offered: every item type some recipe lists, plus the few the machines always take. Built on first use.
GLOBAL_LIST(acceptable_items)
/// The reagents some recipe lists. Built on first use.
GLOBAL_LIST(acceptable_reagents)

/proc/kitchen_acceptable_items()
	RETURN_TYPE(/list)
	if(!GLOB.acceptable_items)
		var/list/acceptable = list()
		for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_COOKING))
			for(var/item in rule.cook_items)
				acceptable |= item
		acceptable |= /obj/item/holder
		acceptable |= /obj/item/reagent_containers/food/snacks/grown
		acceptable |= /obj/item/soulstone
		acceptable |= /obj/item/fuel_assembly/supermatter
		GLOB.acceptable_items = acceptable
	return GLOB.acceptable_items

/proc/kitchen_acceptable_reagents()
	RETURN_TYPE(/list)
	if(!GLOB.acceptable_reagents)
		var/list/acceptable = list()
		for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_COOKING))
			for(var/reagent in rule.reagent_takes)
				acceptable |= reagent
		GLOB.acceptable_reagents = acceptable
	return GLOB.acceptable_reagents

/// The root of the recipes. The hooks a recipe can override are called on its owner instance (xform.owner_of()).
/transformation/kitchen

CAPABILITIES(/transformation/kitchen)
	transformation(medium = MEDIUM_CONTENTS, regime = REGIME_COOKING, cooks_in = MICROWAVE, cook_time = 10 SECONDS, mix = RECIPE_REAGENT_MAX)

/// Called before a machine starts its delays and cooking.
/transformation/kitchen/proc/before_cook(obj/container)
	return

/// Called when the machine has finished.
/transformation/kitchen/proc/after_cook(obj/container)
	return

/// Makes the result inside `container` and returns the list of what was made. Override to change what is made.
/transformation/kitchen/proc/make_food(obj/container as obj)
	var/datum/xform/rule = xform_of(type)
	return rule.cook(container)

/// The recipe that fits `container` best among those of `appliancetype`, or null. With `exact`, extraneous ingredients fail a recipe; without, they are ignored.
/// In both cases the full set of required ingredients is still needed.
/proc/cooking_select(appliancetype, obj/container, exact)
	RETURN_TYPE(/datum/xform)
	var/highest_count = 0
	var/count = 0
	for(var/datum/xform/rule as anything in cooking_rules_for(appliancetype))
		if(!rule.cooking_check_reagents(container.reagents, exact) || !rule.cooking_check_items(container, exact) || !rule.cooking_check_fruit(container, exact))
			continue
		// Taken from cmp_recipe_complexity_dsc, but is way faster.
		count = LAZYLEN(rule.cook_items) + LAZYLEN(rule.reagent_takes) + LAZYLEN(rule.fruit_takes)
		if(count >= highest_count)
			highest_count = count
			. = rule

/datum/xform/proc/cooking_check_reagents(datum/reagents/avail_reagents, exact = FALSE)
	if(!reagent_takes || !reagent_takes.len)
		return TRUE

	if(!avail_reagents)
		return FALSE

	for(var/r_r in reagent_takes)
		var/aval_r_amnt = avail_reagents.get_reagent_amount(r_r)
		if(aval_r_amnt - reagent_takes[r_r] < 0)
			return FALSE

		if(aval_r_amnt > (reagent_takes[r_r]) && exact)
			return FALSE

	if(LAZYLEN(reagent_takes) < avail_reagents.reagent_list.len)
		return FALSE
	return TRUE

/datum/xform/proc/cooking_check_fruit(obj/container, exact = FALSE)
	if (!fruit_takes || !fruit_takes.len)
		return TRUE

	. = TRUE
	if(fruit_takes && fruit_takes.len)
		var/list/checklist = list()
		// You should trust Copy().
		checklist = fruit_takes.Copy()
		for(var/obj/item/reagent_containers/food/snacks/grown/G in contents_of(container))
			if(!G.seed() || !G.seed().kitchen_tag || isnull(checklist[G.seed().kitchen_tag]))
				continue
			if(cooking_check_coating(G))
				checklist[G.seed().kitchen_tag]--
		for(var/ktag in checklist)
			if(!isnull(checklist[ktag]))
				if(checklist[ktag] < 0 && exact)
					. = FALSE
				else if(checklist[ktag] > 0)
					. = FALSE
					break
	return .

/datum/xform/proc/cooking_check_items(obj/container as obj, exact = FALSE)
	if(!cook_items || !cook_items.len)
		return TRUE

	. = TRUE
	if(cook_items && cook_items.len)
		var/list/checklist = list()
		checklist = cook_items.Copy() // You should really trust Copy
		if(istype(container, /obj/machinery))
			var/obj/machinery/machine = container
			machine.latent_materialize_all() // a walk needs real things (C5)
			for(var/obj/O in ((machine.contents - (machine.component_parts || list())) - machine.circuit)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
				if(istype(O,/obj/item/reagent_containers/food/snacks/grown))
					continue // Fruit is handled in cooking_check_fruit().
				var/found = FALSE
				for(var/i = 1; i < checklist.len+1; i++)
					var/item_type = checklist[i]
					if (istype(O,item_type))
						checklist.Cut(i, i+1)
						found = TRUE
						break
				if(!found && exact)
					return FALSE
		else
			for(var/obj/O in contents_of(container))
				if(istype(O,/obj/item/reagent_containers/food/snacks/grown))
					continue // Fruit is handled in cooking_check_fruit().
				var/found = FALSE
				for(var/i = 1; i < checklist.len+1; i++)
					var/item_type = checklist[i]
					if (istype(O,item_type))
						if(cooking_check_coating(O))
							checklist.Cut(i, i+1)
							found = TRUE
							break
				if (!found && exact)
					return FALSE
		if(checklist.len)
			return FALSE
	return .

//This is called on individual items within the container.
/datum/xform/proc/cooking_check_coating(obj/O, exact = FALSE)
	if(!istype(O,/obj/item/reagent_containers/food/snacks))
		return TRUE //Only snacks can be battered

	if (coating == -1)
		return TRUE //-1 value doesnt care

	var/obj/item/reagent_containers/food/snacks/S = O
	if (!S.coating())
		if (!coating)
			return TRUE
		return FALSE
	else if (S.coating().type == coating)
		return TRUE

	return FALSE

// This proc is called under the assumption that the container has already been checked and found to contain the necessary ingredients
/datum/xform/proc/cook(obj/container as obj)
	if(!result)
		log_runtime(EXCEPTION(span_danger("Recipe [rule_type] is defined without a result, please bug report this.")))
		if(istype(container, /obj/machinery/microwave))
			var/obj/machinery/microwave/M = container
			M.dispose(FALSE)

		else if(istype(container, /obj/item/reagent_containers/cooking_container))
			var/obj/item/reagent_containers/cooking_container/CC = container
			CC.clear()

		container.visible_message(span_warning("[container] inexplicably spills, and its contents are lost!"))

		return


//We will subtract all the ingredients from the container, and transfer their reagents into a holder
//We will not touch things which are not required for this recipe. They will be left behind for the caller
//to decide what to do. They may be used again to make another recipe or discarded, or merged into the results,
//thats no longer the concern of this proc
	var/datum/reagents/buffer = new /datum/reagents(10000000000, null)//


	//Find items we need
	if (cook_items && cook_items.len)
		for (var/i in cook_items)
			var/obj/item/I = locate_in_list(container, i)
			if (I && I.reagents)
				I.reagents.trans_to_holder(buffer,I.reagents.total_volume)
			if(istype(I,/obj/item/holder))
				var/obj/item/holder/hol = I
				if(hol.held_mob?.client)
					hol.held_mob.ghostize()
				consumed(hol.held_mob)
				rel_clear(hol, nameof(hol.held_mob))
			consumed(I)

	//Find fruits
	if (fruit_takes && fruit_takes.len)
		var/list/checklist = list()
		checklist = fruit_takes.Copy()

		for(var/obj/item/reagent_containers/food/snacks/grown/G in contents_of(container))
			if(!G.seed() || !G.seed().kitchen_tag || isnull(checklist[G.seed().kitchen_tag]))
				continue

			if (checklist[G.seed().kitchen_tag] > 0)
				//We found a thing we need
				checklist[G.seed().kitchen_tag]--
				if (G && G.reagents)
					G.reagents.trans_to_holder(buffer,G.reagents.total_volume)
				consumed(G)

	//And lastly deduct necessary quantities of reagents
	if (reagent_takes && reagent_takes.len)
		for (var/r in reagent_takes)
			//Doesnt matter whether or not there's enough, we assume that check is done before
			container.reagents.trans_type_to(buffer, r, reagent_takes[r])

	/*
	Now we've removed all the ingredients that were used and we have the buffer containing the total of
	all their reagents.
	Next up we create the result, and then handle the merging of reagents depending on the mix setting
	*/
	var/tally = 0

	/*
	If we have multiple results, holder will be used as a buffer to hold reagents for the result objects.
	If, as in the most common case, there is only a single result, then it will just be a reference to
	the single-result's reagents
	*/
	var/datum/reagents/holder = new/datum/reagents(10000000000)
	var/list/results = list()
	while (tally < result_amount)
		var/obj/result_obj = new result(container)
		results.Add(result_obj)

		if (!result_obj.reagents)//This shouldn't happen
			//If the result somehow has no reagents defined, then create a new holder
			result_obj.reagents = new /datum/reagents(buffer.total_volume*1.5, result_obj)

		if (result_amount == 1)
			consumed(holder)
			holder = result_obj.reagents
		else
			result_obj.reagents.trans_to(holder, result_obj.reagents.total_volume)
		tally++

	switch(mix)
		if (RECIPE_REAGENT_REPLACE)
			pass() //We do no transferring
		if (RECIPE_REAGENT_SUM)
			//Sum is easy, just shove the entire buffer into the result
			buffer.trans_to_holder(holder, buffer.total_volume)
		if (RECIPE_REAGENT_MAX)
			//We want the highest of each.
			//Iterate through everything in buffer. If the target has less than the buffer, then top it up
			for (var/datum/reagent/R in buffer.reagent_list)
				var/rvol = holder.get_reagent_amount(R.id)
				if (rvol < R.volume)
					//Transfer the difference
					buffer.trans_type_to(holder, R.id, R.volume-rvol)

		if (RECIPE_REAGENT_MIN)
			//Min is slightly more complex. We want the result to have the lowest from each side
			//But zero will not count. Where a side has zero its ignored and the side with a nonzero value is used
			for (var/datum/reagent/R in buffer.reagent_list)
				var/rvol = holder.get_reagent_amount(R.id)
				if (rvol == 0) //If the target has zero of this reagent
					buffer.trans_type_to(holder, R.id, R.volume)
					//Then transfer all of ours

				else if (rvol > R.volume)
					//if the target has more than ours
					//Remove the difference
					holder.remove_reagent(R.id, rvol-R.volume)


	if (results.len > 1)
		//If we're here, then holder is a buffer containing the total reagents for all the results.
		//So now we redistribute it among them
		var/total = holder.total_volume
		for (var/i in results)
			var/atom/a = i //optimisation
			holder.trans_to(a, total / results.len)

	return results
