//This only exists to be abused, so it's highly recommended to ensure this file is unchecked.
/datum/power/changeling/lsd_sting
	name = "Hallucination Sting"
	desc = "We evolve the ability to sting a target with a powerful hallunicationary chemical."
	helptext = "The target does not notice they have been stung.  The effect occurs after 30 to 60 seconds."
	genomecost = 3
	verbpath = /mob/proc/changeling_lsdsting

/mob/proc/changeling_lsdsting()
	set category = VERB_CAT_CHANGELING
	set name = "Hallucination Sting (15)"
	set desc = "Causes terror in the target."
	return changeling_lsdsting_stage()

/mob/proc/changeling_lsdsting_stage(mob/living/carbon/selected_target)

	var/mob/living/carbon/T = changeling_sting(15, PROC_REF(changeling_lsdsting_target_answered), selected_target)
	if(!T)
		return FALSE
	add_attack_logs(src,T,"Hallucination sting (changeling)")
	after(T, rand(30 SECONDS, 60 SECONDS), TYPE_PROC_REF(/datum, status_set), with = list(STAT_HALLUCINATING, 400)) //No going ABOVE 400 hallucinations.
	feedback_add_details("changeling_powers","HS")
	return TRUE

/mob/proc/changeling_lsdsting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_lsdsting_stage(A.answer.value)
