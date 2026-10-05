/datum/power/changeling/delayed_toxic_sting
	name = "Delayed Toxic Sting"
	desc = "We silently sting a biological, causing a significant amount of toxins after a few minutes, allowing us to not \
	implicate ourselves."
	helptext = "The toxin takes effect in about two minutes.  Multiple applications within the two minutes will not cause increased toxicity."
	enhancedtext = "The toxic damage is doubled."
	ability_icon_state = "ling_sting_del_toxin"
	genomecost = 1
	verbpath = /mob/proc/changeling_delayed_toxic_sting

/datum/body_effect/delayed_toxin_sting
	name = "delayed toxin injection"
	hidden = TRUE
	stacks = MODIFIER_STACK_FORBID
	on_expired_text = span_danger("You feel a burning sensation flowing through your veins!")

/datum/body_effect/delayed_toxin_sting/on_end(mob/living/L, expired)
	L.injure(INJURY_TOXIN, rand(20, 30))

/datum/body_effect/delayed_toxin_sting/strong/on_end(mob/living/L, expired)
	L.injure(INJURY_TOXIN, rand(40, 60))

/mob/proc/changeling_delayed_toxic_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Delayed Toxic Sting (20)"
	set desc = "Injects the target with a toxin that will take effect after a few minutes."
	return changeling_delayed_toxic_sting_stage()

/mob/proc/changeling_delayed_toxic_sting_stage(mob/living/carbon/selected_target)

	var/mob/living/carbon/T = changeling_sting(20, PROC_REF(changeling_delayed_toxic_sting_target_answered), selected_target)
	var/datum/changeling/comp = is_changeling(src)
	if(!T)
		return 0
	add_attack_logs(src,T,"Delayed toxic sting (chagneling)")
	var/type_to_give = /datum/body_effect/delayed_toxin_sting
	if(comp.recursive_enhancement)
		type_to_give = /datum/body_effect/delayed_toxin_sting/strong
		to_chat(src, span_notice("Our toxin will be extra potent, when it strikes."))

	T.apply_body_effect(type_to_give, 2 MINUTES)


	feedback_add_details("changeling_powers","DTS")
	return 1

/mob/proc/changeling_delayed_toxic_sting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_delayed_toxic_sting_stage(A.answer.value)
