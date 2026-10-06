/obj/item/clothing/gloves/telekinetic
	desc = "Gloves with a built in telekinesis module, allows for remote interaction with small objects."
	name = "kinesis assistance module"
	icon_state = "regen"
	item_state = "graygloves"
	var/use_power_amount = 12


/obj/item/clothing/gloves/telekinetic/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell/device)

/obj/item/clothing/gloves/telekinetic/proc/has_grip_power()
	if(cell && cell.charge >= use_power_amount)
		return TRUE
	return FALSE

/obj/item/clothing/gloves/telekinetic/proc/use_grip_power(mob/user,play_sound)
	if(cell)
		cell.checked_use(use_power_amount)
		user?.tk_refresh() // the power left may be too little for the next reach
		if(play_sound)
			if(cell.charge < use_power_amount)
				to_chat(user,span_danger("\The [src] bwoop as it runs out of power."))
				play_sfx(src, SFX_MACHINES_SYNTH_NO, volume = 0)
			else
				play_sfx(src, SFX_MACHINES_GENERATOR_GENERATOR_END)

CAPABILITIES(/obj/item/clothing/gloves/telekinetic)
	op("telekinetic_remove_cell_hand", hand(), ungated(), then(PROC_REF(telekinetic_remove_cell_hand)))
	op("telekinetic_insert_cell", item(/obj/item/cell), label("Insert cell"), then(PROC_REF(telekinetic_insert_cell)))

/// Old attack_hand: take the cell out while holding the gloves in the other hand.
/obj/item/clothing/gloves/telekinetic/proc/telekinetic_remove_cell_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		if(cell)
			cell.update_icon()
			user.put_in_hands(cell)
			rel_take(src, nameof(cell))
			to_chat(user, span_notice("You remove the cell from the [src]."))
			play_sfx(src, SFX_MACHINES_BUTTON)
			return TRUE
	return OP_DECLINE

/// Old attackby: install a device cell.
/obj/item/clothing/gloves/telekinetic/proc/telekinetic_insert_cell(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/cell/device))
		if(!cell)
			if(!move_into(src, nameof(src.cell), W, user))
				return OP_PASS
			to_chat(user, span_notice("You install a cell in \the [src]."))
			play_sfx(src, SFX_MACHINES_BUTTON)
		else
			to_chat(user, span_warning("\The [src] already has a cell."))
	else
		to_chat(user, span_warning("\The [src] cannot use that type of cell."))
	return OP_PASS

/obj/item/clothing/gloves/telekinetic/examine(mob/user)
	. = ..()
	if(cell)
		. += span_info("\The [src] has a \the [cell] attached.")
		if(cell.charge <= cell.maxcharge*0.25)
			. += span_warning("It appears to have a low amount of power remaining.")
		else if(cell.charge > cell.maxcharge*0.25 && cell.charge <= cell.maxcharge*0.5)
			. += span_notice("It appears to have an average amount of power remaining.")
		else if(cell.charge > cell.maxcharge*0.5 && cell.charge <= cell.maxcharge*0.75)
			. += span_info("It appears to have an above average amount of power remaining.")
		else if(cell.charge > cell.maxcharge*0.75 && cell.charge <= cell.maxcharge)
			. += span_info("It appears to have a high amount of power remaining.")
	else
		. += span_warning("\The [src] has an empty powercell slot.")
