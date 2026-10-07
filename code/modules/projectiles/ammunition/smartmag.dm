///////// Smart Mags /////////

/obj/item/ammo_magazine/smart
	name = "smart magazine"
	icon_state = "smartmag-empty"
	desc = "A Hephaestus Industries brand Smart Magazine. It uses advanced matter manipulation technology to create bullets from energy. Simply present your loaded gun or magazine to the Smart Magazine."
	multiple_sprites = 1
	max_ammo = 5
	mag_type = MAGAZINE

	caliber = null 	 //Set later
	ammo_type = null //Set later
	initial_ammo = 0 //Ensure no problems with no ammo_type or caliber set

	can_remove_ammo = FALSE	// Interferes with batteries

	var/production_time = 6 SECONDS		// Delay in between bullets forming
	COOLDOWN_DECLARE(production_cooldown)		// When the next bullet may form (production_time after the last)
	var/production_cost = null			// Set when an ammo type is scanned in
	var/production_modifier = 2			// Multiplier on the ammo_casing's matter cost
	var/production_delay = 75			// If we're in a gun, how long since it last shot do we need to wait before making bullets?
	/// Started by the holding gun's note_shot() for production_delay.
	COOLDOWN_DECLARE(gun_fired_cooldown)

	var/tmp/obj/item/gun/holding_gun	// What gun are we in, if any?

	var/tmp/obj/item/cell/device/attached_cell	// What cell are we using, if any?

	var/emagged = 0		// If you emag the smart mag, you can get the bullets out by clicking it

