//Updated
/datum/power/changeling/extract_dna
	name = "Extract DNA"
	desc = "We stealthily sting a target and extract the DNA from them."
	helptext = "Will give you the DNA of your target, allowing you to transform into them. Does not count towards absorb objectives."
	ability_icon_state = "ling_sting_extract"
	genomecost = 0
	allowduringlesserform = TRUE
	verbpath = /mob/proc/changeling_extract_dna_sting

/mob/proc/changeling_extract_dna_sting()
	set category = VERB_CAT_CHANGELING
	set name = "Extract DNA Sting (40)"
	set desc="Stealthily sting a target to extract their DNA."
	return changeling_extract_dna_sting_stage()

/mob/proc/changeling_extract_dna_sting_stage(mob/living/carbon/selected_target)

	var/mob/living/carbon/human/T = changeling_sting(40, PROC_REF(changeling_extract_dna_sting_target_answered), selected_target)
	if(!T)
		return

	if(!istype(T) || HAS_SYNTHETIC_BIOLOGY(T))
		to_chat(src, span_warning("\The [T] is not compatible with our biology."))
		return FALSE

	if(T.species.flags & (NO_DNA|NO_SLEEVE))
		to_chat(src, span_warning("We do not know how to parse this creature's DNA!"))
		return FALSE

	if(T.has_mutation(HUSK))
		to_chat(src, span_warning("This creature's DNA is ruined beyond useability!"))
		return FALSE

	add_attack_logs(src,T,"DNA extraction sting (changeling)")

	var/saved_dna = T.dna.Clone() /// Prevent transforming bugginess.
	var/datum/absorbed_dna/newDNA = new(T.real_name, saved_dna, T.species.name, T.languages, T.identifying_gender, T.flavor_texts, T.identity()?.genetic_effects?.Copy())
	absorbDNA(newDNA)

	feedback_add_details("changeling_powers","ED")
	return TRUE

/mob/proc/changeling_extract_dna_sting_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	changeling_extract_dna_sting_stage(A.answer.value)
