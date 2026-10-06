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

CAPABILITIES(/obj/effect/metroid/egg)
	param(nameof(laid_by), pos = 1, apply = PROC_REF(take_parent_look), keep = FALSE)
	rolls(ROLL_PIXEL, PIXEL_JITTER(3))
	after_init(PROC_REF(hatch_delay), then(PROC_REF(hatch_due)))

/// What laid the egg (its constructor param): it takes its light and colour.
/obj/effect/metroid/egg/var/tmp/atom/laid_by

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/metroid/egg/proc/take_parent_look(atom/parent)
	get_light_and_color(parent)

/// after_init(): the hatch delay, from the egg's steps.
/obj/effect/metroid/egg/proc/hatch_delay(datum/act/A)
	return egg_hatch_steps() * 2 SECONDS

/obj/effect/metroid/egg/proc/hatch_due(datum/act/timer/A)
	hatch()

/// Hatches (its growth timer).
/obj/effect/metroid/egg/proc/hatch()
	if(QDELETED(src))
		return
	amount_grown = 100
	if(amount_grown >= 100)
		replace_with(src, metroid_type, src)
