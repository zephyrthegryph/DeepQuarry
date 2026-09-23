//Non-Canon on Virgo. Used downstream.
// Ported to the ability framework (doc/rewrite/rules.md §5). Fixes a latent
// bug found while porting: the legacy verb's "you cannot manually end a Dark
// Respite triggered by an emergency warp" warning never actually blocked
// anything - it fell through into the same toggle-off code below regardless.
// Here that's a real requirement (dq_pred_respite_endable), so the message
// and the behaviour finally agree.

/datum/interaction/ability/self/shadekin_dark_respite
	id = ABILITY_ID_SHADEKIN_DARK_RESPITE
	name = "Dark respite"
	category = ABILITY_CAT_UTILITY
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_vr, "the VR systems cannot comprehend this power"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_shifted, "you can't use that while phase shifted"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_in_dark_respite_area, "you can only trigger Dark Respite in the Dark"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_respite_not_cooling_down, "you can't use that so soon after an emergency warp"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_respite_endable, "you cannot manually end a Dark Respite triggered by an emergency warp"),
	)
	effect = /mob/living/proc/dq_do_dark_respite

/mob/living/proc/dq_pred_not_shifted(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return !SK.in_phase || "you can't use that while phase shifted"

/mob/living/proc/dq_pred_in_dark_respite_area(mob/living/actor, atom/target, obj/item/held)
	return istype(get_area(actor), /area/shadekin) || "you can only trigger Dark Respite in the Dark"

/mob/living/proc/dq_pred_respite_not_cooling_down(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return !SK.in_dark_respite || "you can't use that so soon after an emergency warp"

/// A Dark Respite that an emergency warp triggered can't be manually ended;
/// one the player started can. Always TRUE when no respite is running (there's
/// nothing to end - dq_do_dark_respite then starts a fresh one).
/mob/living/proc/dq_pred_respite_endable(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	if(!actor.has_modifier_of_type(/datum/modifier/dark_respite))
		return TRUE
	return SK.manual_respite || "you cannot manually end a Dark Respite triggered by an emergency warp"

/// Toggles Dark Respite: ends a running one, or starts one.
/mob/living/proc/dq_do_dark_respite(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return FALSE
	if(actor.has_modifier_of_type(/datum/modifier/dark_respite))
		to_chat(actor, span_notice("You stop focusing the Dark on healing yourself."))
		SK.manual_respite = FALSE
		actor.remove_a_modifier_of_type(/datum/modifier/dark_respite)
		return TRUE
	to_chat(actor, span_notice("You start focusing the Dark on healing yourself. (Leave the dark or trigger the ability again to end this.)"))
	SK.manual_respite = TRUE
	actor.add_modifier(/datum/modifier/dark_respite)
	return TRUE

/datum/modifier/dark_respite
	name = "Dark Respite"
	var/datum/component/shadekin/SK

// Override this for special effects when it gets added to the mob.
/datum/modifier/dark_respite/on_applied()
	SK = holder.get_shadekin_component()
	if(!SK)
		expire()
	return

/datum/modifier/dark_respite/tick()
	if(!SK)
		expire()
		return
	var/mob/living/carbon/human/H
	if(istype(holder, /mob/living/carbon/human))
		H = holder
	var/in_dark = istype(get_area(H), /area/shadekin)
	update_respite_factors(in_dark, H?.nutrition > 0)

	if(in_dark)
		//Very good healing, but only in the Dark.
		holder.mend(TREAT_BURN_CARE, 0.25)
		holder.mend(TREAT_TISSUE_REPAIR, 3.25)
		holder.mend(TREAT_ANTITOXIN, 0.25)
		if(H)
			for(var/obj/item/organ/internal/I in H.internal_organs)
				if(I.robotic >= ORGAN_ROBOT)
					continue
				if(I.damage > 0)
					H.mend(TREAT_RESTORATION, 0.25, I)
				if(I.damage <= 5 && I.organ_tag == O_EYES)
					H.sdisabilities &= ~BLIND
			for(var/obj/item/organ/external/O in H.organs)
				if(O.status & ORGAN_BROKEN)
					O.mend_fracture()		//Only works if the bone won't rebreak, as usual
				for(var/datum/affliction/wound/W in O.get_wounds())
					if(W.bleeding() || W.internal)
						W.heal_damage(3, TRUE)
						if(W.damage <= 0)
							O.remove_wound(W)
	else
		if(SK.manual_respite)
			to_chat(holder, span_notice("As you leave the Dark, you stop focusing the Dark on healing yourself."))
			SK.manual_respite = FALSE
			expire()

/// The Dark numbs pain and fights infection; a fed body rebuilds blood.
/// Swaps between static tables, so the factors only recompute on a change.
/datum/modifier/dark_respite/proc/update_respite_factors(in_dark, fed)
	var/static/alist/dark_fed = alist(BF_PAIN_IMMUNITY = 1, BF_ANTIMICROBIAL = ANTIBIO_SUPER, BF_BLOOD_REGEN = 5)
	var/static/alist/dark_hungry = alist(BF_PAIN_IMMUNITY = 1, BF_ANTIMICROBIAL = ANTIBIO_SUPER)
	var/static/alist/light_fed = alist(BF_BLOOD_REGEN = 5)
	var/alist/wanted = in_dark ? (fed ? dark_fed : dark_hungry) : (fed ? light_fed : null)
	if(wanted != factors)
		set_factors(wanted)

/datum/modifier/dark_respite/on_expire()
	SK = null
