// Vat clone stablizer
/datum/reagent/acid/artificial_sustenance
	name = REAGENT_ASUSTENANCE
	id = REAGENT_ID_ASUSTENANCE
	description = "A drug used to stablize vat grown bodies. Often used to control the lifespan of biological experiments." // Who else remembers Cybersix?
	taste_description = "burning metal"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#31d422"
	overdose = 15
	overdose_mod = 1.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/acid/artificial_sustenance/affect_ingest(mob/living/carbon/M, alien, removed)
	// You need me...
	if(M.get_addiction_to_reagent(REAGENT_ID_ASUSTENANCE))
		return
	// Continue to acid damage, no changes on injection or splashing, as this is meant to be edible only to those pre-addicted to it! Not a snowflake acid that doesn't hurt you!
	. = ..()

/datum/reagent/acid/artificial_sustenance/handle_addiction(mob/living/carbon/M, alien)
	// A copy of the base with withdrawl, but with death, and different messages
	var/current_addiction = M.get_addiction_to_reagent(id)
	// slow degrade
	if(prob(2))
		current_addiction  -= 1
	// withdrawl mechanics
	if(prob(2))
		if(current_addiction <= 40)
			to_chat(M, span_danger("You're dying for some [name]!"))
		else if(current_addiction <= 60)
			to_chat(M, span_warning("You're really craving some [name]."))
		else if(current_addiction <= 100)
			to_chat(M, span_notice("You're feeling the need for some [name]."))
		// effects
		if(current_addiction < 60 && prob(20))
			M.emote(pick("pale","shiver","twitch"))
	// Agony and death!
	if(current_addiction <= 20)
		if(prob(12))
			M.injure(INJURY_TOXIN, rand(1,4), source = src)
			M.injure(INJURY_BLUNT, rand(1,4), source = src)
			M.AdjustLosebreath(rand(1,2)) // Withdrawal seizes the chest.
	// proc side effect
	if(current_addiction <= 30)
		if(prob(3))
			M.status_at_least(STAT_WEAKENED, 2)
			M.emote("vomit")
			M.apply_body_effect(/datum/body_effect/withdrawal_strain/severe, 3 SECONDS)
	else if(current_addiction <= 40)
		if(prob(3))
			M.emote("vomit")
			M.apply_body_effect(/datum/body_effect/withdrawal_strain/moderate, 3 SECONDS)
	else if(current_addiction <= 50)
		if(prob(2))
			M.emote("vomit")
	// Sustenance requirements cannot be escaped!
	if(current_addiction <= 0)
		current_addiction = 40
	return current_addiction
