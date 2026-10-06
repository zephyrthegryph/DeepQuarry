/* Stack type objects!
 * Contains:
 * 		Stacks
 * 		Recipe datum
 * 		Recipe list datum
 */

/*
 * Stacks
 */

/obj/item/stack
	gender = PLURAL
	icon = 'icons/obj/stacks_ch.dmi' // materials update
	randpixel = 7
	center_of_mass_x = 0
	center_of_mass_y = 0
	/// A shared recipe table of /datum/stack_recipe (GLOB or the registered material holds it; never owned or cleared by the stack).
	var/tmp/list/datum/stack_recipe/recipes
	var/singular_name
	var/amount = 1
	var/max_amount //also see stack recipes initialisation, param "max_res_amount" must be equal to this max_amount
	var/stacktype //determines whether different stack types can merge
	var/build_type = null //used when directly applied to a turf
	var/uses_charge = 0
	var/list/charge_costs = null
	/// The robot module's matter synths this stack draws on (relation list; the module owns them).
	var/list/datum/matter_synth/synths = null
	var/no_variants = TRUE // Determines whether the item should update it's sprites based on amount.

	var/pass_color = FALSE // Will the item pass its own color var to the created item? Dyed cloth, wood, etc.
	var/strict_color_stacking = FALSE // Will the stack merge with other stacks that are different colors? (Dyed cloth, wood, etc)

	var/beacons = FALSE
	var/sandbags = FALSE

SETTER(/obj/item/stack, amount)

CAPABILITIES(/obj/item/stack)
	ref_many(nameof(synths), /datum/matter_synth)
	interface("MaterialStack", state = nameof(GLOB.tgui_hands_state), input = in_hand())
	op("make", ui_act("make", arg("multiplier", num()), arg("ref", schema_ref(/datum/stack_recipe))), then(PROC_REF(ui_act_make)))
	op("consolidate", item(/obj/item/gripper), passes(), then(PROC_REF(consolidated)))
	op("combine", item(/obj/item/stack), passes(), when(req(PROC_REF(held_is_another))), then(PROC_REF(combined)))
	op("split", hand(), ungated(), label("Split"), then(PROC_REF(split_asked)))
	param(nameof(amount_at_make), pos = 1)

/// The amount a stack is made with (its constructor param): null for its own, negative for a full stack.
/obj/item/stack/var/amount_at_make

// ALLOW(init/INSTANCE_STATE): a stack sets its starting amount (a negative one is a full stack), its in-hand sprite and its sale
/obj/item/stack/Initialize(mapload)
	. = ..()
	if(!stacktype)
		stacktype = type
	if(!no_variants)
		item_state = initial(icon_state) // the in-hand sprite of a stack with variants is the plain one, whatever the pile shows
	var/starting_amount = amount_at_make
	if(!isnull(starting_amount)) // Could be 0
		// Negative numbers are 'give full stack', like -1
		if(starting_amount < 0)
			// But sometimes a coder forgot to define what that even means
			if(max_amount)
				starting_amount = max_amount
			else
				starting_amount = 1
		set_amount(starting_amount, TRUE)
	update_icon()
	make_sellable(/datum/sellable/material_stack)

/obj/item/stack/get_material_composition(breakdown_flags)
	. = ..()
	for(var/M in .)
		.[M] *= amount

/obj/item/stack/draw(datum/look/look)
	..()
	look.state(look_state())

/// The icon state the pile shows: by how full it is (a stack with no variants keeps its own).
/obj/item/stack/proc/look_state()
	if(no_variants || amount <= (max_amount * (1/3)))
		return initial(icon_state)
	if(amount <= (max_amount * (2/3)))
		return "[initial(icon_state)]_2"
	return "[initial(icon_state)]_3"

/obj/item/stack/proc/get_examine_string()
	if(!uses_charge)
		return "There [src.amount == 1 ? "is" : "are"] [src.amount] [src.singular_name]\s in the stack."
	else
		return "There is enough charge for [get_amount()]."

/obj/item/stack/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		. += get_examine_string()

