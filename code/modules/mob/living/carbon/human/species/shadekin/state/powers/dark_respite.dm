//Non-Canon on Virgo. Used downstream.
// Fixes a latent bug found while porting: the legacy verb's "you cannot manually end a Dark Respite triggered by an emergency warp" warning
// never actually blocked anything - it fell through into the same toggle-off code below regardless. Here that's a real requirement
// (ability_respite_endable), so the message and the behaviour finally agree. The op is part of the shadekin_dark capability (dark_maw.dm).

MSG_DEF_SELF(shadekin_ability/not_dark, "you can only trigger Dark Respite in the Dark")
MSG_DEF_SELF(shadekin_ability/respite_cooldown, "you can't use that so soon after an emergency warp")
MSG_DEF_SELF(shadekin_ability/respite_forced, "you cannot manually end a Dark Respite triggered by an emergency warp")

/mob/living/proc/ability_in_dark_respite_area(datum/act/op/A)
	return (istype(get_area(src), /area/shadekin)) ? null : /datum/msg/req_failed

/mob/living/proc/ability_respite_not_cooling_down(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return (!!SK && !SK.in_dark_respite) ? null : /datum/msg/req_failed

/// A Dark Respite that an emergency warp triggered can't be manually ended; one the player started can. Always TRUE when no respite is running
/// (there's nothing to end - ability_dark_respite then starts a fresh one).
/mob/living/proc/ability_respite_endable(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return /datum/msg/req_failed
	if(!has_body_effect(/datum/body_effect/dark_respite))
		return null
	return (!!SK.manual_respite) ? null : /datum/msg/req_failed

/// Toggles Dark Respite: ends a running one, or starts one.
/mob/living/proc/ability_dark_respite(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	if(has_body_effect(/datum/body_effect/dark_respite))
		to_chat(src, span_notice("You stop focusing the Dark on healing yourself."))
		SK.manual_respite = FALSE
		remove_body_effect_stack(/datum/body_effect/dark_respite)
		return OP_OK
	to_chat(src, span_notice("You start focusing the Dark on healing yourself. (Leave the dark or trigger the ability again to end this.)"))
	SK.manual_respite = TRUE
	apply_body_effect(/datum/body_effect/dark_respite)
	return OP_OK

/datum/body_effect/dark_respite
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "Dark Respite"

/datum/body_effect/dark_respite/on_start(mob/living/L)
	if(!L.get_shadekin_state())
		L.end_body_effect(type)

/datum/body_effect/dark_respite/on_tick(mob/living/L)
	var/datum/shadekin/SK = L.get_shadekin_state()
	if(!SK)
		L.end_body_effect(type)
		return
	var/mob/living/carbon/human/H
	if(istype(L, /mob/living/carbon/human))
		H = L
	var/in_dark = istype(get_area(H), /area/shadekin)
	update_respite_factors(L, in_dark, H?.nutrition > 0)

	if(in_dark)
		//Very good healing, but only in the Dark.
		L.mend(TREAT_BURN_CARE, 0.25)
		L.mend(TREAT_TISSUE_REPAIR, 3.25)
		L.mend(TREAT_ANTITOXIN, 0.25)
		if(H)
			for(var/obj/item/organ/internal/I in H.internal_organ_list())
				if(I.is_robotic())
					continue
				if(I.damage > 0)
					H.mend(TREAT_RESTORATION, 0.25, I)
				if(I.damage <= 5 && I.organ_tag == O_EYES)
					H.set_sdisabilities(H.sdisabilities & (~BLIND))
			for(var/obj/item/organ/external/O in H.organs)
				if(O.is_fractured())
					O.mend_fracture()		//Only works if the bone won't rebreak, as usual
				for(var/datum/affliction/wound/W in O.get_wounds())
					if(W.bleeding() || W.internal)
						W.heal_damage(3, TRUE)
						if(W.damage <= 0)
							O.remove_wound(W)
	else
		if(SK.manual_respite)
			to_chat(L, span_notice("As you leave the Dark, you stop focusing the Dark on healing yourself."))
			SK.manual_respite = FALSE
			L.end_body_effect(type)

/// The Dark numbs pain and fights infection; a fed body rebuilds blood.
/// Swaps between static tables, so the factors only recompute on a change.
/datum/body_effect/dark_respite/proc/update_respite_factors(mob/living/L, in_dark, fed)
	var/static/alist/dark_fed = alist(BF_PAIN_IMMUNITY = 1, BF_ANTIMICROBIAL = ANTIBIO_SUPER, BF_BLOOD_REGEN = 5)
	var/static/alist/dark_hungry = alist(BF_PAIN_IMMUNITY = 1, BF_ANTIMICROBIAL = ANTIBIO_SUPER)
	var/static/alist/light_fed = alist(BF_BLOOD_REGEN = 5)
	var/alist/wanted = in_dark ? (fed ? dark_fed : dark_hungry) : (fed ? light_fed : null)
	L.set_body_effect_factors(type, wanted)
