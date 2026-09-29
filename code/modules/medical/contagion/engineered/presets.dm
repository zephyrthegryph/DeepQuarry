/datum/affliction/contagion/engineered/random
	var/randomname = TRUE
	/// Typepath of a trait every strain of this preset carries.
	var/setsymptom = null
	var/max_symptoms_override

/datum/affliction/contagion/engineered/random/minor
	max_symptoms_override = 4

/datum/affliction/contagion/engineered/random/New(max_symptoms, max_level = 6, min_level = 1, list/guaranteed_symptoms = setsymptom, atom/infected, mute = TRUE)
	if(!max_symptoms)
		max_symptoms = (2 + rand(1, (VIRUS_SYMPTOM_LIMIT - 2)))
	if(max_symptoms_override)
		max_symptoms = (max_symptoms_override - rand(0, 2))
	if(guaranteed_symptoms)
		if(islist(guaranteed_symptoms))
			max_symptoms -= length(guaranteed_symptoms)
		else
			guaranteed_symptoms = list(guaranteed_symptoms)
			max_symptoms -= 1

	var/list/datum/viral_trait/possible_symptoms = list()
	for(var/datum/viral_trait/symptom as anything in subtypesof(/datum/viral_trait))
		if(symptom in guaranteed_symptoms)
			continue
		if(initial(symptom.level) > max_level || initial(symptom.level) < min_level)
			continue
		if(initial(symptom.level) <= -1)
			continue
		possible_symptoms += symptom
	for(var/i in 1 to max_symptoms)
		var/datum/viral_trait/chosen_symptom = pick_n_take(possible_symptoms)
		if(chosen_symptom)
			own_add(src, "symptoms", new chosen_symptom)
	for(var/guaranteed_symptom in guaranteed_symptoms)
		own_add(src, "symptoms", new guaranteed_symptom)
	if(!mute)
		virus_modifiers |= IMMUTABLE
	Finalize()

	if(randomname)
		var/randname = random_disease_name(infected)
		AssignName(randname)
		name = randname

/mob/living/carbon/human/proc/give_random_dormant_disease(biohazard = 25, min_symptoms = 2, max_symptoms = 4, min_level = 4, max_level = 9, list/guaranteed_symptoms = list())
	. = FALSE
	var/sickrisk = 1

	if(has_trait(src, STRONG_IMMUNITY_TRAIT)) // Don't bother (synthetic bodies refuse organic strains by biology)
		return

	switch(get_species())
		if(SPECIES_UNATHI, SPECIES_TAJARAN) // Mice devourers
			sickrisk = 0.5
		if(SPECIES_XENOCHIMERA)
			var/datum/affliction/contagion/roanoke/dormant_roanoke = new
			dormant_roanoke.virus_modifiers |= DORMANT
			force_contagion(dormant_roanoke, TRUE)
			return TRUE
		if(SPECIES_PROMETHEAN) // Too clean
			return

	if(prob(min(100, (biohazard * sickrisk))))
		var/symptom_amt = rand(min_symptoms, max_symptoms)
		var/datum/affliction/contagion/engineered/dormant_disease = new /datum/affliction/contagion/engineered/random(symptom_amt, max_level, min_level, guaranteed_symptoms, infected = src)
		dormant_disease.virus_modifiers |= DORMANT
		dormant_disease.spread_flags = DISEASE_SPREAD_NON_CONTAGIOUS
		dormant_disease.spread_text = "None"
		dormant_disease.visibility_flags |= HIDDEN_SCANNER
		force_contagion(dormant_disease, TRUE)
		return TRUE

/datum/affliction/contagion/engineered/random/macrophage
	setsymptom = /datum/viral_trait/macrophage

/datum/affliction/contagion/engineered/random/blob
	name = "Blob Spores"
	setsymptom = /datum/viral_trait/blobspores

// Cold

/datum/affliction/contagion/engineered/cold/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Engineered Cold"
		symptoms = list(new /datum/viral_trait/sneeze)
	..(process, D, copy)


// Flu

/datum/affliction/contagion/engineered/flu/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Engineered Flu"
		symptoms = list(new /datum/viral_trait/cough)
	..(process, D, copy)

// Macrophages

/datum/affliction/contagion/engineered/macrophage/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Macrophages"
		symptoms = list(new /datum/viral_trait/macrophage)
	..(process, D, copy)

// Blob Spores

/datum/affliction/contagion/engineered/blobspores/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Blob Spores"
		symptoms = list(new /datum/viral_trait/blobspores)
	..(process, D, copy)
