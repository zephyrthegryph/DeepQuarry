/datum/reagent/ethanol
	name = REAGENT_ETHANOL //Parent class for all alcoholic reagents.
	id = REAGENT_ID_ETHANOL
	description = "A well-known alcohol with a variety of applications."
	taste_description = "pure alcohol"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#404030"
	cup_prefix = "alcoholic"

	ingest_met = REM * 2

	var/nutriment_factor = 0
	var/strength = 10 // This is, essentially, units between stages - the lower, the stronger. Less fine tuning, more clarity.
	var/toxicity = 1

	var/druggy = 0
	var/adj_temp = 0
	var/targ_temp = BODYTEMP_NORMAL
	var/halluci = 0

	glass_name = REAGENT_ID_ETHANOL
	glass_desc = "A well-known alcohol with a variety of applications."
	allergen_factor = 1	//simulates mixed drinks containing less of the allergen, as they have only a single actual reagent unlike food

	affects_robots = 1 //kiss my shiny metal ass
	wiki_flag = WIKI_DRINK
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
	coolant_modifier = 1.15

/// Intoxication, and liver toxicity past the toxic threshold: both depend
/// on the drinker (synthetics, alcohol tolerance), so they are computed per
/// patient at each factor recompute from the volume in their system.
/datum/reagent/ethanol/contributes_factors(mob/living/L)
	return ishuman(L) || ..()

/datum/reagent/ethanol/special_table(part, mob/living/L, volume)
	if(part != REAGENT_PART_INTOXICATION && part != REAGENT_PART_HEPATOTOXICITY)
		return ..()
	if(!ishuman(L) || volume <= 0)
		return null
	var/mob/living/carbon/human/H = L
	if(HAS_SYNTHETIC_BIOLOGY(H) && !H.species.robo_ethanol_drunk)
		return null
	var/static/alist/intoxication = alist(STAT_INTOXICATION = 1)
	var/static/alist/hepatotoxicity = alist(STAT_HEPATOTOXICITY = 1)
	if(part == REAGENT_PART_INTOXICATION)
		return intoxication
	if(strength && volume >= strength * H.species.chem_strength_alcohol * 6)
		return hepatotoxicity
	return null

/datum/reagent/ethanol/special_scale(part, volume)
	if(part == REAGENT_PART_HEPATOTOXICITY)
		return toxicity
	return ..()

/datum/reagent/ethanol/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		L.adjust_fire_stacks(amount / 15)

/datum/reagent/ethanol/affect_blood(mob/living/carbon/M, alien, removed) //This used to do just toxin. That's boring. Let's make this FUN.
	if(issmall(M))
		removed *= 2

	var/strength_mod = 3 //Alcohol is 3x stronger when injected into the veins.
	if(!strength_mod)
		return

	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		var/effective_dose = dose * strength_mod * (1 + volume/60) //drinking a LOT will make you go down faster

		if(effective_dose >= (strength * M.species.chem_strength_alcohol)) // Early warning
			M.status_adjust(STAT_DIZZY, 18) // It is decreased at the speed of 3 per tick
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 2) // Slurring
			M.status_at_least(STAT_SLURRING, 90)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 3) // Confusion - walking in random directions
			M.status_at_least(STAT_CONFUSED, 60)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 4) // Blurry vision
			M.status_at_least(STAT_BLURRY, 30)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 5) // Drowsyness - periodically falling asleep
			M.status_at_least(STAT_DROWSY, 60)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 7) // Pass out
			M.status_at_least(STAT_PARALYZED, 60)
			M.status_at_least(STAT_SLEEPING, 90)

		if(druggy != 0)
			M.status_at_least(STAT_DRUGGED, druggy*3)

		M.adjust_bodytemperature(drink_temperature_step(M.body_temperature(), targ_temp, adj_temp) - M.body_temperature()) // B12

		if(halluci)
			M.status_at_least(STAT_HALLUCINATING, halluci*3)

/datum/reagent/ethanol/affect_ingest(mob/living/carbon/M, alien, removed)
	var/ep_base_power = 60	//base nutrition gain for ethanol-processing synthetics, reduced by alcohol strength
	var/ep_final_mod = 30	//final divisor on nutrition gain
	if(issmall(M))
		removed *= 2

	if(!(M.species.allergens & allergen_type) && !(M.species.medallergens & medallergen_type) && !(HAS_SYNTHETIC_BIOLOGY(M))) // assuming it doesn't cause a horrible reaction, we get the nutrition effects - (added synth check)
		M.adjust_nutrition(nutriment_factor * removed)

	if(HAS_SYNTHETIC_BIOLOGY(M) && nutrition_of(M) < 500 && M.species.robo_ethanol_proc)
		M.adjust_nutrition(round(max(0,ep_base_power - strength) * removed)/ep_final_mod)	//the stronger it is, the more juice you gain

	var/effective_dose = dose
	if(!effective_dose)
		return

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))

		if(effective_dose >= (strength * M.species.chem_strength_alcohol)) // Early warning
			M.status_adjust(STAT_DIZZY, 6) // It is decreased at the speed of 3 per tick
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 2) // Slurring
			M.status_at_least(STAT_SLURRING, 30)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 3) // Confusion - walking in random directions
			M.status_at_least(STAT_CONFUSED, 20)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 4) // Blurry vision
			M.status_at_least(STAT_BLURRY, 10)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 5) // Drowsyness - periodically falling asleep
			M.status_at_least(STAT_DROWSY, 20)
		if(effective_dose >= (strength * M.species.chem_strength_alcohol) * 7) // Pass out
			M.status_at_least(STAT_PARALYZED, 20)
			M.status_at_least(STAT_SLEEPING, 30)

		if(druggy != 0)
			M.status_at_least(STAT_DRUGGED, druggy)

		if(halluci)
			M.status_at_least(STAT_HALLUCINATING, halluci)

		M.adjust_bodytemperature(drink_temperature_step(M.body_temperature(), targ_temp, adj_temp) - M.body_temperature()) // B12

