/datum/reagent/toxin/cyanide //Fast and Lethal //Fast and lethal my ASS. This shit takes 20 seconds to deal 15 toxins. Eating crayons kills you faster.
	name = REAGENT_CYANIDE
	id = REAGENT_ID_CYANIDE
	description = "A highly toxic chemical. Prevents cellular respiration, causing moderate amounts of toxins from cell death, the inability to breathe, and eventual loss of consciousness."
	taste_description = "almond"
	dermal_absorption = 0 //Splash someone and insta-KO them? No. Make zombie/lich powder for that.
	taste_mult = 0.6
	reagent_state = LIQUID
	color = "#CF3600"
	strength = 15
	poison_affliction = /datum/affliction/poisoning/cyanide
	metabolism = REM * 0.5
	// Blocks cellular respiration: the blood arrives saturated and the tissues
	// can't use it (normal SpO2, climbing oxygen debt).
	factors = alist(STAT_TISSUE_UPTAKE = 0.1)
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/cyanide/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(dose > 5) //Puts you to sleep if its in your system for too long. This is equivalent to 100 seconds (50 ticks).
		M.status_at_least(STAT_SLEEPING, 1)
