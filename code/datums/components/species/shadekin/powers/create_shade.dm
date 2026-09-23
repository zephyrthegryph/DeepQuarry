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
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return (SK.shadekin_get_energy() >= 25) || "not enough energy for that ability"

/mob/living/proc/dq_do_create_shade(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return FALSE
	SK.shadekin_adjust_energy(-25)
	playsound(actor, 'sound/effects/bamf.ogg', 75, 1)
	actor.add_modifier(/datum/modifier/shadekin/create_shade, 20 SECONDS)
	return TRUE

/datum/modifier/shadekin/create_shade
	name = "Shadekin Shadegen"
	desc = "Darkness envelops you."
	mob_overlay_state = ""

	on_created_text = span_notice("You drag part of The Dark into realspace, enveloping yourself.")
	on_expired_text = span_warning("You lose your grasp on The Dark and realspace reasserts itself.")
	stacks = MODIFIER_STACK_EXTEND
	var/mob/living/my_kin

/datum/modifier/shadekin/create_shade/tick()
	var/datum/component/shadekin/SK = my_kin.get_shadekin_component()
	if(SK && SK.in_phase)
		expire()

/datum/modifier/shadekin/create_shade/on_applied()
	my_kin = holder
	holder.glow_toggle = TRUE
	holder.glow_range = 8
	holder.glow_intensity = -10
	holder.glow_color = "#FFFFFF"
	holder.set_light(8, -10, "#FFFFFF")

/datum/modifier/shadekin/create_shade/on_expire()
	holder.glow_toggle = initial(holder.glow_toggle)
	holder.glow_range = initial(holder.glow_range)
	holder.glow_intensity = initial(holder.glow_intensity)
	holder.glow_color = initial(holder.glow_color)
	holder.set_light(0)
	my_kin = null
