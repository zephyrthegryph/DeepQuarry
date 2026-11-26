// Stacked resources. They use a material datum for a lot of inherited values.
// If you're adding something here, make sure to add it to fifty_spawner_mats.dm as well
/obj/item/stack/material
	w_class = ITEMSIZE_NORMAL
	max_amount = 50
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
		)

	var/default_type = MAT_STEEL
	var/datum/material/material
	/// Exotic/runtime-material stacks (substance alloys, shellchitin) whose material
	/// has no static autolathe design and legitimately can't be reprinted from a
	/// fixed recipe — exempt from all_sheets_must_be_printable_from_autolathe.
	var/exotic_no_autolathe_reprint = FALSE
	var/coin_type = null
	var/perunit = SHEET_MATERIAL_AMOUNT
	var/apply_colour //temp pending icon rewrite

CAPABILITIES(/obj/item/stack/material)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	configure(movable_motion(throw_range = 3, throw_speed = 3))
	configure(item_handling(center_x = 0, center_y = 0))
	setup(PROC_REF(find_material), mapload = TRUE)
	setup(PROC_REF(stack_material_setup))
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5.0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_AXE, pickup = SFX_ITEMS_PICKUP_AXE))
	without("ui_open")
	op("material_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Material self"), then(PROC_REF(material_self)))
	op("material_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(material_interaction_item)))

// The material is named by a constructor param (default_type), which keeps_if() cannot read (it is asked before the params apply), so this is a hint-returning hook: a stack of a material that does not exist is discarded.
/obj/item/stack/material/proc/find_material(mapload)
	if(!default_type)
		set_default_type(MAT_STEEL)
	set_material(get_material_by_name("[default_type]"))
	if(!material)
		stack_trace("Material of type: [default_type] does not exist.")
		return INITIALIZE_HINT_QDEL

/obj/item/stack/material/proc/stack_material_setup()
	randpixel_xy()
	// A stack made in a shipment being unpacked, or on an expedition site's level, is a lot of its own (a lot a smelter set already stands).
	if(isnull(lot_key))
		lot_key = trace_lot_at(src)

	set_recipes(material.get_recipes())
	set_stacktype(material.stack_type)

	if(apply_colour)
		set_color(material.icon_colour)

	if(!material.conductive())
		flags |= NOCONDUCT

	update_strings()

/// A sheet's composition follows its material (per sheet; multiply by the amount).
/obj/item/stack/material/material_totals()
	return material ? material.get_matter() : ..()

/obj/item/stack/material/get_material()
	return material

/obj/item/stack/material/proc/update_strings()
	// Update from material datum.
	singular_name = material.sheet_singular_name

	if(amount>1)
		name = "[material.use_name] [material.sheet_plural_name]"
		desc = "A [material.sheet_collective_name] of [material.use_name] [material.sheet_plural_name]."
		set_gender(PLURAL)
	else
		name = "[material.use_name] [material.sheet_singular_name]"
		desc = "A [material.sheet_singular_name] of [material.use_name]."
		set_gender(NEUTER)

/obj/item/stack/material/get_examine_string()
	if(!uses_charge)
		return "There [amount == 1 ? "is" : "are"] [amount] [material.sheet_singular_name]\s in the [material.sheet_collective_name]."
	return ..()

/obj/item/stack/material/use(used)
	var/before = amount
	. = ..()
	if(QDELETED(src))
		return
	// The sheets used took their share of the traces with them.
	if(. && before > 0 && length(trace_amounts))
		scale_traces(amount / before)
	update_strings()

/// Whether `other` is the same kind of stock, so the two merge. Plain stock merges on its material whatever lot it came from.
/obj/item/stack/material/proc/can_merge_with(obj/item/stack/material/other)
	return material?.name == other.material?.name

/// Stock merges like pouring a beaker of solid into another: traces average by amount, and the merged stack is unassayed if either half was.
/obj/item/stack/material/transfer_to(obj/item/stack/S, tamount=null, type_verified)
	var/obj/item/stack/material/M = S
	if(!istype(M) || !can_merge_with(M))
		return 0
	ensure_traces()
	M.ensure_traces()
	var/before = get_amount()
	var/both_assayed = assayed && M.assayed
	var/transfer = ..(S,tamount,1)
	if(transfer && before > 0)
		var/fraction = transfer / before
		for(var/trace_id in LAZYCOPY(trace_amounts))
			var/moved = trace_amounts[trace_id] * fraction
			trace_amounts[trace_id] -= moved
			LAZYSET(M.trace_amounts, trace_id, (LAZYACCESS(M.trace_amounts, trace_id) || 0) + moved)
		M.assayed = both_assayed
	if(!QDELETED(src))
		update_strings()
	if(M)
		M.update_strings()
	return transfer

/obj/item/stack/material/split(tamount)
	ensure_traces()
	var/before = amount
	var/list/old_traces = LAZYCOPY(trace_amounts)
	var/obj/item/stack/material/new_stack = ..()
	if(!new_stack)
		return null
	new_stack.set_default_type(material.name)
	new_stack.set_material(material)
	new_stack.set_recipes(material.get_recipes())
	new_stack.set_stacktype(material.stack_type)
	new_stack.traces_rolled = TRUE
	new_stack.assayed = assayed
	if(before > 0)
		for(var/trace_id in old_traces)
			LAZYSET(new_stack.trace_amounts, trace_id, old_traces[trace_id] * new_stack.amount / before)
			if(!QDELETED(src))
				trace_amounts[trace_id] = old_traces[trace_id] * amount / before
	new_stack.update_strings()
	return new_stack

/// Old attack_self: build windows, or open the recipe window.
/obj/item/stack/material/proc/material_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!material.build_windows(user, src))
		tgui_interact(user)

/// Old attackby.
/obj/item/stack/material/proc/material_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/stack/cable_coil))
		material.build_wired_product(user, W, src)
		return OP_PASS
	else if(istype(W, /obj/item/stack/rods))
		material.build_rod_product(user, W, src)
		return OP_PASS
	else if(istype(W, /obj/item/analyzer) && !istype(material, /datum/material/processed_alloy))
		// The spectrometer: reads the traces in this stack and marks it assayed.
		var/list/lines = assay(user)
		to_chat(user, span_notice("Spectrometry of [src]: [length(lines) ? jointext(lines, "; ") : "no traces"]."))
		return OP_PASS
	return OP_DECLINE
