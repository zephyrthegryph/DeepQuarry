/obj/structure/table/rack
	name = "rack"
	desc = "Different from the Middle Ages version."
	icon = 'icons/obj/objects.dmi'
	icon_state = "rack"
	can_plate = 0
	can_reinforce = 0
	flipped = -1

/obj/structure/table/rack/Initialize(mapload)
	. = ..()
	verbs -= /obj/structure/table/verb/do_flip
	verbs -= /obj/structure/table/proc/do_put

/obj/structure/table/rack/update_connections()
	return

/obj/structure/table/rack/update_desc()
	return

/obj/structure/table/rack/update_icon()
	if(material) //VOREStation Add for rack colors based on materials
		color = material.icon_colour
	return

/obj/structure/table/rack/holorack/dismantle(obj/item/tool/wrench/W, mob/user)
	to_chat(user, span_warning("You cannot dismantle \the [src]."))
	return


// === merged from rack_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/table/rack
	icon = 'icons/obj/objects_vr.dmi'

/obj/structure/table/rack/steel
	color = "#666666"

/obj/structure/table/rack/steel/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/rack/shelf
	name = "shelving"
	desc = "Some nice metal shelves."
	icon_state = "shelf"

/obj/structure/table/rack/shelf/steel
	color = "#666666"

/obj/structure/table/rack/shelf/steel/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	. = ..()

// SOMEONE should add cool overlay stuff to this
/obj/structure/table/rack/gun_rack
	name = "gun rack"
	desc = "Seems like you could prop up some rifles here."
	icon_state = "gunrack"

/obj/structure/table/rack/gun_rack/steel
	color = "#666666"

/obj/structure/table/rack/gun_rack/steel/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/rack/wood
	color = "#A1662F"

/obj/structure/table/rack/wood/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	. = ..()

/obj/structure/table/rack/shelf/wood
	color = "#A1662F"

/obj/structure/table/rack/shelf/wood/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	. = ..()

/obj/structure/table/rack/glamour
	color = "#fffbe6"

/obj/structure/table/rack/glamour/Initialize(mapload)
	material = get_material_by_name(MAT_GLAMOUR)
	. = ..()

/obj/structure/table/rack/shelf/glamour
	color = "#fffbe6"

/obj/structure/table/rack/shelf/glamour/Initialize(mapload)
	material = get_material_by_name(MAT_GLAMOUR)
	. = ..()
