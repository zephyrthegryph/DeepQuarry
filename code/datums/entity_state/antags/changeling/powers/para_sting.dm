//Updated
/datum/power/changeling/paralysis_sting
	name = "Paralysis Sting"
	desc = "We silently sting a human, paralyzing them for a short time."
	genomecost = 3
	verbpath = /mob/proc/changeling_paralysis_sting

/mob/proc/changeling_paralysis_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Paralysis sting (30)"
	set desc="Sting target"
	return changeling_paralysis_sting_stage()

/mob/proc/changeling_paralysis_sting_stage(mob/living/carbon/selected_target)

	var/mob/living/carbon/T = changeling_sting(30, PROC_REF(changeling_paralysis_sting_target_answered), selected_target)
	if(!T)
		return FALSE
	add_attack_logs(src,T,"Paralysis sting (changeling)")
	to_chat(T, span_danger("Your muscles begin to painfully tighten."))
	T.status_at_least(STAT_WEAKENED, 20)
	feedback_add_details("changeling_powers","PS")
	return TRUE

/mob/proc/changeling_paralysis_sting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_paralysis_sting_stage(A.answer.value)