/datum/reagent/ethanol/touch_obj(obj/O, amount, mob/user = null)
	..()
	if(istype(O, /obj/item/paper))
		var/obj/item/paper/paperaffected = O
		paperaffected.clearpaper()
		to_chat(user, "The solution dissolves the ink on the paper.")
		return
	if(istype(O, /obj/item/book))
		if(volume < 5)
			return
		if(istype(O, /obj/item/book/tome))
			to_chat(user, span_notice("The solution does nothing. Whatever this is, it isn't normal ink."))
			return
		var/obj/item/book/affectedbook = O
		affectedbook.set_dat(null)
		to_chat(user, span_notice("The solution dissolves the ink on the book."))
	return

/datum/reagent/ethanol/handle_addiction(mob/living/carbon/M, alien)
	// A copy of the base with withdrawl, but with much less effects, such as vomiting.
	var/current_addiction = M.get_addiction_to_reagent(id)
	var/realistic_addiction = FALSE //DEFAULT set to FALSE. Toggle to TRUE for a more realistic addiction with potentially fatal side effects.
	// slow degrade
	if(prob(8))
		current_addiction  -= 1
	// withdrawl mechanics
	if(!M.stabilization) //Without stabilization effects
		if(current_addiction <= 60)
			M.apply_body_effect(/datum/body_effect/withdrawal_tachycardia, 3 SECONDS)
		if(prob(2))
			if(current_addiction < 90 && prob(10))
				to_chat(M, span_warning("[pick("You feel miserable.","You feel nauseous.","You get a raging headache.")]"))
				M.injure(INJURY_PAIN, 7, source = src)
				M.status_adjust(STAT_JITTERY, 25) //Restlessness.
			else if(current_addiction <= 20)
				to_chat(M, span_danger("You feel absolutely awful. You need some some liquor. Now."))
				if(realistic_addiction && prob(20)) //1 in 5 on a 1 in 50, so 1 in 250 chance. DTs
					to_chat(M, span_red("You have a seizure!"))
					for(var/mob/O in viewers(M, null))
						if(O == M)
							continue
						O.show_message(span_danger("[M] starts having a seizure!"), 1)
					M.status_at_least(STAT_PARALYZED, 10)
					M.status_at_least(STAT_SLEEPING, 10)
					M.status_adjust(STAT_JITTERY, 1000)
			else if(current_addiction <= 50)
				to_chat(M, span_warning("You're really craving some alcohol. You feel nauseated."))
				if(realistic_addiction)
					M.emote("vomit")
					M.status_adjust(STAT_CONFUSED, 10) // Disorientation.
			else if(current_addiction <= 100)
				to_chat(M, span_notice("You're feeling the need for some booze."))
			// effects
			if(current_addiction < 60 && prob(20)) // 1 in 50 x 1 in 5 = 1 in 250
				M.emote(pick("pale","shiver","twitch"))
				M.drop_item() //Hand tremors
				if(realistic_addiction)
					M.apply_body_effect(/datum/body_effect/withdrawal_strain/moderate, 3 SECONDS)
	else //Stabilization effects
		if(current_addiction <= 60)
			M.apply_body_effect(/datum/body_effect/withdrawal_tachycardia/mild, 3 SECONDS)
		if(prob(2))
			if(current_addiction < 90 && prob(10))
				to_chat(M, span_warning("[pick("You feel a light throbbing in your head.","Your stomach feels upset.","Your .")]"))
				M.injure(INJURY_PAIN, 3, source = src)
				M.status_adjust(STAT_JITTERY, 10) //Restlessness.
			else if(current_addiction <= 20)
				to_chat(M, span_warning("You feel nauseated."))
				if(realistic_addiction)
					M.emote("vomit")
					M.status_adjust(STAT_CONFUSED, 10) // Disorientation.
			else if(current_addiction <= 50)
				to_chat(M, span_warning("Your head throbs and the room spins."))
				if(realistic_addiction)
					M.status_adjust(STAT_CONFUSED, 3) // Disorientation.
			else if(current_addiction <= 100)
				to_chat(M, span_notice("A drink would be nice."))
			// effects
			if(current_addiction < 60 && prob(5)) // 1 in 50 x 1 in 20 = 1 in 1000
				M.emote(pick("pale","shiver","twitch"))
				M.drop_item() //Hand tremors
	if(current_addiction <= 0) //safety
		current_addiction = 0
	return current_addiction

/datum/reagent/ethanol/addiction_cure_message()
	return span_notice("You feel your symptoms end, you no longer feel the craving for alcohol.")
