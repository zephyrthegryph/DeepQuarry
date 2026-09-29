//////////////////////
///  CREATE SHADE  ///
//////////////////////
// Ported to the ability framework (doc/rewrite/rules.md §5).

/datum/interaction/ability/self/shadekin_create_shade
	id = ABILITY_ID_SHADEKIN_CREATE_SHADE
	name = "Create shade"
	category = ABILITY_CAT_UTILITY
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_shifted, "you can't use that while phase shifted"),
		REQ_RESOURCE(/mob/living/proc/dq_create_shade_afford),
	)
	effect = /mob/living/proc/dq_do_create_shade

// pay_cost() is deliberately trivial (see phase_shift.dm's comment): spending
// there would make the framework's post-pay_cost why_not() recheck fail
// against the now-lower balance. The spend happens in the effect instead.

/// TRUE if `actor` can afford the flat 25-energy cost, else a reason.
/mob/living/proc/dq_create_shade_afford(mob/living/actor, atom/target, obj/item/held)
	var/datum/shadekin/SK = actor.get_shadekin_state()
	if(!SK)
		return "you aren't shadekin"
	return (SK.shadekin_get_energy() >= 25) || "not enough energy for that ability"

/mob/living/proc/dq_do_create_shade(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/shadekin/SK = actor.get_shadekin_state()
	if(!SK)
		return FALSE
	SK.shadekin_adjust_energy(-25)
	play_sfx(actor, SFX_EFFECTS_BAMF)
	actor.apply_body_effect(/datum/body_effect/shadekin/create_shade, 20 SECONDS)
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
