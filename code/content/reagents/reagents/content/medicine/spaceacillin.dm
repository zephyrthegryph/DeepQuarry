/datum/reagent/spaceacillin
	treatment_tags = list(TREAT_ANTIMICROBIAL = 0.5)
	factors = alist(STAT_ANTIMICROBIAL = ANTIBIO_NORM)
	name = REAGENT_SPACEACILLIN
	id = REAGENT_ID_SPACEACILLIN
	description = "A mild all-purpose antibiotic for common infections. Low potency and slow to metabolise: it works gently over a long time, and is not enough for sepsis."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C1C1C1"
	metabolism = REM * 0.25
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	var/last_message_at = 0 // when the last status message was sent (-1: the effect ended)
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_SPACACIL

/datum/reagent/spaceacillin/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(alien == IS_SLIME)
		if(volume <= 0.1 && last_message_at != -1)
			last_message_at = -1
			to_chat(M, span_notice("You regain focus..."))
		else
			var/delay = (5 MINUTES)
			if(ELAPSED(src, last_message_at, CLOCK_WORLD) > delay)
				STAMP(src, last_message_at, CLOCK_WORLD)
				to_chat(M, span_warning("Your senses feel unfocused, and divided."))

/datum/reagent/spaceacillin/affect_touch(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.8) // Not 100% as effective as injections, though still useful.
