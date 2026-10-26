//Updated
/datum/power/changeling/silence_sting
	name = "Silence Sting"
	desc = "We silently sting a human, completely silencing them for a short time."
	helptext = "Does not provide a warning to a victim that they have been stung, until they try to speak and cannot."
	enhancedtext = "Silence duration is extended."
	ability_icon_state = "ling_sting_mute"
	genomecost = 2
	allowduringlesserform = TRUE
	verbpath = /mob/proc/changeling_silence_sting

/mob/proc/changeling_silence_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Silence sting (10)"
	set desc="Sting target"
	return changeling_silence_sting_stage()

/mob/proc/changeling_silence_sting_stage(mob/living/carbon/selected_target)

	var/mob/living/carbon/T = changeling_sting(10, PROC_REF(changeling_silence_sting_target_answered), selected_target)
	var/datum/changeling/comp = is_changeling(src)
	if(!T)
		return FALSE
	add_attack_logs(src,T,"Silence sting (changeling)")
	var/duration = 30
	if(comp.recursive_enhancement)
		duration = duration + 10
		to_chat(src, span_notice("They will be unable to cry out in fear for a little longer."))
	T.status_adjust(STAT_MUTED, duration)
	feedback_add_details("changeling_powers","SS")
	return TRUE

/mob/proc/changeling_silence_sting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_silence_sting_stage(A.answer.value)