/// The stack's recipe window data.
/obj/item/stack/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["amount"] = get_amount()

	return data

/obj/item/stack/tgui_static_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["recipes"] = recursively_build_recipes(recipes)

	return data

/obj/item/stack/proc/recursively_build_recipes(list/recipe_to_iterate)
	var/list/L = list()
	for(var/recipe in recipe_to_iterate)
		if(istype(recipe, /datum/stack_recipe_list))
			var/datum/stack_recipe_list/R = recipe
			L["[R.title]"] = recursively_build_recipes(R.recipes)
		if(istype(recipe, /datum/stack_recipe))
			var/datum/stack_recipe/R = recipe
			L["[R.title]"] = build_recipe(R)

	return L

/obj/item/stack/proc/build_recipe(datum/stack_recipe/R)
	return list(
		"res_amount" = R.res_amount,
		"max_res_amount" = R.max_res_amount,
		"req_amount" = R.req_amount,
		"ref" = "\ref[R]",
	)

/// The window's build button: `ref` is the recipe, `multiplier` how many batches.
/obj/item/stack/proc/ui_act_make(datum/act/op/A, multiplier, datum/stack_recipe/ref)
	var/mob/user = A.actor
	if(get_amount() < 1)
		spent(src)
		return

	var/datum/stack_recipe/R = ref
	if(!is_valid_recipe(R, recipes)) //href exploit protection
		return FALSE
	if(!multiplier || (multiplier <= 0)) //href exploit protection
		return
	produce_recipe(R, multiplier, user)
	return TRUE

/obj/item/stack/proc/is_valid_recipe(datum/stack_recipe/R, list/recipe_list)
	for(var/S in recipe_list)
		if(S == R)
			return TRUE
		if(istype(S, /datum/stack_recipe_list))
			var/datum/stack_recipe_list/L = S
			if(is_valid_recipe(R, L.recipes))
				return TRUE

	return FALSE

/obj/item/stack/proc/produce_recipe(datum/stack_recipe/recipe, quantity, mob/user)
	var/required = quantity*recipe.req_amount
	var/produced = min(quantity*recipe.res_amount, recipe.max_res_amount)

	if(om_busy(src))
		return

	if (!can_use(required))
		if (produced>1)
			to_chat(user, span_warning("You haven't got enough [src] to build \the [produced] [recipe.title]\s!"))
		else
			to_chat(user, span_warning("You haven't got enough [src] to build \the [recipe.title]!"))
		return

	if (recipe.one_per_turf && (locate_within(user.loc, recipe.result_type)))
		to_chat(user, span_warning("There is another [recipe.title] here!"))
		return

	if (recipe.on_floor && !isfloor(user.loc))
		to_chat(user, span_warning("\The [recipe.title] must be constructed on the floor!"))
		return

	if (recipe.time)
		to_chat(user, span_notice("Building [recipe.title] ..."))
	om_task_start(/datum/om/task/timed/stack_build, user, src, duration = recipe.time, receiver = src, recipe = recipe, required = required, produced = produced)

/// Building a stack recipe (at once when it takes no time): the stack is claimed meanwhile.
/datum/om/task/timed/stack_build
	claims = TRUE
	complete_proc = /obj/item/stack/proc/produce_recipe_done
	var/datum/stack_recipe/recipe
	var/required
	var/produced

