/*
 * Internal Slime organs.
 */

/obj/item/organ/internal/heart/grey/colormatch/slime
	name = "pneumatic network"
	desc = "A disgusting sac of goo."
	icon_state = "sac_slime"
	dead_icon = null
	standard_pulse_level = PULSE_NONE

/obj/item/organ/internal/heart/grey/colormatch/slime/organ_tick(cycles)
	..()
	if(!(QDELETED(src)) && !owner)
		visible_message(span_infoplain(span_bold("\The [src]") + " splatters!"))
		var/turf/T = get_turf(src)
		var/obj/effect/decal/cleanable/blood/B = new (T)

		B.set_basecolor(src.color)
		dissolved(src)

/obj/item/organ/internal/regennetwork
	name = "pneumoregenesis network"
	parent_organ = BP_TORSO
	organ_tag = O_REGBRUTE

	icon_state = "sac_slime"

	var/strain = 0	// The amount of stress this organ is under. Capped at min_broken_damage, usually half its max damage.

	COOLDOWN_DECLARE(strain_regen_cooldown_until)	// World time of the last increase in strain.
	var/strain_regen_cooldown = 5 MINUTES

CAPABILITIES(/obj/item/organ/internal/regennetwork)
	setup(PROC_REF(regen_colour_setup))

/// Setup after the Initialize() chain: takes the blood colour of the human it was placed in.
/obj/item/organ/internal/regennetwork/proc/regen_colour_setup()
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		set_color(H.species.get_blood_colour(H))

/obj/item/organ/internal/regennetwork/proc/get_strain_percent(cost)
	adjust_strain(cost)

	if((status & ORGAN_CUT_AWAY) || is_fractured() || (status & ORGAN_DEAD))
		return 1

	return round((strain / min_broken_damage) * 10) / 10

/obj/item/organ/internal/regennetwork/proc/adjust_strain(amount)
	if(amount < 0 && !COOLDOWN_FINISHED(src, strain_regen_cooldown_until))
		return

	else if(amount > 0)
		COOLDOWN_START(src, strain_regen_cooldown_until, strain_regen_cooldown)

	strain = CLAMP(strain + amount, 0, min_broken_damage)

/obj/item/organ/internal/regennetwork/organ_tick(cycles)
	..()

	if(!(QDELETED(src)) && !owner)
		visible_message(span_infoplain(span_bold("\The [src]") + " splatters!"))
		var/turf/T = get_turf(src)
		var/obj/effect/decal/cleanable/blood/B = new (T)

		B.set_basecolor(src.color)
		dissolved(src)

	if(src && !is_bruised())
		adjust_strain(-0.25 * max(0, (min_broken_damage - damage) / min_broken_damage)) // Decrease the current strain with respect to the current strain level.

/obj/item/organ/internal/regennetwork/burn
	name = "thermoregenesis network"
	organ_tag = O_REGBURN

/obj/item/organ/internal/regennetwork/oxy
	name = "respiroregenesis network"
	organ_tag = O_REGOXY

/obj/item/organ/internal/regennetwork/tox
	name = "toxoregenesis network"
	organ_tag = O_REGTOX


// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/heart/grey/colormatch/slime/life_step_idle()
	return FALSE

/obj/item/organ/internal/regennetwork/life_step_idle()
	return FALSE

