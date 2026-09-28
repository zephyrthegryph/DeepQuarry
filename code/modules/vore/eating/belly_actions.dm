/obj/belly/proc/instant_digest(mob/user, mob/living/target)
	if(target.absorbed)
		to_chat(user, span_vwarning("\The [target] is absorbed, and cannot presently be digested."))
		return FALSE
	var/_answer_a1 = rerun_prompt(target, "a1", list("message" = "\The [user] is attempting to instantly digest you. Is this something you are okay with happening to you?", "title" = "Instant Digest", "choices" = list("No", "Yes")), PROC_REF(instant_digest), args)
	if(isnull(_answer_a1))
		return
	if(_answer_a1 != "Yes")
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
				SEND_SOUND(target, sound(get_sfx("classic_death_sounds")))
			else
				SEND_SOUND(target, sound(get_sfx("fancy_death_prey")))
		target.mind?.vore_death = TRUE
		handle_digestion_death(target)
	return TRUE

/obj/belly/proc/instant_break_bone(mob/user, mob/living/target)
	if(!ishuman(target))
		to_chat(user, span_vwarning("\The [target] has no breakable organs."))
		return FALSE
	if(target.absorbed)
		to_chat(user, span_vwarning("\The [target] is absorbed, and cannot presently be broken."))
		return FALSE
	var/_answer_a2 = rerun_prompt(target, "a2", list("message" = "\The [user] is attempting to break one of your bones. Is this something you are okay with happening to you?", "title" = "Break Bones", "choices" = list("No", "Yes")), PROC_REF(instant_break_bone), args)
	if(isnull(_answer_a2))
		return
	if(_answer_a2 != "Yes")
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
	var/_answer_a3 = rerun_prompt(target, "a3", list("message" = "\The [user] is attempting to instantly absorb you. Is this something you are okay with happening to you?", "title" = "Instant Absorb", "choices" = list("No", "Yes")), PROC_REF(instant_absorb), args)
	if(isnull(_answer_a3))
		return
	if(_answer_a3 != "Yes")
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
	var/_answer_a4 = rerun_prompt(target, "a4", list("message" = "\The [user] is attempting to instantly make you unconscious, you will be unable until ejected from the pred. Is this something you are okay with happening to you?", "title" = "Instant Knockout", "choices" = list("No", "Yes")), PROC_REF(instant_knockout), args)
	if(isnull(_answer_a4))
		return
	if(_answer_a4 != "Yes")
		to_chat(user, span_vwarning("\The [target] declined your knockout attempt."))
		to_chat(target, span_vwarning("You declined the knockout attempt."))
		return FALSE
	if(target.loc != src)
		to_chat(user, span_vwarning("\The [target] is no longer in \the [src]."))
		return FALSE
	target.status_adjust(EFFECT_SLEEPING, 500000)
	to_chat(target, span_vwarning("\The [user] has put you to sleep, you will remain unconscious until ejected from the belly."))
	return TRUE
