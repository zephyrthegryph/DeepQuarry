/obj/belly/proc/instant_digest(mob/user, mob/living/target)
	return instant_digest_stage(user, target, null)

/obj/belly/proc/instant_digest_stage(mob/user, mob/living/target, decision)
	if(target.absorbed)
		to_chat(user, span_vwarning("\The [target] is absorbed, and cannot presently be digested."))
		return FALSE
	if(isnull(decision))
		if(!ismob(target) || QDELETED(target))
			return
		open_request(src, /datum/prompt/choice/belly_instant_consent, PROC_REF(instant_digest_answered), answerer = target, subject = src, instigator = user, question = "\The [user] is attempting to instantly digest you. Is this something you are okay with happening to you?", title = "Instant Digest")
		return
	if(decision != "Yes")
		to_chat(user, span_vwarning("\The [target] declined your digest attempt."))
		to_chat(target, span_vwarning("You declined the digest attempt."))
		return FALSE
	// must be checked after alert
	if(target.loc != src)
		to_chat(user, span_vwarning("\The [target] is no longer in \the [src]."))
		return FALSE

	if(isliving(user))
		var/mob/living/l = user
		var/thismuch = (target.vitality() * target.get_endurance()) + 100
		if(ishuman(l))
			var/mob/living/carbon/human/h = l
			thismuch = thismuch * h.species.digestion_nutrition_modifier
		l.adjust_nutrition(thismuch)
	target.death()		// To make sure all on-death procs get properly called
	if(target)
		if(target.check_sound_preference(/datum/preference/toggle/digestion_noises))
			if(!fancy_vore)
				SEND_SOUND(target, sound(get_sfx(SFX_CLASSIC_DEATH_SOUNDS)))
			else
				SEND_SOUND(target, sound(get_sfx(SFX_FANCY_DEATH_PREY)))
		target.mind?.vore_death = TRUE
		handle_digestion_death(target)
	return TRUE

/obj/belly/proc/instant_break_bone(mob/user, mob/living/target)
	return instant_break_bone_stage(user, target, null)

/obj/belly/proc/instant_break_bone_stage(mob/user, mob/living/target, decision)
	if(!ishuman(target))
		to_chat(user, span_vwarning("\The [target] has no breakable organs."))
		return FALSE
	if(target.absorbed)
		to_chat(user, span_vwarning("\The [target] is absorbed, and cannot presently be broken."))
		return FALSE
	if(isnull(decision))
		if(!ismob(target) || QDELETED(target))
			return
		open_request(src, /datum/prompt/choice/belly_instant_consent, PROC_REF(instant_break_bone_answered), answerer = target, subject = src, instigator = user, question = "\The [user] is attempting to break one of your bones. Is this something you are okay with happening to you?", title = "Break Bones")
		return
	if(decision != "Yes")
		to_chat(user, span_vwarning("\The [target] declined your breaking bones attempt."))
		to_chat(target, span_vwarning("You declined the breaking bones attempt."))
		return FALSE
	if(target.loc != src)
		to_chat(user, span_vwarning("\The [target] is no longer in \the [src]."))
		return FALSE
	var/mob/living/carbon/human/human_target = target
	var/obj/item/organ/external/target_organ = pick(human_target.get_fracturable_organs())
	if(!target_organ)
		to_chat(user, span_vwarning("\The [target] has no breakable organs."))
		return FALSE
	to_chat(user, span_vwarning("You break [target]'s [target_organ]!"))
	target_organ.fracture()
	return TRUE

/obj/belly/proc/instant_absorb(mob/user, mob/living/target)
	return instant_absorb_stage(user, target, null)

