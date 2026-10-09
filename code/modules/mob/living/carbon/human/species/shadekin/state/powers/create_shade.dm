//////////////////////
///  CREATE SHADE  ///
//////////////////////
// Part of the shadekin_utility capability (regenerate_other.dm).

/mob/living/proc/ability_can_afford_25(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return !!SK && SK.shadekin_get_energy() >= 25

/mob/living/proc/ability_create_shade(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	SK.shadekin_adjust_energy(-25)
	play_sfx(src, SFX_EFFECTS_BAMF)
	apply_body_effect(/datum/body_effect/shadekin/create_shade, 20 SECONDS)
	return OP_OK

/datum/body_effect/shadekin/create_shade, 20 SECONDS)
	return TRUE

/datum/body_effect/shadekin/create_shade
	tick_interval = 2 SECONDS
	name = "Shadekin Shadegen"
	desc = "Darkness envelops you."
	mob_overlay_state = ""

	on_created_text = span_notice("You drag part of The Dark into realspace, enveloping yourself.")
	on_expired_text = span_warning("You lose your grasp on The Dark and realspace reasserts itself.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/shadekin/create_shade/on_tick(mob/living/L)
	var/datum/shadekin/SK = L.get_shadekin_state()
	if(SK && SK.in_phase)
		L.end_body_effect(type)

/datum/body_effect/shadekin/create_shade/on_start(mob/living/L)
	L.set_glow_toggle(TRUE)
	L.set_glow_range(8)
	L.set_glow_intensity(-10)
	L.set_glow_color("#FFFFFF")
	L.set_light(8, -10, "#FFFFFF")

/datum/body_effect/shadekin/create_shade/on_end(mob/living/L, expired)
	L.set_glow_toggle(initial(L.glow_toggle))
	L.set_glow_range(initial(L.glow_range))
	L.set_glow_intensity(initial(L.glow_intensity))
	L.set_glow_color(initial(L.glow_color))
	L.set_light(0)
