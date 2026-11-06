/*
 * Crossbow
 */
/obj/item/gun/energy/crossbow
	name = "mini energy-crossbow"
	desc = "A weapon favored by many mercenary stealth specialists."
	icon = 'icons/obj/gun.dmi' // Gun Sprites
	icon_state = "crossbow"
	w_class = ITEMSIZE_SMALL
	item_state = "crossbow"
	MATERIAL_BULK(MAT_STEEL, 2000)
	silenced = 1
	projectile_type = /obj/item/projectile/energy/bolt
	charge_cost = 480
	cell_type = /obj/item/cell/device/weapon/recharge
	battery_lock = 1
	charge_meter = 0

/obj/item/gun/energy/crossbow/ninja
	name = "energy dart thrower"
	projectile_type = /obj/item/projectile/energy/dart

/obj/item/gun/energy/crossbow/largecrossbow
	name = "energy crossbow"
	desc = "A weapon favored by mercenary infiltration teams."
	icon_state = "crossbowlarge"
	w_class = ITEMSIZE_LARGE
	MATERIAL_BULK(MAT_STEEL, 200000)
	projectile_type = /obj/item/projectile/energy/bolt/large

CAPABILITIES(/obj/item/gun/energy/crossbow/largecrossbow)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_combat(force = 10))
