////////////// PTR-7 Anti-Materiel Rifle //////////////

/obj/item/gun/projectile/heavysniper/collapsible

EXTEND_INTERACTIONS(/obj/item/gun/projectile/heavysniper/collapsible, INTERACT_VERB("Disassemble Rifle", PROC_REF(collapsible_sniper_verb_take_down), REQ_IN_INVENTORY))

/// Old Disassemble Rifle verb.
/obj/item/gun/projectile/heavysniper/collapsible/proc/collapsible_sniper_verb_take_down(mob/living/carbon/human/user, obj/item/held, datum/interaction/interaction)
	if(user.stat)
		return

	if(chambered)
		to_chat(user, span_warning("You need to empty the rifle to break it down."))
	else
		collapse_rifle(user)

/obj/item/gun/projectile/heavysniper/proc/collapse_rifle(mob/user)
	to_chat(user, span_warning("You begin removing \the [src]'s barrel."))
	om_task_timed(user, 4 SECONDS, src, src, PROC_REF(barrel_removed), list(user))

/obj/item/gun/projectile/heavysniper/proc/barrel_removed(mob/user)
	if(user.unEquip(src, force=1))
		to_chat(user, span_warning("You remove \the [src]'s barrel."))
		consume(src, user)
		var/obj/item/barrel = new /obj/item/sniper_rifle_part/barrel(user)
		var/obj/item/sniper_rifle_part/assembly = new /obj/item/sniper_rifle_part/trigger_group(user)
		var/obj/item/sniper_rifle_part/stock/stock = new(assembly)
		assembly.stock_handle = om_handle(stock)
		assembly.part_count = 2
		assembly.update_build(user)
		user.put_in_any_hand_if_possible(assembly) || assembly.dropInto(user.loc)
		user.put_in_any_hand_if_possible(barrel) || barrel.dropInto(user.loc)


/obj/item/sniper_rifle_part
	name = "AM rifle part"
	desc = "A part of an antimateriel rifle."

	w_class = ITEMSIZE_NORMAL

	icon = 'icons/obj/gun.dmi'

	var/tmp/barrel_handle
	var/tmp/stock_handle
	var/tmp/trigger_group_handle
	var/part_count = 1


/obj/item/sniper_rifle_part/barrel
	name = "AM rifle barrel"
	icon_state = "heavysniper-barrel"

/obj/item/sniper_rifle_part/barrel/Initialize(mapload)
	. = ..()
	barrel_handle = om_handle(src)

/obj/item/sniper_rifle_part/stock
	name = "AM rifle stock"
	icon_state = "heavysniper-stock"

/obj/item/sniper_rifle_part/stock/Initialize(mapload)
	. = ..()
	stock_handle = om_handle(src)

/obj/item/sniper_rifle_part/trigger_group
	name = "AM rifle trigger assembly"
	icon_state = "heavysniper-trig"

/obj/item/sniper_rifle_part/trigger_group/Initialize(mapload)
	. = ..()
	trigger_group_handle = om_handle(src)

DECLARE_INTERACTIONS(/obj/item/sniper_rifle_part, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/sniper_rifle_part/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(part_count == 1)
		to_chat(user, span_warning("You can't disassemble this further!"))
		return TRUE

	to_chat(user, span_notice("You start disassembling \the [src]."))
	om_task_timed(user, 4 SECONDS, src, src, PROC_REF(disassembled), list(user))
	return TRUE

/obj/item/sniper_rifle_part/proc/disassembled(mob/user)
	if(part_count == 1)
		return
	to_chat(user, span_notice("You disassemble \the [src]."))
	for(var/obj/item/sniper_rifle_part/P in list(barrel(), stock(), trigger_group()))
		if(P.barrel() != P)
			P.barrel_handle = null
		if(P.stock() != P)
			P.stock_handle = null
		if(P.trigger_group() != P)
			P.trigger_group_handle = null
		if(P != src)
			user.put_in_any_hand_if_possible(P) || P.dropInto(loc)
		P.part_count = 1

	update_build(user)

/// Old attackby.
/obj/item/sniper_rifle_part/proc/interaction_item(mob/user, obj/item/sniper_rifle_part/A, datum/interaction/interaction)

	to_chat(user, span_notice("You begin adding \the [A] to \the [src]."))
	om_task_timed(user, 3 SECONDS, src, src, PROC_REF(part_added), list(A, user))
	return INTERACTION_HANDLED_PASS

/obj/item/sniper_rifle_part/proc/part_added(obj/item/sniper_rifle_part/A, mob/user)
	if(istype(A, /obj/item/sniper_rifle_part/trigger_group))
		if(A.part_count > 1 && src.part_count > 1)
			to_chat(user, span_warning("Disassemble one of these parts first!"))
			return

		if(!trigger_group())
			if(user.unEquip(A, force=1))
				trigger_group_handle = om_handle(A)
		else
			to_chat(user, span_warning("There's already a trigger group!"))
			return

	else if(istype(A, /obj/item/sniper_rifle_part/barrel))
		if(!barrel())
			if(user.unEquip(A, force=1))
				barrel_handle = om_handle(A)
		else
			to_chat(user, span_warning("There's already a barrel!"))
			return

	else if(istype(A, /obj/item/sniper_rifle_part/stock))
		if(!stock())
			if(user.unEquip(A, force=1))
				stock_handle = om_handle(A)
		else
			to_chat(user, span_warning("There's already a stock!"))
			return

	A.forceMove(src)
	to_chat(user, span_notice("You install \the [A]."))

	if(A.barrel() && !src.barrel())
		src.barrel_handle = om_handle(A.barrel())
	if(A.stock() && !src.stock())
		src.stock_handle = om_handle(A.stock())
	if(A.trigger_group() && !src.trigger_group())
		src.trigger_group_handle = om_handle(A.trigger_group())


	part_count = A.part_count + src.part_count
	update_build(user)


/obj/item/sniper_rifle_part/proc/update_build(mob/user)
	switch(part_count)
		if(1)
			name = initial(name)
			w_class = ITEMSIZE_NORMAL
			icon_state = initial(icon_state)
		if(2)
			if(barrel() && trigger_group())
				name = "AM rifle barrel-trigger assembly"
				icon_state = "heavysniper-trigbar"
			else if(stock() && trigger_group())
				name = "AM rifle stock-trigger assembly"
				icon_state = "heavysniper-trigstock"
			else if(stock() && barrel())
				name = "AM rifle stock-barrel assembly"
				icon_state = "heavysniper-barstock"
			w_class = ITEMSIZE_LARGE

		if(3)
			var/obj/item/gun/projectile/heavysniper/collapsible/gun = new (get_turf(src), 0)
			if(user && ishuman(user))
				var/mob/living/carbon/human/H = user
				H.unEquip(src, force=1)
				H.put_in_any_hand_if_possible(gun) || gun.dropInto(loc)
			consume(src, user)


/// LC-refs: the barrel this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/sniper_rifle_part/proc/barrel() as /obj/item/sniper_rifle_part
	return om_resolve(barrel_handle)

/// LC-refs: the trigger_group this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/sniper_rifle_part/proc/trigger_group() as /obj/item/sniper_rifle_part
	return om_resolve(trigger_group_handle)

/// LC-refs: the stock this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/sniper_rifle_part/proc/stock() as /obj/item/sniper_rifle_part
	return om_resolve(stock_handle)
