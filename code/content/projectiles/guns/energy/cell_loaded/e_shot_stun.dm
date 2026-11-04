/obj/item/projectile/bullet/pellet/e_shot_stun
	icon_state = "spark"
	damage = 2
	agony = 20
	pellets = 6			//number of pellets
	range_step = 2		//projectile will lose a fragment each time it travels this distance. Can be a non-integer.
	base_spread = 90	//lower means the pellets spread more across body parts. If zero then this is considered a shrapnel explosion instead of a shrapnel cone
	spread_step = 10

CAPABILITIES(/obj/item/projectile/bullet/pellet/e_shot_stun)
	configure(item_combat(embed_chance = 0, injury_kind = INJURY_BLUNT))
	configure(item_combat(sharp = FALSE))
