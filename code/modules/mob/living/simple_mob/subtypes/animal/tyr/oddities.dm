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

	glow_color = "#FF3300"
	glow_range = 4
	glow_intensity = 4

	melee_damage_lower = 5
	melee_damage_upper = 5


CAPABILITIES(/mob/living/simple_mob/animal/tyr/rainbow_fly)
	configure(light_glow(color = "#FF3300"))
	configure(mob_movement(hovering = TRUE))
	configure(mob_kind(attack_cooldown = 5))

/obj/item/projectile/energy/blob/rainbowfly
	damage = 10
	splatter = TRUE

TYPE_TABLE(/obj/item/projectile/energy/blob/rainbowfly, blob_projectile_chems, list(REAGENT_ID_CRYPTOBIOLIN))

/mob/living/simple_mob/animal/tyr/rainbow_fly/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/tyr/rainbow_fly/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.painbow_aura()
	..()

/mob/living/simple_mob/animal/tyr/rainbow_fly/proc/painbow_aura()
	for(var/mob/living/L in view(src, 7))
		L.status_at_least(STAT_DRUGGED, 10)
