/*
 * Snap pops
 */
/obj/item/toy/snappop
	name = "snap pop"
	desc = "Wow!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "snappop"
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/toy/snappop)
	configure(item_sounds(drop = TRAIT_NONE))

/obj/item/toy/snappop/throw_impact(atom/hit_atom)
	..()
	fx_sparks(src, 3)
	src.visible_message(span_warning("The [src.name] explodes!"),span_warning("You hear a snap!"))
	play_sfx(src, SFX_EFFECTS_SNAP)
	replace_with(src, /obj/effect/decal/cleanable/ash)

/obj/item/toy/snappop/Crossed(atom/movable/H as mob|obj)
	if(H.is_incorporeal())
		return
	if((ishuman(H))) //i guess carp and shit shouldn't set them off
		var/mob/living/carbon/M = H
		if(M.m_intent == I_RUN)
			to_chat(M, span_warning("You step on the snap pop!"))

			fx_sparks(src, 2, FALSE)
			src.visible_message(span_warning("The [src.name] explodes!"),span_warning("You hear a snap!"))
			play_sfx(src, SFX_EFFECTS_SNAP)
			replace_with(src, /obj/effect/decal/cleanable/ash)
