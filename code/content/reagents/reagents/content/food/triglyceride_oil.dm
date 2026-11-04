/datum/reagent/nutriment/triglyceride/oil
	//Having this base class incase we want to add more variants of oil
	name = REAGENT_OIL
	id = REAGENT_ID_OIL
	description = "Oils are liquid fats."
	reagent_state = LIQUID
	taste_description = "oil"
	color = "#c79705"
	touch_met = 1.5
	COOLDOWN_DECLARE(burn_message_cooldown)

/datum/reagent/nutriment/triglyceride/oil/touch_turf(turf/simulated/T)
	if(!istype(T))
		return

	..()

	var/hotspot = (locate_on(T, /obj/effect/hotspot))
	if(hotspot && !istype(T, /turf/space))
		var/datum/gas_mixture/lowertemp = T.remove_air(xgm_total_moles(T.return_air())) // XGM T:air:total_moles → LINDA helper
		var/lowertemp_temperature = lowertemp.return_temperature()
		heat_set(lowertemp, max(min(lowertemp_temperature-2000, lowertemp_temperature / 2), 0), HEAT_SOURCE_REACTION)
		lowertemp.react()
		T.assume_air(lowertemp)
		spent(hotspot)

	if(volume >= 3)
		T.wet_floor(2)

/datum/reagent/nutriment/triglyceride/oil/initialize_data(newdata) // Called when the reagent is created.
	..()
	if (!data)
		data = list("temperature" = T20C)

/// Oil data always requires a "temperature" key.
TYPE_TABLE(/datum/reagent/nutriment/triglyceride/oil, get_data_schema, list("temperature"))

//Handles setting the temperature when oils are mixed
/datum/reagent/nutriment/triglyceride/oil/mix_data(newdata, newamount)

	if (!data)
		data = list("temperature" = T20C)

	if(!islist(newdata) || isnull(newdata["temperature"]))
		return

	var/ouramount = volume - newamount
	if (ouramount <= 0 || !data["temperature"] || !volume)
		//If we get here, then this reagent has just been created, just copy the temperature exactly
		data["temperature"] = newdata["temperature"]

	else
		//Our temperature is set to the mean of the two mixtures, taking volume into account
		var/total = (data["temperature"] * ouramount) + (newdata["temperature"] * newamount)
		data["temperature"] = total / volume

	return ..()

//Calculates a scaling factor for scalding damage, based on the temperature of the oil and creature's heat resistance
/datum/reagent/nutriment/triglyceride/oil/proc/heatdamage(mob/living/carbon/M)
	var/threshold = 360//Human heatdamage threshold
	var/datum/species/S = M.get_species(1)
	if (S && istype(S))
		threshold = S.heat_level_1

	//If temperature is too low to burn, return a factor of 0. no damage
	if (data["temperature"] < threshold)
		return 0

	//Step = degrees above heat level 1 for 1.0 multiplier
	var/step = 60
	if (S && istype(S))
		step = (S.heat_level_2 - S.heat_level_1)*1.5

	. = data["temperature"] - threshold
	. /= step
	. = min(., 2.5)//Cap multiplier at 2.5

/datum/reagent/nutriment/triglyceride/oil/affect_touch(mob/living/carbon/M, alien, removed)
	var/dfactor = heatdamage(M)
	if (dfactor)
		M.injure(INJURY_BURN, removed * 1.5 * dfactor, source = src)
		data["temperature"] -= (6 * removed) / (1 + volume*0.1)//Cools off as it burns you
		if (COOLDOWN_FINISHED(src, burn_message_cooldown)	)
			to_chat(M, span_danger("Searing hot oil burns you, wash it off quick!"))
			COOLDOWN_START(src, burn_message_cooldown, 10 SECONDS)

/datum/reagent/nutriment/triglyceride/oil/cooking
	name = REAGENT_COOKINGOIL
	id = REAGENT_ID_COOKINGOIL
	description = "A general-purpose cooking oil."
	reagent_state = LIQUID

/datum/reagent/nutriment/triglyceride/oil/corn
	name = REAGENT_CORNOIL
	id = REAGENT_ID_CORNOIL
	description = "An oil derived from various types of corn."
	reagent_state = LIQUID
	allergen_type = ALLERGEN_VEGETABLE //Corn is a vegetable

/datum/reagent/nutriment/triglyceride/oil/peanut
	name = REAGENT_PEANUTOIL
	id = REAGENT_ID_PEANUTOIL
	description = "An oil derived from various types of nuts."
	taste_description = "nuts"
	taste_mult = 0.3
	nutriment_factor = 15
	color = "#4F3500"
	allergen_type = ALLERGEN_SEEDS //Peanut oil would come from peanuts, hence seeds.
