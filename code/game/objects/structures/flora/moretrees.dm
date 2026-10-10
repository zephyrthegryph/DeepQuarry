/obj/structure/flora/tree/bigtree
	icon = 'icons/obj/flora/moretrees_vr.dmi'
	icon_state = "bigtree1"
	base_state = "tree"
	product = /obj/item/stack/material/log
	product_amount = 20
	max_integrity = 400
	pixel_x = -65
	pixel_y = -8
	layer = MOB_LAYER - 1
	shake_animation_degrees = 2

/obj/structure/flora/tree/bigtree/choose_icon_state(datum/roller/R)
	return "[base_state][R.number(1, 4)]"

/obj/structure/flora/tree/bigtree/Initialize(mapload)
	. = ..()

/obj/structure/flora/tree/bigtree/stump()
	if(is_stump)
		return

	set_is_stump(TRUE)
	set_density(FALSE)
	icon_state = "[icon_state]_stump"
	cut_overlays()
	set_light(0)

/obj/structure/flora/tree/bigtree/draw(datum/look/look)
	..()
	if(!is_stump)
		look.overlay(look_overlay_image('icons/obj/flora/moretrees_vr.dmi', "[look.state_so_far(src)]-b", plane = ABOVE_MOB_PLANE))
