//
// Paper Shredder Machine
//
/obj/machinery/papershredder
	name = "paper shredder"
	desc = "For those documents you don't want seen."
	icon = 'icons/obj/papershredder.dmi'
	icon_state = "shredder-off"
	var/shred_anim = "shredder-shredding"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 200
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	power_channel = EQUIP
	circuit = /obj/item/circuitboard/papershredder
	var/max_paper = 10
	var/paperamount = 0
	var/static/list/shred_amounts = list(
		/obj/item/photo = 1,
		/obj/item/shreddedp = 1,
		/obj/item/paper = 1,
		/obj/item/newspaper = 3,
		/obj/item/card/id = 3,
		/obj/item/paper_bundle = 3,
		)

/obj/machinery/papershredder/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()
	AddElement(/datum/element/climbable)

/obj/machinery/papershredder/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/papershredder_empty_into,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/papershredder_shred,
		/datum/interaction/machine_verb/papershredder_empty,
	)
	..()

/datum/interaction/machine_item/papershredder_empty_into
	id = "papershredder_empty_into"
	name = "Empty into"
	category = INTERACTION_CAT_EJECT
	held_type = /obj/item/storage
	effect = /obj/machinery/papershredder/proc/interaction_empty_into

/obj/machinery/papershredder/proc/interaction_empty_into(mob/living/user, obj/item/storage/W, datum/interaction/interaction)
	empty_bin(user, W)
	return TRUE

/datum/interaction/machine_item/papershredder_shred
	id = "papershredder_shred"
	name = "Shred"
	held_type = list(/obj/item/photo, /obj/item/shreddedp, /obj/item/paper, /obj/item/newspaper, /obj/item/card/id, /obj/item/paper_bundle)
	effect = /obj/machinery/papershredder/proc/interaction_shred

/obj/machinery/papershredder/proc/interaction_shred(mob/living/user, obj/item/W, datum/interaction/interaction)
	var/paper_result
	for(var/shred_type in shred_amounts)
		if(istype(W, shred_type))
			paper_result = shred_amounts[shred_type]
	if(paper_result)
		if(inoperable())
			return TRUE // Need powah!
		if(paperamount == max_paper)
			to_chat(user, span_warning("\The [src] is full; please empty it before you continue."))
			return TRUE
		paperamount += paper_result
		user.drop_from_inventory(W)
		qdel(W)
		playsound(src, 'sound/items/pshred.ogg', 75, 1)
		flick(shred_anim, src)
		if(paperamount > max_paper)
			to_chat(user,span_danger("\The [src] was too full, and shredded paper goes everywhere!"))
			for(var/i=(paperamount-max_paper);i>0;i--)
				var/obj/item/shreddedp/SP = get_shredded_paper()
				SP.loc = get_turf(src)
				SP.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),1,5)
			paperamount = max_paper
		update_icon()
		return TRUE
	return FALSE

/datum/interaction/machine_verb/papershredder_empty
	id = "papershredder_empty"
	name = "Empty bin"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_ACTOR, /obj/machinery/papershredder/proc/actor_can_empty, "you can't do that right now"), REQ_ON(PRED_TARGET, /obj/machinery/papershredder/proc/has_paper, "it is empty"))
	effect = /obj/machinery/papershredder/proc/interaction_empty

/obj/machinery/papershredder/proc/actor_can_empty(mob/actor, atom/target, obj/item/held)
	return !(actor.stat || actor.restrained() || actor.weakened || actor.paralysis || actor.lying || actor.stunned)

/obj/machinery/papershredder/proc/has_paper(mob/actor, atom/target, obj/item/held)
	return paperamount > 0

/obj/machinery/papershredder/proc/interaction_empty(mob/user, obj/item/held, datum/interaction/interaction)
	empty_bin(user)
	return TRUE

/obj/machinery/papershredder/proc/empty_bin(mob/living/user, obj/item/storage/empty_into)

	// Sanity.
	if(empty_into && !istype(empty_into))
		empty_into = null

	if(empty_into && empty_into.contents.len >= empty_into.storage_slots)
		to_chat(user, span_notice("\The [empty_into] is full."))
		return

	while(paperamount)
		var/obj/item/shreddedp/SP = get_shredded_paper()
		if(!SP) break
		if(empty_into)
			empty_into.handle_item_insertion(SP)
			if(empty_into.contents.len >= empty_into.storage_slots)
				break
	if(empty_into)
		if(paperamount)
			to_chat(user, span_notice("You fill \the [empty_into] with as much shredded paper as it will carry."))
		else
			to_chat(user, span_notice("You empty \the [src] into \the [empty_into]."))

	else
		to_chat(user, span_notice("You empty \the [src]."))
	update_icon()

/obj/machinery/papershredder/proc/get_shredded_paper()
	if(!paperamount)
		return
	paperamount--
	return new /obj/item/shreddedp(get_turf(src))

/obj/machinery/papershredder/power_change()
	..()
	spawn(rand(0,15))
		update_icon()

/obj/machinery/papershredder/update_icon()
	cut_overlays()
	if(operable())
		icon_state = "shredder-on"
	else
		icon_state = "shredder-off"
	// Fullness overlay
	add_overlay("shredder-[max(0,min(5,FLOOR(paperamount/max_paper*5, 1)))]")
	if (panel_open)
		add_overlay("panel_open")

//
// Shredded Paper Item
//

/obj/item/shreddedp
	name = "shredded paper"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "shredp"
	throwforce = 0
	w_class = ITEMSIZE_TINY
	throw_range = 3
	throw_speed = 1

/obj/item/shreddedp/Initialize(mapload)
	. = ..()
	pixel_x = rand(-5,5)
	pixel_y = rand(-5,5)
	if(prob(65)) color = pick("#BABABA","#7F7F7F")

/obj/item/shreddedp/attackby(obj/item/W as obj, mob/user)
	if(istype(W, /obj/item/flame/lighter))
		burnpaper(W, user)
	else
		..()

/obj/item/shreddedp/proc/burnpaper(obj/item/flame/lighter/P, mob/user)
	if(user.restrained())
		return
	if(!P.lit)
		to_chat(user, span_warning("\The [P] is not lit."))
		return
	user.visible_message(span_warning("\The [user] holds \the [P] up to \the [src]. It looks like [user.p_theyre()] trying to burn it!"), \
		span_warning("You hold \the [P] up to \the [src], burning it slowly."))
	if(!do_after(user, 2 SECONDS, target = src))
		to_chat(user, span_warning("You must hold \the [P] steady to burn \the [src]."))
		return
	user.visible_message(span_danger("\The [user] burns right through \the [src], turning it to ash. It flutters through the air before settling on the floor in a heap."), \
		span_danger("You burn right through \the [src], turning it to ash. It flutters through the air before settling on the floor in a heap."))
	FireBurn()

/obj/item/shreddedp/proc/FireBurn()
	var/mob/living/M = loc
	if(istype(M))
		M.drop_from_inventory(src)
	new /obj/effect/decal/cleanable/ash(get_turf(src))
	qdel(src)
