/datum/reagent/sugar
	name = REAGENT_SUGAR
	id = REAGENT_ID_SUGAR
	description = "The organic compound commonly known as table sugar and sometimes called saccharose. This white, odorless, crystalline powder has a pleasing, sweet taste."
	taste_description = "sugar"
	taste_mult = 1.8
	reagent_state = SOLID
	scannable = SCANNABLE_BENEFICIAL
	color = "#FFFFFF"

	glass_name = REAGENT_ID_SUGAR
	glass_desc = "The organic compound commonly known as table sugar and sometimes called saccharose. This white, odorless, crystalline powder has a pleasing, sweet taste."
	glass_icon = DRINK_ICON_NOISY

	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_FOOD
	coolant_modifier = -0.25

/datum/reagent/sugar/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjust_nutrition(removed * 3)

	var/effective_dose = dose
	if(issmall(M))
		effective_dose *= 2

	sugar_sedation(M, effective_dose, deep_sleep = TRUE)
