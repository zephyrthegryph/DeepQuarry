// The drug profile: the data a drug declares about its drawbacks, read by the metabolism, the scanners and the medical book.
//
//   strains = alist(O_LIVER = DRUG_STRAIN_MODERATE)  slow organ damage per unit metabolised (a toxic lesion on the organ). Natural regeneration
//                                                    outpaces it while the organ is healthy; it accumulates when the organ is already damaged,
//                                                    doses repeat, or two drugs strain the same organ (the lesions simply add).
//   hides   = list(HIDE_FEVER)                       readings this drug masks on instruments while it is in the blood (diagnose() applies them).
//   adds    = a /datum/affliction/chem_side_effect (or /datum/affliction/nausea, /seizure) with caused_by_chems: the pharmacology files.
//
// Both tables are constant per type (shared like treatment_tags, /datum/reagent/New()).

/datum/reagent
	/// O_* organ tag -> toxic-lesion damage per unit metabolised in the blood.
	var/alist/strains
	/// HIDE_* readings masked on instruments while at least DRUG_HIDE_MIN_VOLUME is in the blood.
	var/list/hides

/// Every unit this reagent metabolises in the blood strains each organ in `strains`: a toxic lesion on it, through the injury pipeline.
/datum/reagent/proc/apply_strains(mob/living/carbon/M, removed)
	if(!strains || removed <= 0 || inert_for(M))
		return
	for(var/organ_tag in strains)
		var/obj/item/organ/O = M.organ_in(organ_tag)
		if(!O)
			continue
		var/amount = strains[organ_tag] * removed * species_mult(M)
		if(amount <= 0)
			continue
		M.injure(INJURY_BLUNT, amount, O, src, affliction = /datum/affliction/lesion/toxic_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		if(GLOB.chem_trace)
			log_world("CHEM: [id] strains [organ_tag] of [M] by [amount] (removed [removed])")

/// Is a reading (HIDE_*) masked on this mob's instruments by a drug in its blood?
/mob/living/proc/reading_hidden(key)
	return FALSE

/mob/living/carbon/reading_hidden(key)
	for(var/datum/reagent/R as anything in bloodstr?.reagent_list)
		if(R.hides && (key in R.hides) && R.volume >= DRUG_HIDE_MIN_VOLUME)
			return TRUE
	return FALSE

/// Every reading hidden at once (the diagnosis asks once per scan), as a list of HIDE_* keys; null when nothing is masked.
/mob/living/proc/hidden_readings()
	return null

/mob/living/carbon/hidden_readings()
	var/list/out
	for(var/datum/reagent/R as anything in bloodstr?.reagent_list)
		if(!R.hides || R.volume < DRUG_HIDE_MIN_VOLUME)
			continue
		for(var/key in R.hides)
			LAZYOR(out, key)
	return out

/// TRUE: every strain and mask a drug applies is written to the world log (an admin or a test sets it to follow a drug that behaves strangely).
GLOBAL_VAR_INIT(chem_trace, FALSE)
