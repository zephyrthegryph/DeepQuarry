/*
 * Balloons
 */
/obj/item/toy/balloon
	name = "water balloon"
	desc = "A translucent balloon. There's nothing in it."
	icon = 'icons/obj/toy.dmi'
	icon_state = "waterballoon-e"

/obj/item/toy/balloon/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/toy/balloon/afterattack(atom/A as mob|obj, mob/user as mob, proximity)
	if(!proximity) return
	if (istype(A, /obj/structure/reagent_dispensers/watertank) && get_dist(src,A) <= 1)
		A.reagents.trans_to_obj(src, 10)
		to_chat(user, span_notice("You fill the balloon with the contents of [A]."))
		src.desc = "A translucent balloon with some form of liquid sloshing around in it."
	return

CAPABILITIES(/obj/item/toy/balloon)
	reagents(10)
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/toy/balloon/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(istype(O, /obj/item/reagent_containers/glass))
		if(O.reagents)
			if(O.reagents.total_volume < 1)
				to_chat(user, "The [O] is empty.")
			else if(O.reagents.total_volume >= 1)
				if(O.reagents.has_reagent(REAGENT_ID_PACID, 1))
					to_chat(user, "The acid chews through the balloon!")
					O.reagents.splash(user, reagents.total_volume)
					consume(src, user)
				else
					src.desc = "A translucent balloon with some form of liquid sloshing around in it."
					to_chat(user, span_notice("You fill the balloon with the contents of [O]."))
					O.reagents.trans_to_obj(src, 10)
	return OP_PASS

/obj/item/toy/balloon/throw_impact(atom/hit_atom)
	if(src.reagents.total_volume >= 1)
		src.visible_message(span_warning("\The [src] bursts!"),"You hear a pop and a splash.")
		src.reagents.touch_turf(get_turf(hit_atom))
		for(var/atom/A in get_turf(hit_atom))
			src.reagents.touch(A)
		set_icon_state("burst")
		expire(5)
	return

/obj/item/toy/balloon/draw(datum/look/look)
	..()
	if(src.reagents.total_volume >= 1)
		look.state("waterballoon")
	else
		look.state("waterballoon-e")
