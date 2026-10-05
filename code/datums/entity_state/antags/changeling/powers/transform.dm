/datum/power/changeling/transform
	name = "Transform"
	desc = "We take on the appearance and voice of one we have absorbed."
	ability_icon_state = "ling_transform"
	genomecost = 0
	verbpath = /mob/proc/changeling_transform

//Change our DNA to that of somebody we've absorbed.
/mob/proc/changeling_transform()
	set category = VERB_CAT_CHANGELING
	set name = "Transform (5)"

	return changeling_transform_review()

/mob/proc/changeling_transform_review(answered = FALSE, reply)
	var/datum/changeling/changeling = changeling_power(5,1,0)
	if(!changeling)
		return

	if(!isturf(loc))
		to_chat(src, span_warning("Transforming here would be a bad idea."))
		return 0

	var/list/names = list()
	for(var/datum/absorbed_dna/DNA in changeling.absorbed_dna)
		names += "[DNA.name]"

	if(!answered)
		open_request(src, /datum/prompt/choice, PROC_REF(changeling_transform_answered), answerer = src, title = "Target DNA", question = "Select the target DNA:", choices = names, timeout = 0)
		return
	var/S = reply
	if(isnull(S))
		return
	if(!S)
		return

	var/datum/absorbed_dna/chosen_dna = changeling.GetDNA(S)
	if(!chosen_dna)
		return

	changeling.chem_charges -= 5
	act_message(src, null, others = span_warning("%U% transforms!"))
	changeling.geneticdamage = 5

	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		var/newSpecies = chosen_dna.speciesName
		H.set_species(newSpecies)

	rel_set(src, nameof(dna), chosen_dna.dna.Clone())
	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		H.identifying_gender = chosen_dna.identifying_gender
		H.flavor_texts = chosen_dna.flavour_texts ? chosen_dna.flavour_texts.Copy() : null
	real_name = chosen_dna.name
	UpdateAppearance()
	domutcheck(src, null)
	UpdateAppearance()
	changeling_update_languages(changeling.absorbed_languages)
	if(chosen_dna.genMods)
		// Take on the persistent traits (genetic body effects) of the chosen DNA.
		var/mob/living/self = src
		for(var/effect_type in self.body_effects().Copy())
			if(body_effect_def(effect_type).genetic)
				self.remove_body_effect(effect_type, TRUE)
		for(var/effect_type in chosen_dna.genMods)
			self.apply_body_effect(effect_type)
	regenerate_icons()
	if(isliving(src)) //Prevents organ rejection. Less intensive than adding a changeling check to blood_incompatible.
		var/mob/living/owner = src
		for(var/obj/item/organ/O in owner.organs) //I guess you can also consider this a changeling test if you take out their organ and implant it into someone else and it doesn't reject.
			O.can_reject = FALSE
		for(var/obj/item/organ/O in owner.internal_organ_list())
			O.can_reject = FALSE

	feedback_add_details("changeling_powers","TR")
	return TRUE

/// Replay the current changeling state and choices after an accepted native answer.
/mob/proc/changeling_transform_answered(datum/act/request/context)
	if(!context.answer)
		return
	changeling_transform_review(TRUE, context.answer.value)
	if(!QDELETED(src))
		SStgui.update_uis(src)