/// The build time is over: spend the stack and make the thing.
/obj/item/stack/proc/produce_recipe_done(datum/om/task/timed/stack_build/task)
	var/datum/stack_recipe/recipe = task.recipe
	var/mob/user = task.actor
	var/required = task.required
	var/produced = task.produced
	if (use(required))
		var/atom/O
		if(recipe.use_material)
			O = new recipe.result_type(user.loc, recipe.use_material)

			if(istype(O, /obj/item))
				var/obj/item/Ob = O

				// Law of equivalent exchange: the product is made of exactly what it cost.
				var/mattermult = istype(Ob, /obj/item) ? min(2000, 400 * Ob.w_class) : 2000
				Ob.set_single_material(recipe.use_material, mattermult / produced * required)

		else
			O = new recipe.result_type(user.loc)

			if(recipe.matter_material)
				if(istype(O, /obj/item))
					var/obj/item/Ob = O

					// Law of equivalent exchange: the product is made of exactly what it cost.
					var/mattermult = istype(Ob, /obj/item) ? min(2000, 400 * Ob.w_class) : 2000
					Ob.set_single_material(recipe.matter_material, mattermult / produced * required)

		O.set_dir(user.dir)
		O.add_fingerprint(user)
		if (istype(O, /obj/item/stack))
			var/obj/item/stack/S = O
			S.set_amount(produced, TRUE)
			S.add_to_stacks(user)
		if (isitem(O))
			var/obj/item/P = O
			P.persist_storable = FALSE
		if (istype(O, /obj/item/storage)) //BubbleWrap - so newly formed boxes are empty
			for (var/obj/item/I in O)
				spent(I)

		if ((pass_color || recipe.pass_color))
			if(!color)
				if(recipe.use_material)
					var/datum/material/MAT = get_material_by_name(recipe.use_material)
					if(MAT.icon_colour)
						O.color = MAT.icon_colour
				else
					return
			else
				O.color = color

//Return 1 if an immediate subsequent call to use() would succeed.
//Ensures that code dealing with stacks uses the same logic
/obj/item/stack/proc/can_use(used)
	if(used < 0 || (used != round(used)))
		stack_trace("Tried to use a bad stack amount: [used]. Location: [src.loc] ([src.x],[src.y],[src.z])")
		return 0
	if(get_amount() < used)
		return 0
	return 1

/obj/item/stack/proc/use(used)
	if(!can_use(used))
		return 0
	if(!uses_charge)
		set_amount(amount - used, TRUE)
		if (amount <= 0)
			// Tell container that we used up a stack
			if(istype( loc, /obj/item/storage))
				var/obj/item/storage/holder = loc
				holder.remove_from_storage( src, null)
			spent(src) //should be safe to qdel immediately since if someone is still using this stack it will persist for a little while longer
		return 1
	else
		if(get_amount() < used)
			return 0
		for(var/i = 1 to uses_charge)
			var/datum/matter_synth/S = synths[i]
			S.use_charge(charge_costs[i] * used) // Doesn't need to be deleted
		return 1

/obj/item/stack/proc/add(extra)
	if(extra < 0 || (extra != round(extra)))
		stack_trace("Tried to add a bad stack amount: [extra]. Location: [src.loc] ([src.x],[src.y],[src.z])")
		return 0
	if(!uses_charge)
		if(amount + extra > get_max_amount())
			return 0
		else
			set_amount(amount + extra, TRUE)
		return 1
	else if(!synths || synths.len < uses_charge)
		return 0
	else
		for(var/i = 1 to uses_charge)
			var/datum/matter_synth/S = synths[i]
			S.add_charge(charge_costs[i] * extra)

/obj/item/stack/proc/set_amount(new_amount, no_limits = FALSE)
	if(new_amount < 0 || (new_amount != round(new_amount)))
		stack_trace("Tried to set a bad stack amount: [new_amount]. Location: [src.loc] ([src.x],[src.y],[src.z])")
		return 0

	// Clean up the new amount
	new_amount = max(round(new_amount), 0)

	// Can exceed max if you really want
	if(new_amount > max_amount && !no_limits)
		new_amount = max_amount

	if(amount != new_amount)
		amount = new_amount
		tracked_changed(src, nameof(amount))

	// Can set it to 0 without qdel if you really want
	if(amount == 0 && !no_limits)
		spent(src)
		return FALSE

	return TRUE

/*
	The transfer and split procs work differently than use() and add().
	Whereas those procs take no action if the desired amount cannot be added or removed these procs will try to transfer whatever they can.
	They also remove an equal amount from the source stack.
*/

