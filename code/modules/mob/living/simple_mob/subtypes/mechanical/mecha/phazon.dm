// Phazons are weird.

/mob/living/simple_mob/mechanical/mecha/combat/phazon
	name = "phazon"
	desc = "An extremly enigmatic exosuit."
	icon_state = "phazon"
	movement_cooldown = 1.5
	wreckage = /obj/structure/loot_pile/mecha/phazon

	endurance = 200
	deflect_chance = 30
	armor_spec = "melee=30;bullet=30;laser=30;energy=30;bomb=30;bio=100;rad=100"
	projectiletype = /obj/item/projectile/energy/declone


// === merged from phazon_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/mechanical/mecha/combat/phazon
	projectiletype = /obj/item/projectile/bullet/magnetic/fuelrod


/mob/living/simple_mob/mechanical/mecha/combat/phazon/advanced
	name = "Advanced phazon"
	movement_cooldown = 1
	wreckage = /obj/structure/loot_pile/mecha/phazon
	color = "#ffffff"

	endurance = 500
	evasion = 10

	special_attack_min_range = 1
	special_attack_max_range = 9
	special_attack_cooldown = 30 SECONDS
	size_multiplier = 1.25
	shock_resist = 0.5
	ranged_attack_delay = 1 SECONDS
	projectilesound = 'sound/weapons/gauss_shoot.ogg'
	damage_fatigue_mult = 0

	projectiletype = /obj/item/projectile/bullet/rifle/a545/ap

/mob/living/simple_mob/mechanical/mecha/combat/phazon/advanced/do_special_attack(atom/A, stance)
	. = TRUE // So we don't fire a bolt as well.
	switch(stance)
		if(I_DISARM) // Side gun
			electric_defense(A)
		if(I_HURT) // Rockets
			launch_rockets(A)
		if(I_GRAB) // Micro-singulo
			launch_microsingularity(A)

/mob/living/simple_mob/mechanical/mecha/combat/phazon/advanced/proc/electric_defense(atom/target)

	// Telegraph our next move.
	Beam(target, icon_state = "sat_beam", time = 3.5 SECONDS, maxdistance = INFINITY)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% deploys a red missile rack!")))
	playsound(src, 'sound/effects/turret/move1.wav', 50, 1)
	rocket_volley(target, /obj/item/projectile/arc/explosive_rocket/big, 2, "\The [src] retracts the red missile rack.")

/obj/item/projectile/arc/explosive_rocket/big
	name = "rocket"
	icon_state = "mortar"
	color = "#FF0000"

/obj/item/projectile/arc/explosive_rocket/big/on_impact(turf/T)
	new /obj/effect/explosion(T) // Weak explosions don't produce this on their own, apparently.
	explosion(T, 1, 1, 1, adminlog = FALSE)

/mob/living/simple_mob/mechanical/mecha/combat/phazon/advanced/proc/launch_rockets(atom/target)

	// Telegraph our next move.
	Beam(target, icon_state = "sat_beam", time = 3.5 SECONDS, maxdistance = INFINITY)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% deploys a blue missile rack!")))
	playsound(src, 'sound/effects/turret/move1.wav', 50, 1)
	rocket_volley(target, /obj/item/projectile/arc/explosive_rocket, 2, "\The [src] retracts the blue missile rack.")

/obj/item/projectile/arc/explosive_rocket/blue
	name = "rocket"
	icon_state = "mortar"
	color = "#000066"

/obj/item/projectile/arc/explosive_rocket/blue/on_impact(turf/T)
	new /obj/effect/explosion(T) // Weak explosions don't produce this on their own, apparently.
	empulse(T, 1, 2, 3, 4)

/mob/living/simple_mob/mechanical/mecha/combat/phazon/advanced/proc/launch_microsingularity(atom/target)

	// Telegraph our next move.
	Beam(target, icon_state = "sat_beam", time = 3.5 SECONDS, maxdistance = INFINITY)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% deploys a yellow missile rack!")))
	playsound(src, 'sound/effects/turret/move1.wav', 50, 1)
	rocket_volley(target, /obj/item/projectile/arc/explosive_rocket/spread, 2, "\The [src] retracts the yellow missile rack.")

/obj/item/projectile/arc/explosive_rocket/spread
	name = "rocket"
	icon_state = "mortar"
	color = "#FFFF00"

/obj/item/projectile/arc/explosive_rocket/spread/on_impact(turf/T)
	new /obj/effect/explosion(T) // Weak explosions don't produce this on their own, apparently.
	explosion(T, 0, 0, 2, adminlog = FALSE)
