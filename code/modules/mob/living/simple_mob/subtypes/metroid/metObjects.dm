/*
//Objects related to the Metroids.
*/

//Projectile for the Metroids.
/obj/item/projectile/energy/metroidacid
	name = "metroid acid"
	icon_state = "neurotoxin"
	damage = 10
	injury_kind = INJURY_TOXIN
	agony = 10
	armor_penetration = 50

//EGG! Metroid egg and its mechanics. Ripped from spiders.
/obj/effect/metroid/egg
	name = "egg cluster"
	desc = "It seems to pulse slightly with an inner life"
	icon = 'icons/mob/metroid/small.dmi'
	icon_state = "egg"
	var/amount_grown = 0
	var/metroid_type = /mob/living/simple_mob/metroid/juvenile/baby

/obj/effect/metroid/egg/Initialize(mapload, atom/parent)
	get_light_and_color(parent)
	. = ..()
	pixel_x = rand(3,-3)
	pixel_y = rand(3,-3)
	om_after(src, egg_hatch_steps() * 2 SECONDS, PROC_REF(hatch)) // ALLOW(decl): the hatch delay is computed per instance from the egg's steps, which a declaration cannot express

/// Hatches (its growth timer).
/obj/effect/metroid/egg/proc/hatch()
	if(QDELETED(src))
		return
	amount_grown = 100
	if(amount_grown >= 100)
		replace_with(src, metroid_type, src)
