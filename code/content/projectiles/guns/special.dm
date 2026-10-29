/obj/item/projectile/mobbola
	name = "bola"
	icon_state = "bola"
	damage = 5
	muzzle_type = null
	hud_state = "monkey"

	combustion = FALSE

	modifier_type_to_apply = /datum/body_effect/entangled
	modifier_duration = 0.5 MINUTE

CAPABILITIES(/obj/item/projectile/mobbola)
	configure(item_combat(embed_chance = 0, injury_kind = INJURY_PAIN))
