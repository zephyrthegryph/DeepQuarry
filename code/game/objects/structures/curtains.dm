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
		consume(src)
	else
		..(P, def_zone)

/// A hand or anything held draws it; a cyborg beside it too (the AI has no hands to draw it with).
/obj/structure/curtain/proc/toggled(datum/act/op/A)
	play_sfx(src, SFX_RUSTLE, 0.6)
	toggle()
	return OP_OK

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

MSG_DEF_SELF(curtain/cutting, "You start to cut the shower curtains.")
MSG_DEF_SELF(curtain/cut, "You cut the shower curtains.")

CAPABILITIES(/obj/structure/curtain)
	op("toggle", inputs(hand(), item(/obj/item)), label("Toggle"), then(PROC_REF(toggled)))
	op("silicon_toggle", remote(), label("Toggle"), when(req_actor_kind(/mob/living/silicon/robot)), needs(req_adjacent()), then(PROC_REF(toggled)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), label("Cut down"), wait(1 SECOND), begins(MSG(curtain/cutting)), says(MSG(curtain/cut)), then(PROC_REF(cut_down)))

/// The cutters' wait ran out: the curtain is plastic sheets.
/obj/structure/curtain/proc/cut_down(datum/act/op/A)
	replace_with(src, /obj/item/stack/material/plastic, 3)
	return OP_OK

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
