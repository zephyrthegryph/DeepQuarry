//Damage values back to old values for combat refactor walkback, keeping simplemob bonus damage.
/obj/item/projectile/beam/phaser //The "medium" phaser beam.
	//damage = 10
	mob_bonus_damage = 10

/obj/item/projectile/beam/phaser/light
	//damage = 5
	mob_bonus_damage = 5

/obj/item/projectile/beam/phaser/heavy
	//damage = 12
	mob_bonus_damage = 12

/obj/item/projectile/beam/phaser/heavy/cannon
	//damage = 15
	mob_bonus_damage = 15

/obj/item/projectile/scatter/laser
	damage = 40 //Old 20

	submunition_spread_max = 40
	submunition_spread_min = 10

	submunitions = list(
		/obj/item/projectile/beam/prismatic = 4
		)

/obj/item/projectile/beam/prismatic
	name = "prismatic beam"
	icon_state = "omnilaser"
	damage = 10 //Old 5?
	damage_type = BURN
	check_armour = "laser"
	light_color = "#00C6FF"
