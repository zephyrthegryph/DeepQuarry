/obj/item/projectile/bullet
	damage = 25 //seems many bullets use this value for some reason

CAPABILITIES(/obj/item/projectile/bullet)
	configure(item_combat(injury_kind = INJURY_PIERCE))
	configure(item_combat(sharp = TRUE))

/obj/item/projectile/bullet/pistol/strong
	damage = 40

