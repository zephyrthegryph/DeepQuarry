/obj/structure/table/rack
	name = "rack"
	desc = "Different from the Middle Ages version."
	icon = 'icons/obj/objects.dmi'
	icon_state = "rack"
	can_plate = 0
	can_reinforce = 0
	flipped = -1
	can_flip_verb = FALSE

/obj/structure/table/rack/update_connections()
	return

/obj/structure/table/rack/update_desc()
	return

/obj/structure/table/rack/look_parts(datum/look/look)
	if(material()) // for rack colors based on materials
		look.set_color(material().icon_colour)

/obj/structure/table/rack/holorack
	can_dismantle = FALSE

/obj/structure/table/rack
	icon = 'icons/obj/objects_vr.dmi'

/obj/structure/table/rack/steel
	plating_id = MAT_STEEL
	color = "#666666"

/obj/structure/table/rack/shelf
	name = "shelving"
	desc = "Some nice metal shelves."
	icon_state = "shelf"

/obj/structure/table/rack/shelf/steel
	plating_id = MAT_STEEL
	color = "#666666"

// SOMEONE should add cool overlay stuff to this
/obj/structure/table/rack/gun_rack
	name = "gun rack"
	desc = "Seems like you could prop up some rifles here."
	icon_state = "gunrack"

/obj/structure/table/rack/gun_rack/steel
	plating_id = MAT_STEEL
	color = "#666666"

/obj/structure/table/rack/wood
	plating_id = MAT_WOOD
	color = "#A1662F"

/obj/structure/table/rack/shelf/wood
	plating_id = MAT_WOOD
	color = "#A1662F"

/obj/structure/table/rack/glamour
	plating_id = MAT_GLAMOUR
	color = "#fffbe6"

/obj/structure/table/rack/shelf/glamour
	plating_id = MAT_GLAMOUR
	color = "#fffbe6"
