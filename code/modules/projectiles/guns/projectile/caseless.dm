/obj/item/gun/projectile/caseless/prototype
	name = "prototype caseless rifle"
	desc = "The GC1 is a rifle cooked up in Gilthari Exports's R&D labs that operates with barely comprehensible clockwork internals. Uses solid phoron 5mm caseless rounds."
	description_fluff = "Gilthari is Sol’s premier supplier of luxury goods, specializing in extracting money from the rich and successful. \
	The GC1 is currently undergoing limited consumer trials, and is firmly aimed at a segment of the enthusiast market with more money than sense."
	icon_state = "caseless"
	item_state = "caseless"
	w_class = ITEMSIZE_HUGE //.
	caliber = "5mm caseless"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = null // R&D builds this. Starts unloaded.
	allowed_magazines = list(/obj/item/ammo_magazine/m5mmcaseless)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/caseless/prototype/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-empty"]")

/obj/item/gun/projectile/caseless/prototype/loaded
	magazine_type = /obj/item/ammo_magazine/m5mmcaseless
