/*
 * Surplus Rifle
 */
/obj/item/gun/projectile/shotgun/pump/surplus
	name = "surplus rifle"
	desc = "An ancient weapon from an era long past, crude in design, but still just as effective \
	as any modern interpretation. Uses 7.62mm rounds."
	icon_state = "surplus"
	item_state = "rifle"
	fire_sound = SFX_WEAPONS_GUNSHOT_GENERIC_RIFLE
	max_shells = 4
	caliber = "7.62mm" // Old(er) as shit rifle doesn't have very good tech.
	ammo_type = /obj/item/ammo_casing/a762
	load_method = SINGLE_CASING|SPEEDLOADER
	action_sound = SFX_WEAPONS_RIFLEBOLT
	pump_animation = "surplus-cycling"

CAPABILITIES(/obj/item/gun/projectile/shotgun/pump/surplus)
	configure(item_worn(slots = TRAIT_NONE))
