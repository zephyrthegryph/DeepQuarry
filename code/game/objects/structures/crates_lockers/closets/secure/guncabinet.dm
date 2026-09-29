/obj/structure/closet/secure_closet/guncabinet
	name = "gun cabinet"
	icon = 'icons/obj/guncabinet.dmi'
	icon_state = "base"
	req_one_access = list(ACCESS_ARMORY)
	closet_appearance = null

/obj/structure/closet/secure_closet/guncabinet/Initialize(mapload)
	. = ..()
	update_icon()

/obj/structure/closet/secure_closet/guncabinet/toggle()
	..()
	update_icon()

APPEARANCE_NONE(/obj/structure/closet/secure_closet/guncabinet)
DECLARE_APPEARANCE_PROC(/obj/structure/closet/secure_closet/guncabinet, PROC_REF(appearance_overlays), list())
/obj/structure/closet/secure_closet/guncabinet/appearance_overlays()
	. = list()
	if(opened)
		. += "door_open"
	else
		var/lazors = 0
		var/shottas = 0
		latent_materialize_all() // a walk needs real things (C5)
		for (var/obj/item/gun/G in contents) // ALLOW(latent): materialized above
			if (istype(G, /obj/item/gun/energy))
				lazors++
			if (istype(G, /obj/item/gun/projectile))
				shottas++
		for (var/i = 0 to 2)
			if(lazors || shottas) // only make icons if we have one of the two types.
				var/image/gun = image(icon(src.icon))
				if (lazors > shottas)
					lazors--
					gun.icon_state = "laser"
				else if (shottas)
					shottas--
					gun.icon_state = "projectile"
				gun.pixel_x = i*4
				. += gun

		. += "door"

		if(sealed)
			. += "sealed"

		if(broken)
			. += "broken"
		else if (locked)
			. += "locked"
		else
			. += "open"

/obj/structure/closet/secure_closet/guncabinet/excursion
	name = "expedition weaponry cabinet"
	req_one_access = list(ACCESS_EXPLORER,ACCESS_ARMORY) //CHOMP keep explo

/obj/structure/closet/secure_closet/guncabinet/excursion/Initialize(mapload)
	. = ..()
	for(var/i = 1 to 2)
		new /obj/item/gun/energy/locked/frontier(src)
	for(var/i = 1 to 2)
		new /obj/item/gun/energy/locked/frontier/holdout(src)
