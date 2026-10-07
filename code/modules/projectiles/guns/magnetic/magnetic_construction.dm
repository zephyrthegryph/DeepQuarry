// We really need some datums for this.
/obj/item/coilgun_assembly
	name = "coilgun stock"
	desc = "It might be a coilgun, someday."
	icon = 'icons/obj/coilgun.dmi'
	icon_state = "coilgun_construction_1"

	var/construction_stage = 1

/obj/item/coilgun_assembly/welder_act(mob/user, obj/item/tool)
	if(construction_stage != 4)
		return NONE
	var/obj/item/weldingtool/welder = tool.get_welder()

	if(!welder.isOn())
		to_chat(user, span_warning("Turn it on first!"))
		return ITEM_INTERACT_SUCCESS

	if(!welder.remove_fuel(0,user))
		to_chat(user, span_warning("You need more fuel!"))
		return ITEM_INTERACT_SUCCESS

	act_message(user, src, others = span_infoplain(span_bold("%U%") + " welds the barrel of %T% into place."))
	play_sfx(src, SFX_ITEMS_WELDER2, 2)
	increment_construction_stage()
	return ITEM_INTERACT_SUCCESS

/obj/item/coilgun_assembly/screwdriver_act(mob/user, obj/item/tool)
	if(construction_stage < 9)
		return NONE
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " secures %T% and finishes it off."))
	play_sfx(src, SFX_ITEMS_SCREWDRIVER)
	var/obj/item/gun/magnetic/coilgun = new(loc)
	var/put_in_hands
	var/mob/M = src.loc
	if(istype(M))
		put_in_hands = M == user
		M.drop_from_inventory(src)
	if(put_in_hands)
		user.put_in_hands(coilgun)
	replace_with(src, coilgun)
	return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/coilgun_assembly)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/coilgun_assembly/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/thing = A.held

	if(istype(thing, /obj/item/stack/material) && construction_stage == 1)
		var/obj/item/stack/material/reinforcing = thing
		var/datum/material/reinforcing_with = reinforcing.get_material()
		if(reinforcing_with.name == MAT_STEEL) // Steel
			if(reinforcing.get_amount() < 5)
				to_chat(user, span_warning("You need at least 5 [reinforcing.singular_name]\s for this task."))
				return OP_PASS
			reinforcing.use(5)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " shapes some steel sheets around %T% to form a body."))
			increment_construction_stage()
			return OP_PASS

	if(istype(thing, /obj/item/tape_roll) && construction_stage == 2)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " secures %T% together with %I%."), item = thing)
		increment_construction_stage()
		return OP_PASS

	if(istype(thing, /obj/item/pipe) && construction_stage == 3)
		consume(thing, user)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " jams %I% into %T%."), item = thing)
		increment_construction_stage()
		return OP_PASS

	if(istype(thing, /obj/item/stack/cable_coil) && construction_stage == 5)
		var/obj/item/stack/cable_coil/cable = thing
		if(cable.get_amount() < 5)
			to_chat(user, span_warning("You need at least 5 lengths of cable for this task."))
			return OP_PASS
		cable.use(5)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " wires %T%."))
		increment_construction_stage()
		return OP_PASS

	if(istype(thing, /obj/item/smes_coil) && construction_stage >= 6 && construction_stage <= 8)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " installs \a [thing] into %T%."))
		consume(thing, user)
		increment_construction_stage()
		return OP_PASS

	return OP_DECLINE

/obj/item/coilgun_assembly/proc/increment_construction_stage()
	if(construction_stage < 9)
		construction_stage++
	icon_state = "coilgun_construction_[construction_stage]"

/obj/item/coilgun_assembly/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		switch(construction_stage)
			if(2)
				. += span_notice("It has a metal frame loosely shaped around the stock.")
			if(3)
				. += span_notice("It has a metal frame duct-taped to the stock.")
			if(4)
				. += span_notice("It has a length of pipe attached to the body.")
			if(5)
				. += span_notice("It has a length of pipe welded to the body.")
			if(6)
				. += span_notice("It has a cable mount and capacitor jack wired to the frame.")
			if(7)
				. += span_notice("It has a single superconducting coil threaded onto the barrel.")
			if(8)
				. += span_notice("It has a pair of superconducting coils threaded onto the barrel.")
			if(9)
				. += span_notice("It has three superconducting coils attached to the body, waiting to be secured.")