/obj/belly/proc/instant_absorb_stage(mob/user, mob/living/target, decision)
	if(isnull(decision))
		if(!ismob(target) || QDELETED(target))
			return
		open_request(src, /datum/prompt/choice/belly_instant_consent, PROC_REF(instant_absorb_answered), answerer = target, subject = src, instigator = user, question = "\The [user] is attempting to instantly absorb you. Is this something you are okay with happening to you?", title = "Instant Absorb")
		return
	if(decision != "Yes")
		to_chat(user, span_vwarning("\The [target] declined your absorb attempt."))
		to_chat(target, span_vwarning("You declined the absorb attempt."))
		return FALSE
	if(target.loc != src)
		to_chat(user, span_vwarning("\The [target] is no longer in \the [src]."))
		return FALSE
	if(isliving(user))
		var/mob/living/l = user
		l.adjust_nutrition(target.nutrition)
		var/n = 0 - target.nutrition
		target.adjust_nutrition(n)
	absorb_living(target)
	return TRUE

/obj/belly/proc/instant_knockout(mob/user, mob/living/target)
	return instant_knockout_stage(user, target, null)

/obj/belly/proc/instant_knockout_stage(mob/user, mob/living/target, decision)
	if(isnull(decision))
		if(!ismob(target) || QDELETED(target))
			return
		open_request(src, /datum/prompt/choice/belly_instant_consent, PROC_REF(instant_knockout_answered), answerer = target, subject = src, instigator = user, question = "\The [user] is attempting to instantly make you unconscious, you will be unable until ejected from the pred. Is this something you are okay with happening to you?", title = "Instant Knockout")
		return
	if(decision != "Yes")
		to_chat(user, span_vwarning("\The [target] declined your knockout attempt."))
		to_chat(target, span_vwarning("You declined the knockout attempt."))
		return FALSE
	if(target.loc != src)
		to_chat(user, span_vwarning("\The [target] is no longer in \the [src]."))
		return FALSE
	target.status_adjust(STAT_SLEEPING, 500000)
	to_chat(target, span_vwarning("\The [user] has put you to sleep, you will remain unconscious until ejected from the belly."))
	return TRUE

/obj/belly/proc/instant_digest_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = instant_digest_accepted(A)
	SStgui.update_uis(src)
	return .

/obj/belly/proc/instant_digest_accepted(datum/act/request/A)
	var/datum/prompt/choice/belly_instant_consent/ask = A.answer
	return instant_digest_stage(ask.instigator, ask.answerer, ask.value)

/obj/belly/proc/instant_break_bone_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = instant_break_bone_accepted(A)
	SStgui.update_uis(src)
	return .

/obj/belly/proc/instant_break_bone_accepted(datum/act/request/A)
	var/datum/prompt/choice/belly_instant_consent/ask = A.answer
	return instant_break_bone_stage(ask.instigator, ask.answerer, ask.value)

/obj/belly/proc/instant_absorb_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = instant_absorb_accepted(A)
	SStgui.update_uis(src)
	return .

/obj/belly/proc/instant_absorb_accepted(datum/act/request/A)
	var/datum/prompt/choice/belly_instant_consent/ask = A.answer
	return instant_absorb_stage(ask.instigator, ask.answerer, ask.value)

/obj/belly/proc/instant_knockout_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = instant_knockout_accepted(A)
	SStgui.update_uis(src)
	return .

/obj/belly/proc/instant_knockout_accepted(datum/act/request/A)
	var/datum/prompt/choice/belly_instant_consent/ask = A.answer
	return instant_knockout_stage(ask.instigator, ask.answerer, ask.value)

/// The original requester's identity is captured weakly, as the old kept proc arguments were.
/datum/prompt/choice/belly_instant_consent
	timeout = 0
	buttons = TRUE
	choices = list("No", "Yes")
	var/mob/instigator
	var/instigator_expected = FALSE

CAPABILITIES(/datum/prompt/choice/belly_instant_consent)
	ref_one(nameof(instigator), /mob)

/datum/prompt/choice/belly_instant_consent/prepare(datum/act/A)
	. = ..()
	var/mob/captured = instigator
	instigator_expected = !isnull(captured)
	rel_clear(src, nameof(instigator))
	if(captured && !QDELETED(captured))
		rel_set(src, nameof(instigator), captured)

/datum/prompt/choice/belly_instant_consent/recheck_extra()
	. = ..()
	if(.)
		return
	if(instigator_expected && QDELETED(instigator))
		return "gone"
