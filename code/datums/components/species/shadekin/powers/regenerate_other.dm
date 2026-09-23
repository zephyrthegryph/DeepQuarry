//////////////////////////
///  REGENERATE OTHER  ///
//////////////////////////
// Ported to the ability framework (doc/rewrite/rules.md §5). This is a
// targeted ability, not a self one: the legacy verb picked its target from a
// tgui_input_list of nearby mobs (a picker built by hand, then re-validated
// because the pick was async). Here the target IS the click/Menu target - the
// Menu on a nearby mob already lists this, with its live cost and adjacency
// requirement, so there's no separate picker to keep in sync.

/datum/interaction/ability/shadekin_regenerate_other
	id = ABILITY_ID_SHADEKIN_REGENERATE_OTHER
	name = "Regenerate other"
	category = ABILITY_CAT_UTILITY
	requires = list(
		REQ_CONSCIOUS,
		REQ_NOT_SELF, // the legacy oview(1) target list never included yourself
		REQ_REACH(1),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_shifted, "you can't use that while phase shifted"),
		REQ_RESOURCE(/mob/living/proc/dq_regenerate_other_afford),
	)
	effect = /mob/living/proc/dq_do_regenerate_other

// pay_cost() is deliberately trivial (see phase_shift.dm's comment): spending
// there would make the framework's post-pay_cost why_not() recheck fail
// against the now-lower balance. The spend happens in the effect instead.

/// TRUE if `actor` can afford the flat 50-energy cost, else a reason.
/mob/living/proc/dq_regenerate_other_afford(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return (SK.shadekin_get_energy() >= 50) || "not enough energy for that ability"

/// Mends `src` (the target), announced by `actor` (the healer).
/mob/living/proc/dq_do_regenerate_other(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	var/mob/living/L = actor
	var/datum/component/shadekin/SK = L.get_shadekin_component()
	if(!SK)
		return FALSE
	SK.shadekin_adjust_energy(-50)
	playsound(L, 'sound/effects/EMPulse.ogg', 75, 1)
	add_modifier(/datum/modifier/shadekin/heal_boop, 1 MINUTE)
	actor.visible_message(span_notice("\The [actor] gently places a hand on \the [src]..."))
	actor.face_atom(src)
	return TRUE

/datum/modifier/shadekin/heal_boop
	name = "Shadekin Regen"
	desc = "You feel serene and well rested."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_notice("Sparkles begin to appear around you, and all your ills seem to fade away.")
	on_expired_text = span_notice("The sparkles have faded, although you feel much healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/modifier/shadekin/heal_boop/tick()
	var/mended = holder.mend(TREAT_TISSUE_REPAIR, 2)
	mended += holder.mend(TREAT_BURN_CARE, 2)
	mended += holder.mend(TREAT_ANTITOXIN, 2)
	mended += holder.mend(TREAT_OXYGENATION, 2)
	mended += holder.mend(TREAT_GENETIC_REPAIR, 2)
	if(!mended) // No point existing if the spell can't heal.
		expire()
		return
