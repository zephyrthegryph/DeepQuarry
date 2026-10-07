/obj/structure/lightpost
	name = "lightpost"
	desc = "A homely lightpost."
	icon = 'icons/obj/32x64.dmi'
	icon_state = "lightpost"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	anchored = TRUE
	density = TRUE
	opacity = FALSE

	var/lit = TRUE // If true, will have a glowing overlay and lighting.
	var/festive = FALSE // If true, adds a festive bow overlay to it.

TRACKED(/obj/structure/lightpost, lit)
TRACKED(/obj/structure/lightpost, festive)

/// The glow and the light while it is lit, the bow when it is festive. The one emissive blocker is the atom's own (doc/rewrite/intended_changes.md).
/obj/structure/lightpost/draw(datum/look/look)
	..()
	var/base = look.state_so_far(src)
	if(lit)
		look.light(5, 1, "#E9E4AF")
		look.overlay(look_overlay_image(null, "[base]-glow", plane = PLANE_LIGHTING_ABOVE))
	else
		look.light_off()
	if(festive)
		look.overlay(look_overlay_image(null, "[base]-festive"))

/obj/structure/lightpost/unlit
	lit = FALSE

/obj/structure/lightpost/festive
	desc = "A homely lightpost adorned with festive decor."
	festive = TRUE

/obj/structure/lightpost/festive/unlit
	lit = FALSE