//attempts to transfer amount to S, and returns the amount actually transferred
/obj/item/stack/proc/transfer_to(obj/item/stack/S, tamount=null, type_verified)
	if (!get_amount())
		return 0
	if ((stacktype != S.stacktype) && !type_verified)
		return 0
	if ((strict_color_stacking || S.strict_color_stacking) && S.color != color)
		return 0

	if (isnull(tamount))
		tamount = src.get_amount()

	if(tamount < 0 || (tamount != round(tamount)))
		stack_trace("Tried to transfer a bad stack amount: [tamount]. Location: [src.loc] ([src.x],[src.y],[src.z])")
		return 0

	var/transfer = max(min(tamount, src.get_amount(), (S.get_max_amount() - S.get_amount())), 0)

	var/orig_amount = src.get_amount()
	if (transfer && src.use(transfer))
		S.add(transfer)
		if (prob(transfer/orig_amount * 100))
			transfer_fingerprints_to(S)
			transfer_blooddna_to(S)
		return transfer
	return 0

//creates a new stack with the specified amount
/obj/item/stack/proc/split(tamount)
	if (!amount)
		return null
	if(uses_charge)
		return null

	if(tamount < 0 || (tamount != round(tamount)))
		stack_trace("Tried to split a bad stack amount: [tamount]")
		return null

	var/transfer = max(min(tamount, src.amount, initial(max_amount)), 0)

	var/orig_amount = src.amount
	if (transfer && src.use(transfer))
		var/obj/item/stack/newstack = new src.type(loc, transfer)
		newstack.color = color
		copy_stack_properties(newstack)
		if (prob(transfer/orig_amount * 100))
			transfer_fingerprints_to(newstack)
			transfer_blooddna_to(newstack)
		return newstack
	return null

/// Called by split() on the freshly constructed stack so subtypes whose identity
/// is per-instance state (a runtime material, a feedstock lot) rather than the
/// type path can carry it across. `new src.type(...)` alone only copies the type.
/obj/item/stack/proc/copy_stack_properties(obj/item/stack/newstack)
	return

/obj/item/stack/proc/get_amount()
	if(uses_charge)
		if(!synths || synths.len < uses_charge)
			return 0
		var/datum/matter_synth/S = synths[1]
		. = round(S.get_charge() / charge_costs[1])
		if(uses_charge > 1)
			for(var/i = 2 to uses_charge)
				S = synths[i]
				. = min(., round(S.get_charge() / charge_costs[i]))
		return
	return amount

/obj/item/stack/proc/get_max_amount()
	if(uses_charge)
		if(!synths || synths.len < uses_charge)
			return 0
		var/datum/matter_synth/S = synths[1]
		. = round(S.max_energy / charge_costs[1])
		if(uses_charge > 1)
			for(var/i = 2 to uses_charge)
				S = synths[i]
				. = min(., round(S.max_energy / charge_costs[i]))
		return
	return max_amount

/obj/item/stack/proc/add_to_stacks(mob/user as mob)
	for (var/obj/item/stack/item in user.loc)
		if (item==src)
			continue
		var/transfer = src.transfer_to(item)
		if (transfer)
			to_chat(user, span_notice("You add a new [item.singular_name] to the stack. It now contains [item.amount] [item.singular_name]\s."))
		if(!amount)
			break