CAPABILITIES(/obj/item/ammo_magazine/smart)
	every(2 SECONDS, then(PROC_REF(smart_step)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)

/obj/item/ammo_magazine/smart/proc/smart_step(datum/act/timer/A)
	if(!holding_gun())	// Yes, this is awful, sorry. Don't know a better way to figure out if we've been moved into or out of a gun.
		if(istype(src.loc, /obj/item/gun))
			rel_set(src, nameof(holding_gun), src.loc)

	if(caliber && ammo_type && attached_cell())
		if(length(stored_ammo) == max_ammo)
			COOLDOWN_START(src, production_cooldown, production_time)	// Otherwise the max_ammo var is basically always off by 1
			return
		if(holding_gun() && !COOLDOWN_FINISHED(src, gun_fired_cooldown))	// Same as recharging energy weapons.
			return
		if(COOLDOWN_FINISHED(src, production_cooldown))
			COOLDOWN_START(src, production_cooldown, production_time)
			produce()

/obj/item/ammo_magazine/smart/examine(mob/user)
	. = ..()

	if(attached_cell())
		. += span_notice("\The [src] is loaded with a [attached_cell().name]. It is [round(attached_cell().percent())]% charged.")
	else
		. += span_warning("\The [src] does not appear to have a power source installed.")

DECLARE_APPEARANCE_PROC(/obj/item/ammo_magazine/smart, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/ammo_magazine/smart/appearance_overlays()
	. = list()
	if(attached_cell())
		icon_state = "smartmag-filled"
	else
		icon_state = "smartmag-empty"

// Emagging lets you remove bullets from your bullet-making magazine

/obj/item/ammo_magazine/smart/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You overload \the [src]'s security measures causing widespread destabilisation. It is likely you could empty \the [src] now."))
	emagged = TRUE
	can_remove_ammo = TRUE
	return OP_OK

EXTEND_INTERACTIONS(/obj/item/ammo_magazine/smart, \
	INTERACT_ITEM(null, PROC_REF(smart_interaction_item)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(smart_interaction_hand)), \
	INTERACT_VERB("Clear Ammo Data", PROC_REF(smartmag_verb_clear_data), REQ_IN_INVENTORY, REQ_FIELD_NOT("stored_ammo", "you can't reset it unless it's empty")), \
)

/// Old attackby. FALSE goes on to the magazine's, as its ..() did.
/obj/item/ammo_magazine/smart/proc/smart_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	make_rounds_real()
	if(istype(I, /obj/item/cell/device))
		if(attached_cell())
			to_chat(user, span_notice("\The [src] already has a [attached_cell().name] attached."))
			return INTERACTION_HANDLED_PASS
		else
			to_chat(user, "You begin inserting \the [I] into \the [src].")
			task_timed(user, 2.5 SECONDS, src, src, PROC_REF(cell_installed), list(user, I))
			return INTERACTION_HANDLED_PASS

	else if(istype(I, /obj/item/ammo_magazine) || istype(I, /obj/item/ammo_casing))
		scan_ammo(I, user)

	return FALSE

/obj/item/ammo_magazine/smart/screwdriver_act(mob/user, obj/item/tool)
	if(!attached_cell())
		return ITEM_INTERACT_BLOCKING
	var/obj/item/cell/device/removed_cell = attached_cell()
	to_chat(user, "You begin removing \the [removed_cell] from \the [src].")
	use_tool(user, tool, src, delay = 1 SECOND, quality = TOOL_SCREWDRIVER, volume = 0, receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, removed_cell))
	return ITEM_INTERACT_SUCCESS

/obj/item/ammo_magazine/smart/proc/screwdriver_act_tool_done(mob/user, obj/item/cell/device/removed_cell)
	removed_cell.update_icon()
	removed_cell.forceMove(get_turf(src))
	rel_clear(src, nameof(attached_cell))
	act_message(user, src, MSG_SELF("You remove %I% from %T%."), MSG_OTHERS("%U% removes a cell from %T%."), item = removed_cell)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/item/ammo_magazine/smart/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(src.loc == user)
		scan_ammo(target, user)
	..()

// You can remove the power cell from the magazine by hand, but it's way slower than using a screwdriver
/// Old attack_hand. FALSE goes on to the magazine's, as its ..() did.
/obj/item/ammo_magazine/smart/proc/smart_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	make_rounds_real()
	if(user.get_inactive_hand() == src)
		if(attached_cell())
			to_chat(user, "You struggle to remove \the [attached_cell()] from \the [src].")
			task_timed(user, 4 SECONDS, src, src, PROC_REF(cell_removed), list(user))
			return TRUE
	return FALSE

/obj/item/ammo_magazine/smart/proc/cell_installed(mob/user, obj/item/cell/device/I)
	if(attached_cell())
		return
	user.drop_item()
	I.forceMove(src)
	rel_set(src, nameof(attached_cell), I)
	act_message(user, src, MSG_SELF("You install %I% into %T%."), MSG_OTHERS("%U% installs a cell in %T%."), item = I)
	update_icon()

/obj/item/ammo_magazine/smart/proc/cell_removed(mob/user)
	if(!attached_cell())
		return
	attached_cell().update_icon()
	user.put_in_hands(attached_cell())
	act_message(user, src, MSG_SELF("You remove \the [attached_cell()] from %T%."), MSG_OTHERS("%U% removes a cell from %T%."))
	rel_clear(src, nameof(attached_cell))
	update_icon()

// Finds the cell for the magazine, used by rechargers
/obj/item/ammo_magazine/smart/get_cell()
	return attached_cell()

// Removes energy from the attached cell when creating new bullets
/obj/item/ammo_magazine/smart/proc/chargereduction()
	return attached_cell() && attached_cell().checked_use(production_cost)

// Sets how much energy is drained to make each bullet
/obj/item/ammo_magazine/smart/proc/set_production_cost(obj/item/ammo_casing/A)
	var/list/matters = GLOB.ammo_repository.get_materials_from_object(A)
	var/tempcost
	for(var/key in matters)
		var/value = matters[key]
		tempcost += value * production_modifier
	production_cost = tempcost

// Scans a magazine or ammo casing and tells the smart mag to start making those, if it can
/obj/item/ammo_magazine/smart/proc/scan_ammo(atom/target, mob/user)

	var/new_caliber = caliber		// Tracks what our new caliber will be
	var/new_ammo_type = ammo_type	// Tracks what our new ammo_type will be

	if(istype(target, /obj/item/ammo_magazine))
		var/obj/item/ammo_magazine/M = target
		if(!new_caliber)
			new_caliber = M.caliber	// If caliber isn't set, set it now

		if(new_caliber && new_caliber != M.caliber)	// If we still don't have a caliber, or if our caliber doesn't match the thing we're scanning, give up
			return
		else
			new_ammo_type = M.ammo_type

	if(istype(target, /obj/item/ammo_casing))
		var/obj/item/ammo_casing/C = target

		if(!new_caliber)
			new_caliber = C.caliber	// If caliber isn't set, set it now

		if(new_caliber && new_caliber != C.caliber)	// If we still don't have a caliber, or if our caliber doesn't match the thing we're scanning, give up
			return
		else
			new_ammo_type = C.type

	var/change = FALSE	// If we've changed caliber or ammo_type, display the built message.
	var/msg = "You scan \the [target] with \the [src], copying \the [target]'s "
	if(new_caliber != caliber)	// This should never happen without the ammo_type switching too
		change = TRUE
		msg += "caliber and "
	if(new_ammo_type != ammo_type)
		change = TRUE
		msg += "ammunition type."

	if(change)
		to_chat(user, span_notice("[msg]"))
		caliber = new_caliber
		ammo_type = new_ammo_type
		set_production_cost(ammo_type)	// Update our cost

	return

// Actually makes the bullets
/obj/item/ammo_magazine/smart/proc/produce()
	if(chargereduction())
		var/obj/item/ammo_casing/W = new ammo_type(src)
		rel_add(src, nameof(stored_ammo), W)
		moveElement(stored_ammo, length(stored_ammo), 1) //to the head of the list
		return 1
	return 0

// This verb clears out the smart mag's copied data, but only if it's empty
/// Old Clear Ammo Data verb.
/obj/item/ammo_magazine/smart/proc/smartmag_verb_clear_data(mob/user, obj/item/held, datum/interaction/interaction)
	if(!isliving(src.loc))	// Needs to be in your hands to reset
		return

	var/mob/living/carbon/human/H = user
	if(!istype(H))
		return
	if(H.stat)
		return


	to_chat(H, span_notice("You clear \the [src]'s data buffers."))

	caliber = null
	ammo_type = null
	production_cost = null

	return

/// What gun are we in, if any? (a relation view: null once it is deleted).
/obj/item/ammo_magazine/smart/proc/holding_gun() as /obj/item/gun
	return holding_gun

/// What cell are we using, if any? (a relation view: null once it is deleted).
/obj/item/ammo_magazine/smart/proc/attached_cell() as /obj/item/cell/device
	return attached_cell
