//Updated
/datum/power/changeling/blind_sting
	name = "Blind Sting"
	desc = "We silently sting a human, completely blinding them for a short time."
	enhancedtext = "Duration is extended."
	ability_icon_state = "ling_sting_blind"
	genomecost = 2
	allowduringlesserform = TRUE
	verbpath = /mob/proc/changeling_blind_sting

/mob/proc/changeling_blind_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Blind sting (20)"
	set desc="Sting target"
	return changeling_blind_sting_stage()

/mob/proc/changeling_blind_sting_stage(mob/living/carbon/selected_target)
	var/datum/changeling/comp = is_changeling(src)
	var/mob/living/carbon/T = changeling_sting(20, PROC_REF(changeling_blind_sting_target_answered), selected_target)
	if(!T)
		return FALSE
	add_attack_logs(src,T,"Blind sting (changeling)")
	to_chat(T, span_danger("Your eyes burn horrificly!"))
	var/duration = 30 SECONDS
	if(comp.recursive_enhancement)
		duration = duration + 15 SECONDS
		to_chat(src, span_notice("They will be deprived of sight for longer."))
	T.status_at_least(STAT_NEARSIGHTED, CEILING(duration / LIFE_CYCLE, 1))
	T.status_at_least(STAT_BLINDED, 10)
	T.status_set(STAT_BLURRY, 20)
	feedback_add_details("changeling_powers","BS")
	return TRUE


/mob/proc/changeling_blind_sting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_blind_sting_stage(A.answer.value)
