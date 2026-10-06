/datum/power/changeling/deaf_sting
	name = "Deaf Sting"
	desc = "We silently sting a human, completely deafening them for a short time."
	enhancedtext = "Deafness duration is extended."
	ability_icon_state = "ling_sting_deafen"
	genomecost = 1
	allowduringlesserform = TRUE
	verbpath = /mob/proc/changeling_deaf_sting


/mob/proc/changeling_deaf_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Deaf sting (5)"
	set desc="Sting target:"
	return changeling_deaf_sting_stage()

/mob/proc/changeling_deaf_sting_stage(mob/living/carbon/selected_target)

	var/mob/living/carbon/T = changeling_sting(5, PROC_REF(changeling_deaf_sting_target_answered), selected_target)
	var/datum/changeling/comp = is_changeling(src)
	if(!T)	return 0
	add_attack_logs(src,T,"Deaf sting (changeling)")
	var/duration = 300
	if(comp.recursive_enhancement)
		duration = duration + 100
		to_chat(src, span_notice("They will be unable to hear for a little longer."))
	to_chat(T, span_danger("Your ears pop and begin ringing loudly!"))
	T.status_at_least(STAT_DEAFENED, CEILING(duration / LIFE_CYCLE, 1))
	feedback_add_details("changeling_powers","DS")
	return 1

/mob/proc/changeling_deaf_sting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_deaf_sting_stage(A.answer.value)
