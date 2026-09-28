/obj/structure/curtain
	name = "curtain"
	desc = "The show must go on! At least, until you close these."
	icon = 'icons/obj/curtain.dmi'
	icon_state = "closed"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	opacity = 1
	density = FALSE

/obj/structure/curtain/open
	icon_state = "open"
	plane = OBJ_PLANE
	layer = OBJ_LAYER
	opacity = 0

/obj/structure/curtain/bullet_act(obj/item/projectile/P, def_zone)
	if(!P.nodamage)
		visible_message(span_warning("[P] tears [src] down!"))
		qdel(src)
	else
		..(P, def_zone)

/obj/structure/curtain/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/curtain_toggle,
		/datum/interaction/entry_item/curtain_toggle_item,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Toggle", PROC_REF(curtain_silicon_toggle)))
	..()

/// Old attack_hand: open/close the curtain.
/datum/interaction/entry_hand/curtain_toggle
	id = "curtain_toggle"
	name = "Toggle"
	effect = /obj/structure/curtain/proc/interaction_toggle

/obj/structure/curtain/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	playsound(src, "rustle", 15, 1, -5)
	toggle()
	return TRUE

/// Old attack_ai: a cyborg next to it opens/closes it. Nothing for the AI.
/obj/structure/curtain/proc/curtain_silicon_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return TRUE
	if(!isrobot((user)))
		return TRUE
	playsound(src, "rustle", 15, 1, -5)
	toggle()
	return TRUE

/obj/structure/curtain/proc/toggle()
	set_opacity(!opacity)
	if(opacity)
		icon_state = "closed"
		plane = MOB_PLANE
		layer = ABOVE_MOB_LAYER
	else
		icon_state = "open"
		plane = OBJ_PLANE
		layer = OBJ_LAYER

/// Old attackby: same as attack_hand.
/datum/interaction/entry_item/curtain_toggle_item
	id = "curtain_toggle_item"
	name = "Toggle"
	effect = /obj/structure/curtain/proc/interaction_toggle

/obj/structure/curtain/wirecutter_act(mob/user, obj/item/P)
	playsound(src, P.usesound, 50, 1)
	to_chat(user, span_notice("You start to cut the shower curtains."))
	om_do_after(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(wirecutter_act_timed_done), done_args = list(user))
	return TRUE

/obj/structure/curtain/proc/wirecutter_act_timed_done(mob/user)
	to_chat(user, span_notice("You cut the shower curtains."))
	replace_with(src, /obj/item/stack/material/plastic, 3)

/obj/structure/curtain/black
	name = "black curtain"
	color = "#222222"

/obj/structure/curtain/medical
	name = "plastic curtain"
	color = "#B8F5E3"
	alpha = 200

/obj/structure/curtain/bed
	name = "bed curtain"
	color = "#854636"

/obj/structure/curtain/open/bed
	name = "bed curtain"
	color = "#854636"

/obj/structure/curtain/open/privacy
	name = "privacy curtain"
	color = "#B8F5E3"

/obj/structure/curtain/open/shower
	name = "shower curtain"
	color = "#ACD1E9"
	alpha = 200

/obj/structure/curtain/open/shower/engineering
	color = "#FFA500"

/obj/structure/curtain/open/shower/medical
	color = "#B8F5E3"

/obj/structure/curtain/open/shower/security
	color = "#AA0000"
