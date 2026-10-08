/obj/structure/closet/secure_closet/guncabinet
	name = "gun cabinet"
	icon = 'icons/obj/guncabinet.dmi'
	icon_state = "base"
	req_one_access = list(ACCESS_ARMORY)
	closet_appearance = null

/// The cabinet keeps its mapped sprite and draws its door and the guns behind it: one per laser or projectile gun it holds (up to three, the commoner kind
/// first), read from the slot without making the guns that are only declared.
/obj/structure/closet/secure_closet/guncabinet/closet_look(datum/look/look)
	if(opened)
		look.overlay("door_open")
		return
	var/lazors = 0
	var/shottas = 0
	for(var/kind in look.contents_of(CONTAINER_SLOT_INTERIOR, /obj/item/gun))
		if(ispath(kind, /obj/item/gun/energy))
			lazors++
		if(ispath(kind, /obj/item/gun/projectile))
			shottas++
	for(var/i in 0 to 2)
		if(lazors || shottas) // only make icons if we have one of the two types.
			var/gun_state
			if(lazors > shottas)
				lazors--
				gun_state = "laser"
			else if(shottas)
				shottas--
				gun_state = "projectile"
			look.overlay(look_overlay_image(icon, gun_state, pixel_x = i * 4))
	look.overlay("door")
	look.overlay("sealed", when = is_welded(src))
	if(broken)
		look.overlay("broken")
	else if(lock_locked(src))
		look.overlay("locked")
	else
		look.overlay("open")

/obj/structure/closet/secure_closet/guncabinet/excursion
	name = "expedition weaponry cabinet"
	req_one_access = list(ACCESS_EXPLORER,ACCESS_ARMORY) //CHOMP keep explo

/obj/structure/closet/secure_closet/guncabinet/excursion/Initialize(mapload)
	. = ..()
	for(var/i = 1 to 2)
		new /obj/item/gun/energy/locked/frontier(src)
	for(var/i = 1 to 2)
		new /obj/item/gun/energy/locked/frontier/holdout(src)
