//Suggested to leave unchecked because this is why we can't have nice things.
/datum/power/changeling/transformation_sting
	name = "Transformation Sting"
	desc = "We silently sting a human, injecting a retrovirus that forces them to transform into another."
	helptext = "Does not provide a warning to others. The victim will transform much like a changeling would."
	ability_icon_state = "ling_sting_transform"
	genomecost = 3
	verbpath = /mob/proc/changeling_transformation_sting

/mob/proc/changeling_transformation_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Transformation sting (40)"
	set desc="Sting target"

	var/datum/changeling/changeling = changeling_power(40, 1, 100, CONSCIOUS)
	if(!changeling)
		return FALSE

	var/list/names = list()
	for(var/datum/absorbed_dna/DNA in changeling.absorbed_dna)
		names += "[DNA.name]"
	if(!LAZYLEN(names))
		to_chat(src, "We have no DNA to select from!)")
		return FALSE
	var/S
	if(LAZYLEN(names) > 1)
		var/_answer_a1 = rerun_ask(src, "a1", PROC_REF(changeling_transformation_sting), args, /datum/om/prompt/choice, message = "Select the target DNA:", title = "Target DNA", choices = names)
		if(isnull(_answer_a1))
			return
		S = _answer_a1
	else
		S = names[1]

	var/datum/absorbed_dna/chosen_dna = changeling.GetDNA(S)
	if(!chosen_dna)
		return

	var/mob/living/carbon/T = changeling_sting(40,/mob/proc/changeling_transformation_sting)
	if(!T)
		return FALSE
	if((T.has_mutation(HUSK)) || (!ishuman(T) && !issmall(T)))
		to_chat(src, span_warning("Our sting appears ineffective against its DNA."))
		return FALSE
	add_attack_logs(src,T,"Transformation sting (changeling)")
	act_message(T, null, others = span_warning("%U% transforms!"))
	own_set(T, "dna", chosen_dna.dna.Clone())
	T.real_name = chosen_dna.dna.real_name
	T.UpdateAppearance()
	domutcheck(T, null)
	feedback_add_details("changeling_powers","TS")
	return TRUE
