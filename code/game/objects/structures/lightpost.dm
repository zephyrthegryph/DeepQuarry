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

/obj/structure/lightpost/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)

	if(lit)
		look.light(5, 1, "#E9E4AF")
		var/image/glow = image(icon_state = "[drawn_state]-glow")
		glow.plane = PLANE_LIGHTING_ABOVE
		look.overlay(glow)
	else
		look.light_off()

	if(festive)
		var/image/bow = image(icon_state = "[drawn_state]-festive")
		look.overlay(bow)

/obj/structure/lightpost/unlit
	lit = FALSE

/obj/structure/lightpost/festive
	desc = "A homely lightpost adorned with festive decor."
	festive = TRUE

/obj/structure/lightpost/festive/unlit
	lit = FALSE
