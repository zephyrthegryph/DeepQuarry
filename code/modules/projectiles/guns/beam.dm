//Damage values back to old values for combat refactor walkback, keeping simplemob bonus damage.
/obj/item/projectile/beam/phaser //The "medium" phaser beam.
	mob_bonus_damage = 10

CAPABILITIES(/obj/item/projectile/beam/phaser)
	configure(light_glow(color = "#F18F12"))

/obj/item/projectile/beam/phaser/light
	mob_bonus_damage = 5

CAPABILITIES(/obj/item/projectile/beam/phaser/light)
	configure(light_glow(range = 1.5, power = 0.3))

/obj/item/projectile/beam/phaser/heavy
	mob_bonus_damage = 12

CAPABILITIES(/obj/item/projectile/beam/phaser/heavy)
	configure(light_glow(range = 3, power = 1))

/obj/item/projectile/beam/phaser/heavy/cannon
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

CAPABILITIES(/obj/item/projectile/beam/prismatic)
	configure(light_glow(color = "#00C6FF"))
