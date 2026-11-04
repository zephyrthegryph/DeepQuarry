/*
/// Recreational and psychiatric drugs go here! Please keep them separated in the file.
/// Due to concerns and safety for our repo, illegal real-world drug names should generally be avoided.
*/

/datum/reagent/drugs
	name = REAGENT_DRUGS
	id = REAGENT_ID_DRUGS
	description = "Some generic drugs."
	taste_description = "a bad investment"
	taste_mult = 1.2 /// The overwhelming flavor of a good(?) time!
	color = "#f2f2f2"
	scannable = SCANNABLE_ADVANCED
	var/high_messages = TRUE
	var/list/high_message_list = list("You feel great! For now...", "You feel a wave of happiness!") // ALLOW(instance_list): kept: interned by contents in New() (intern_list); read-only
	var/list/sober_message_list = list("You feel like garbage...", "Your head aches.") // ALLOW(instance_list): kept: interned by contents in New() (intern_list); read-only
	var/last_message_at = 0 // when the last status message was sent (-1: the effect ended)

	var/prob_proc = FALSE /// ANY probabilities in specific drugs should check for this to be TRUE + the desired probability AND set this back to false.

	reagent_state = LIQUID
	metabolism = REM * 0.5
	ingest_met = REM * 1.5 /// Be very careful with this, ingestion is weird and will spam high/sober messages horribly!
	allergen_factor = 3 // Allergic reactions to concentrated medications should be pretty strong
	dermal_absorption = 0
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE

	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_ILLDRUG
	/// Prometheans feel drugs at ~1/6 strength (drug_strength / thresholds scale by species_mult()).
	species_strength = alist(IS_SLIME = 0.15)

// Every reagent datum in every holder carries these; share identical message tables (read-only).
/datum/reagent/drugs/New()
	high_message_list = intern_list(high_message_list)
	sober_message_list = intern_list(sober_message_list)
	return ..()

/datum/reagent/drugs/affect_blood(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return

	if(high_messages == TRUE)
		if(ELAPSED(src, last_message_at, CLOCK_WORLD) > 90 SECONDS && volume > 0.5) /// Spam prevention.
			STAMP(src, last_message_at, CLOCK_WORLD)
			var/msg = pick(high_message_list)
			to_chat(M, span_warning("[msg]"))
		else if(volume <= 0.2 && last_message_at != -1)
			last_message_at = -1
			var/msg = pick(sober_message_list)
			to_chat(M, span_warning("[msg]"))
	if(prob(5) && prob_proc == FALSE) /// Enables procs to activate, remains true until THAT PROC sets it to false again.
		prob_proc = TRUE

/*///////////////////////////////////////////////////////////////////////////
///						PSYCHIATRIC DRUGS								/////
///																		/////
/// Psychiatric drugs use similar mechanics and will go under "drugs".  /////
*////////////////////////////////////////////////////////////////////////////
/datum/reagent/drugs/methylphenidate
	name = REAGENT_METHYLPHENIDATE
	id = REAGENT_ID_METHYLPHENIDATE
	description = "Improves the ability to concentrate."
	taste_description = "mild grape" ///Referencing real life oral solutions for these meds.
	color = "#BF80BF"
	high_message_list = list("You feel focused.", "Your attention is undivided.")
	sober_message_list = list("It becomes harder to focus...", "You feel distractible.")
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	scannable = SCANNABLE_BENEFICIAL
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/drugs/qerr_quem
	name = REAGENT_QERRQUEM
	id = REAGENT_ID_QERRQUEM
	description = "A potent sedative and anti-anxiety medication, made for the Qerr-Katish."
	taste_description = "mint"
	color = "#e6efe3"
	scannable = SCANNABLE_BENEFICIAL
	high_message_list = list("You feel sluggish...", "You feel calm and collected.")
	sober_message_list = list("You feel so much more antsy...", "Your concentration wavers.")
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG
