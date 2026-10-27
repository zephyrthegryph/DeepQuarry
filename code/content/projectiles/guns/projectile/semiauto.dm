/*
 * M1 Garand
 */
/obj/item/gun/projectile/garand
	name = "semi-automatic rifle"
	desc = "A vintage styled frontier rifle by Hedberg-Hammarstrom. The distinctive 'ping' is considered \
	traditional, though its origins are much debated. Uses 7.62mm rounds."
	icon_state = "garand"
	item_state = "rifle"
	w_class = ITEMSIZE_LARGE
	caliber = "7.62mm"
	load_method = MAGAZINE // ToDo: Make it so MAGAZINE, SPEEDLOADER and SINGLE_CASING can all be used on the same gun.
	magazine_type = /obj/item/ammo_magazine/m762enbloc
	allowed_magazines = list(/obj/item/ammo_magazine/m762enbloc)
	auto_eject = 1
	auto_eject_sound = SFX_WEAPONS_GARAND_PING

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/garand/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-e"]")

/*
 * Revolver Rifle
 *		Bastard child of a revolver and a semi-auto rifle.
 */
/obj/item/gun/projectile/revolvingrifle
	name = "revolving rifle"
	desc = "The Gungnir is a novel, antique idea brought into the modern era by Hedberg-Hammarstrom. \
	The semi-automatic revolving mechanism offers no real advantage, but some colonists swear by it. \
	Uses .44 magnum revolver rounds."
	icon_state = "revolvingrifle"
	item_state = "rifle"
	w_class = ITEMSIZE_LARGE
	caliber = ".44"
	handle_casings = CYCLE_CASINGS
	load_method = SINGLE_CASING|SPEEDLOADER
	max_shells = 6
	ammo_type = /obj/item/ammo_casing/a44/rifle

/*
 * Vintage Revolver Rifle
 */
/obj/item/gun/projectile/revolvingrifle/vintage
	name = "vintage revolving rifle"
	desc = "The Willhem is the Gungir's older cousin by Hedberg-Hammarstrom, the perfect collector piece. \
	The semi-automatic revolving mechanism offers no real advantage, but some colonists swear by it. \
	Uses .44 magnum revolver rounds."
	icon_state = "vintagerevolvingrifle"
