/mob/living/simple_mob/animal/tyr/rainbow_fly
	name = "chromatic fly"
	desc = "A strange insect."
	icon_state = "firefly"
	icon_dead = "firefly_dead"
	endurance = 10 //One shotable by pratically anyweapon
	pass_flags = PASSTABLE
	movement_cooldown = 1


	mob_size = MOB_MINISCULE //need to click the tiny sprite

	projectiletype = /obj/item/projectile/energy/blob/rainbowfly
	projectile_dispersion = 8
	projectile_accuracy = -15
	base_attack_cooldown = 5

	glow_color = "#FF3300"
	light_color = "#FF3300"
	glow_range = 4
	glow_intensity = 4

	melee_damage_lower = 5
	melee_damage_upper = 5

	// dq_get_hovering(src) type-default moved to GLOB.dq_hovering_by_type

/obj/item/projectile/energy/blob/rainbowfly
	damage = 10
	splatter = TRUE
	my_chems = list(REAGENT_ID_CRYPTOBIOLIN)

/datum/life_system/special/animal/tyr/rainbow_fly
	mob_type = /mob/living/simple_mob/animal/tyr/rainbow_fly

/datum/life_system/special/animal/tyr/rainbow_fly/tick(mob/living/simple_mob/animal/tyr/rainbow_fly/self, datum/life_context/ctx)
	if(self.stat != DEAD)
		self.painbow_aura()
	..()

/mob/living/simple_mob/animal/tyr/rainbow_fly/proc/painbow_aura()
	for(var/mob/living/L in view(src, 7))
		L.status_at_least(EFFECT_DRUGGED, 10)
