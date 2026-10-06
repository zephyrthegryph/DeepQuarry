// Stacked resources. They use a material datum for a lot of inherited values.
// If you're adding something here, make sure to add it to fifty_spawner_mats.dm as well
/obj/item/stack/material
	force = 5.0
	throwforce = 5
	w_class = ITEMSIZE_NORMAL
	throw_speed = 3
	throw_range = 3
	center_of_mass_x = 0
	center_of_mass_y = 0
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
	drop_sound = SFX_ITEMS_DROP_AXE
	pickup_sound = SFX_ITEMS_PICKUP_AXE

CAPABILITIES(/obj/item/stack/material)
	without("ui_open")

// ALLOW(init/INSTANCE_STATE): a sheet stack takes its material's recipes, stack type, colour and conductivity
/obj/item/stack/material/Initialize(mapload)
	. = ..()

	randpixel_xy()

	if(!default_type)
		default_type = MAT_STEEL
	material = get_material_by_name("[default_type]")
	if(!material)
		stack_trace("Material of type: [default_type] does not exist.")
		return INITIALIZE_HINT_QDEL

	recipes = material.get_recipes()
	stacktype = material.stack_type

	if(apply_colour)
		color = material.icon_colour

	if(!material.conductive)
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
		gender = PLURAL
	else
		name = "[material.use_name] [material.sheet_singular_name]"
		desc = "A [material.sheet_singular_name] of [material.use_name]."
		gender = NEUTER

/obj/item/stack/material/get_examine_string()
	if(!uses_charge)
		return "There [amount == 1 ? "is" : "are"] [amount] [material.sheet_singular_name]\s in the [material.sheet_collective_name]."
	return ..()

/obj/item/stack/material/use(used)
	. = ..()
	if(QDELETED(src))
		return
	update_strings()

/obj/item/stack/material/transfer_to(obj/item/stack/S, tamount=null, type_verified)
	var/obj/item/stack/material/M = S
	if(!istype(M) || material.name != M.material.name)
		return 0
	if(feedstock_lot_id && M.feedstock_lot_id && feedstock_lot_id != M.feedstock_lot_id)
		return 0
	var/transfer = ..(S,tamount,1)
	if(!QDELETED(src))
		update_strings()
	if(M)
		M.update_strings()
	return transfer

/obj/item/stack/material/split(tamount)
	var/obj/item/stack/material/new_stack = ..()
	if(!new_stack)
		return null
	new_stack.default_type = material.name
	new_stack.material = material
	new_stack.recipes = material.get_recipes()
	new_stack.stacktype = material.stack_type
	new_stack.feedstock_purity = feedstock_purity
	new_stack.feedstock_lot_id = feedstock_lot_id
	new_stack.feedstock_trace = feedstock_trace
	new_stack.feedstock_trace_units = feedstock_trace_units
	new_stack.update_strings()
	return new_stack

/// Old attack_self: build windows, or open the recipe window.
/obj/item/stack/material/proc/material_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!material.build_windows(user, src))
		tgui_interact(user)

EXTEND_INTERACTIONS(/obj/item/stack/material, \
	INTERACT_USE(null, PROC_REF(material_self)), \
	INTERACT_ITEM(null, PROC_REF(material_interaction_item)), \
)

/// Old attackby.
/obj/item/stack/material/proc/material_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/stack/cable_coil))
		material.build_wired_product(user, W, src)
		return INTERACTION_HANDLED_PASS
	else if(istype(W, /obj/item/stack/rods))
		material.build_rod_product(user, W, src)
		return INTERACTION_HANDLED_PASS
	return FALSE