/// Touching the stack in the other hand asks how many to split off; otherwise the touch goes on to the pickup.
/obj/item/stack/proc/split_asked(datum/act/op/A)
	var/mob/user = A.actor
	if (user.get_inactive_hand() != src)
		return OP_DECLINE
	open_request(src, /datum/prompt/number, PROC_REF(split_amount_chosen), answerer = user, title = "Split stacks", question = "How many stacks of [src] would you like to split off?  There are currently [amount].", default = 1, max_value = amount, min_value = 1, step = 0.01, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/stack/proc/split_amount_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/N = A.answer.value
	if(N != round(N))
		to_chat(user, span_warning("You cannot separate a non-whole number of stacks!"))
		return
	if(N)
		var/obj/item/stack/F = src.split(N)
		if (F)
			user.put_in_hands(F)
			src.add_fingerprint(user)
			F.add_fingerprint(user)
			if (!QDELETED(src) && user.check_current_machine(src))
				src.interact(user)

/// A cyborg's gripper gathers the stacks around it into this one.
/obj/item/stack/proc/consolidated(datum/act/op/A)
	var/obj/item/gripper/G = A.held
	G.consolidate_stacks(src)
	return OP_OK

/// A stack clicked with itself in the hand is the in-hand use, not a stack held against another.
/obj/item/stack/proc/held_is_another(datum/act/op/A)
	return A.held != src

/// A stack held against this one: this one pours into it.
/obj/item/stack/proc/combined(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/S = A.held
	src.transfer_to(S)
	if(QDELETED(src))
		return OP_OK

	if (S && user.check_current_machine(S))
		S.interact(user)
	if (src && user.check_current_machine(src))
		src.interact(user)
	return OP_OK

/obj/item/stack/proc/combine_in_loc()
	return //STUBBED for now, as it seems to randomly delete stacks

/obj/item/stack/dropped(mob/user, equipping, slot)
	. = ..()
	if(isturf(loc))
		combine_in_loc()

/obj/item/stack/Moved(atom/old_loc, direction, forced)
	. = ..()
	var/mob/pulledby = src?.pulled_by_mob()
	if(pulledby && isturf(loc))
		combine_in_loc()

/obj/item/stack/proc/reagents_per_sheet()
	return REAGENTS_PER_SHEET // units total of reagents when grinded

/*
 * Recipe datum
 */
/datum/stack_recipe
	var/title = "ERROR"
	var/result_type
	var/req_amount = 1 //amount of material needed for this recipe
	var/res_amount = 1 //amount of stuff that is produced in one batch (e.g. 4 for floor tiles)
	var/max_res_amount = 1
	var/time = 0
	var/one_per_turf = 0
	var/on_floor = 0
	var/use_material
	var/pass_color
	var/matter_material 	// Material type used for recycling. Default, uses use_material. For non-material-based objects however, matter_material is needed.

/datum/stack_recipe/New(title, result_type, req_amount = 1, res_amount = 1, max_res_amount = 1, time = 0, one_per_turf = 0, on_floor = 0, supplied_material = null, pass_stack_color, recycle_material = null)
	src.title = title
	src.result_type = result_type
	src.req_amount = req_amount
	src.res_amount = res_amount
	src.max_res_amount = max_res_amount
	src.time = time
	src.one_per_turf = one_per_turf
	src.on_floor = on_floor
	src.use_material = supplied_material
	src.pass_color = pass_stack_color

	if(!recycle_material && src.use_material)
		src.matter_material = src.use_material

	else if(recycle_material)
		src.matter_material = recycle_material

/*
 * Recipe list datum
 */
/datum/stack_recipe_list
	var/title = "ERROR"
	var/list/recipes = null
/datum/stack_recipe_list/New(title, recipes)
	src.title = title
	src.recipes = recipes

// Porting stack dragging/auto stacking from TG.

/obj/item/stack/proc/merge(obj/item/stack/S) //Merge src into S, as much as possible
	var/transfer = get_amount()
	transfer = min(transfer, S.max_amount - S.amount)
	var/mob/pulledby2 = src?.pulled_by_mob()
	if(pulledby2)
		pulledby2.start_pulling(S)
	transfer_fingerprints_to(S)
	S.init_forensic_data().merge_blooddna(forensic_data)
	use(transfer)
	S.add(transfer)

/obj/item/stack/proc/can_merge(obj/item/stack/S)
	if(uses_charge || S.uses_charge) // This should realistically never happen, but in case it does lets avoid breaking things.
		return
	if(S.stacktype != stacktype)
		return
	if(S.amount >= S.max_amount)
		return
	if(!isturf(loc) || !isturf(S.loc))
		return FALSE
	if(src == S)
		return FALSE
	if(ismob(S.loc) || ismob(loc))
		return FALSE
	if(S.throwing || throwing)
		return FALSE
	if(S.amount < 1 || amount < 1)
		return FALSE
	return TRUE

/obj/item/stack/Crossed(atom/movable/AM)
	if(istype(AM, src.type)) // Sanity so we don't try to merge non-stacks.
		if(can_merge(AM))
			merge(AM)
	return ..()

