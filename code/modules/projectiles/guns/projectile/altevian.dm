/obj/item/gun/projectile/altevian
	name = "Altevian Rivet Repeater"
	desc = "An offensive ballistic weapon designed by the Altevian Hegemony commonly used for decompression and structural damage tactics. It's also pretty effective at personnel damage."
	magazine_type = /obj/item/ammo_magazine/sam48
	allowed_magazines = list(/obj/item/ammo_magazine/sam48)
	projectile_type = /obj/item/projectile/bullet/sam48
	icon_state = "altevian-repeater"
	item_state = "altevian-repeater"
	caliber = ".48"
	load_method = MAGAZINE

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/altevian/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-e"]")

/obj/item/ammo_magazine/sam48
	name = "ammo clip (SAM .48)"
	icon_state = "sam48"
	desc = "Standard Altevian Munition clip, caliber .48."
	caliber = ".48"
	ammo_type = /obj/item/ammo_casing/sam48
	mag_type = MAGAZINE
	MATERIAL_BULK(MAT_STEEL, 240)
	max_ammo = 5
	multiple_sprites = 1

/obj/item/ammo_casing/sam48
	desc = "A .48 bolt casing."
	caliber = ".48"
	projectile_type = /obj/item/projectile/bullet/sam48
	MATERIAL_BULK(MAT_STEEL, 30)

/obj/item/projectile/bullet/sam48
	fire_sound = SFX_WEAPONS_GUNSHOT4
	icon_state = "sam48"
	damage = 49
	hud_state = "pistol_special"
