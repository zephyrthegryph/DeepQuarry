////////////// PTR-7 Anti-Materiel Rifle //////////////

/obj/item/gun/projectile/heavysniper/collapsible

CAPABILITIES(/obj/item/gun/projectile/heavysniper/collapsible)
	op("collapsible_sniper_verb_take_down", menu(), label("Disassemble Rifle"), needs(carried(), req(PROC_REF(rifle_empty), because = MSG(sniper/empty_first))), begins(MSG(sniper/removing_barrel)), wait(4 SECONDS), then(PROC_REF(barrel_removed)))

MSG_DEF_SELF(sniper/empty_first, span_warning("You need to empty the rifle to break it down."))
MSG_DEF_SELF(sniper/removing_barrel, span_warning("You begin removing %T%'s barrel."))

/// Requirement: no round is chambered.
/obj/item/gun/projectile/heavysniper/collapsible/proc/rifle_empty(datum/act/op/A)
	return (!chambered) ? null : MSG(sniper/empty_first)

/obj/item/gun/projectile/heavysniper/proc/barrel_removed(datum/act/op/A)
	var/mob/user = A.actor
	if(user.unEquip(src, force=1))
		to_chat(user, span_warning("You remove \the [src]'s barrel."))
		consume(src, user)
		var/obj/item/barrel = new /obj/item/sniper_rifle_part/barrel(user)
		var/obj/item/sniper_rifle_part/assembly = new /obj/item/sniper_rifle_part/trigger_group(user)
		var/obj/item/sniper_rifle_part/stock/stock = new(assembly)
		rel_set(assembly, nameof(assembly.stock), stock)
		assembly.set_part_count(2)
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

TRACKED(/obj/item/sniper_rifle_part, part_count)
MSG_DEF_SELF(sniper_part/last_part, "you can't disassemble this further")

CAPABILITIES(/obj/item/sniper_rifle_part)
	op("use", in_hand(), needs(req(PROC_REF(can_disassemble_holds))), begins(MSG(sniper_part/disassembling)), wait(4 SECONDS), then(PROC_REF(disassembled)))
	op("add_part", item(/obj/item/sniper_rifle_part), begins(PROC_REF(adding_text)), wait(3 SECONDS), then(PROC_REF(part_added)))

MSG_DEF_SELF(sniper_part/disassembling, span_notice("You start disassembling %T%."))

/// The line names the part being added.
/obj/item/sniper_rifle_part/proc/adding_text(datum/act/op/A)
	return msg_text(span_notice("You begin adding [A.held] to %T%."))

/// Requirement: the part is more than one piece.
/obj/item/sniper_rifle_part/proc/can_disassemble_holds(datum/act/op/A)
	return (part_count != 1) ? null : MSG(sniper_part/last_part)

/obj/item/sniper_rifle_part/proc/disassembled(datum/act/op/A)
	var/mob/user = A.actor
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
		P.set_part_count(1)

	update_build(user)

/obj/item/sniper_rifle_part/proc/part_added(datum/act/op/op_act)
	var/obj/item/sniper_rifle_part/A = op_act.held
	var/mob/user = op_act.actor
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


	set_part_count(A.part_count + src.part_count)
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
