////////////// PTR-7 Anti-Materiel Rifle //////////////

/obj/item/gun/projectile/heavysniper/collapsible

CAPABILITIES(/obj/item/gun/projectile/heavysniper/collapsible)
	op("collapsible_sniper_verb_take_down", menu(), label("Disassemble Rifle"), needs(carried()), then(PROC_REF(collapsible_sniper_verb_take_down)))

/// Old Disassemble Rifle verb.
/obj/item/gun/projectile/heavysniper/collapsible/proc/collapsible_sniper_verb_take_down(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	if(user.stat)
		return

	if(chambered)
		to_chat(user, span_warning("You need to empty the rifle to break it down."))
	else
		collapse_rifle(user)

/obj/item/gun/projectile/heavysniper/proc/collapse_rifle(mob/user)
	to_chat(user, span_warning("You begin removing \the [src]'s barrel."))
	task_timed(user, 4 SECONDS, src, src, PROC_REF(barrel_removed), list(user))

/obj/item/gun/projectile/heavysniper/proc/barrel_removed(mob/user)
	if(user.unEquip(src, force=1))
		to_chat(user, span_warning("You remove \the [src]'s barrel."))
		consume(src, user)
		var/obj/item/barrel = new /obj/item/sniper_rifle_part/barrel(user)
		var/obj/item/sniper_rifle_part/assembly = new /obj/item/sniper_rifle_part/trigger_group(user)
		var/obj/item/sniper_rifle_part/stock/stock = new(assembly)
		rel_set(assembly, nameof(assembly.stock), stock)
		assembly.part_count = 2
		assembly.update_build(user)
		user.put_in_any_hand_if_possible(assembly) || assembly.dropInto(user.loc)
		user.put_in_any_hand_if_possible(barrel) || barrel.dropInto(user.loc)


/obj/item/sniper_rifle_part
	name = "AM rifle part"
	desc = "A part of an antimateriel rifle."

	w_class = ITEMSIZE_NORMAL

	icon = 'icons/obj/gun.dmi'

	var/tmp/obj/item/sniper_rifle_part/barrel
	var/tmp/obj/item/sniper_rifle_part/stock
	var/tmp/obj/item/sniper_rifle_part/trigger_group
	var/part_count = 1


/obj/item/sniper_rifle_part/barrel
	name = "AM rifle barrel"
	icon_state = "heavysniper-barrel"

/obj/item/sniper_rifle_part/barrel/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(barrel), src)

/obj/item/sniper_rifle_part/stock
	name = "AM rifle stock"
	icon_state = "heavysniper-stock"

/obj/item/sniper_rifle_part/stock/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(stock), src)

/obj/item/sniper_rifle_part/trigger_group
	name = "AM rifle trigger assembly"
	icon_state = "heavysniper-trig"

/obj/item/sniper_rifle_part/trigger_group/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(trigger_group), src)

MSG_DEF_SELF(sniper_part/last_part, "you can't disassemble this further")

CAPABILITIES(/obj/item/sniper_rifle_part)
	op("use", in_hand(), needs(req(PROC_REF(can_disassemble_holds), because = MSG(sniper_part/last_part))), then(PROC_REF(interaction_self)))
	op("add_part", item(/obj/item/sniper_rifle_part), then(PROC_REF(interaction_item)))

/// Requirement: the part is more than one piece.
/obj/item/sniper_rifle_part/proc/can_disassemble_holds(datum/act/op/A)
	return part_count != 1

/// Old attack_self.
/obj/item/sniper_rifle_part/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You start disassembling \the [src]."))
	task_timed(user, 4 SECONDS, src, src, PROC_REF(disassembled), list(user))
	return OP_OK

/obj/item/sniper_rifle_part/proc/disassembled(mob/user)
	if(part_count == 1)
		return
	to_chat(user, span_notice("You disassemble \the [src]."))
	for(var/obj/item/sniper_rifle_part/P in list(barrel(), stock(), trigger_group()))
		if(P.barrel() != P)
			rel_clear(P, nameof(P.barrel))
		if(P.stock() != P)
			rel_clear(P, nameof(P.stock))
		if(P.trigger_group() != P)
			rel_clear(P, nameof(P.trigger_group))
		if(P != src)
			user.put_in_any_hand_if_possible(P) || P.dropInto(loc)
		P.part_count = 1

	update_build(user)

/// Old attackby.
/obj/item/sniper_rifle_part/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/sniper_rifle_part/part = A.held
	to_chat(user, span_notice("You begin adding \the [part] to \the [src]."))
	task_timed(user, 3 SECONDS, src, src, PROC_REF(part_added), list(part, user))
	return OP_PASS

/obj/item/sniper_rifle_part/proc/part_added(obj/item/sniper_rifle_part/A, mob/user)
	if(istype(A, /obj/item/sniper_rifle_part/trigger_group))
		if(A.part_count > 1 && src.part_count > 1)
			to_chat(user, span_warning("Disassemble one of these parts first!"))
			return

		if(!trigger_group())
			if(user.unEquip(A, force=1))
				rel_set(src, nameof(trigger_group), A)
		else
			to_chat(user, span_warning("There's already a trigger group!"))
			return

	else if(istype(A, /obj/item/sniper_rifle_part/barrel))
		if(!barrel())
			if(user.unEquip(A, force=1))
				rel_set(src, nameof(barrel), A)
		else
			to_chat(user, span_warning("There's already a barrel!"))
			return

	else if(istype(A, /obj/item/sniper_rifle_part/stock))
		if(!stock())
			if(user.unEquip(A, force=1))
				rel_set(src, nameof(stock), A)
		else
			to_chat(user, span_warning("There's already a stock!"))
			return

	A.forceMove(src)
	to_chat(user, span_notice("You install \the [A]."))

	if(A.barrel() && !src.barrel())
		rel_set(src, nameof(barrel), A.barrel())
	if(A.stock() && !src.stock())
		rel_set(src, nameof(stock), A.stock())
	if(A.trigger_group() && !src.trigger_group())
		rel_set(src, nameof(trigger_group), A.trigger_group())


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


/// the barrel this refers to (a relation view: null once it is deleted).
/obj/item/sniper_rifle_part/proc/barrel() as /obj/item/sniper_rifle_part
	return barrel

/// the trigger_group this refers to (a relation view: null once it is deleted).
/obj/item/sniper_rifle_part/proc/trigger_group() as /obj/item/sniper_rifle_part
	return trigger_group

/// the stock this refers to (a relation view: null once it is deleted).
/obj/item/sniper_rifle_part/proc/stock() as /obj/item/sniper_rifle_part
	return stock
