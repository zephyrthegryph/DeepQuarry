//Base type for alchoholic drinks containing coffee
/datum/reagent/ethanol/coffee
	name = REAGENT_DEVELOPER_WARNING
	id = REAGENT_ID_DEVELOPER_WARNING
	overdose = REAGENTS_OVERDOSE *1.5
	allergen_type = ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Contains coffee or is made from coffee

/datum/reagent/ethanol/coffee/affect_ingest(mob/living/carbon/M, alien, removed)
	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		if(inert_for(M))
			return
		..()
		M.status_adjust(STAT_DIZZY, -5)
		M.status_adjust(STAT_DROWSY, -3)
		M.status_adjust(STAT_SLEEPING, -2)
		if(M.body_temperature() > BODYTEMP_NORMAL)
			drive_body_temperature(M, BODYTEMP_NORMAL, 5 * TEMPERATURE_DAMAGE_COEFFICIENT, removed)

/datum/reagent/ethanol/coffee/affect_blood(mob/living/carbon/M, alien, removed)
	return // Coffee liqueur has no blood effect of its own.

/datum/reagent/ethanol/coffee/overdose(mob/living/carbon/M, alien)
	if(inert_for(M))
		return
	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		M.status_adjust(STAT_JITTERY, 5)

/datum/reagent/ethanol/coffee/kahlua
	name = REAGENT_KAHLUA
	id = REAGENT_ID_KAHLUA
	description = "A widely known, Mexican coffee-flavored liqueur. In production since 1936!"
	taste_description = "spiked latte"
	taste_mult = 1.1
	color = "#4C3100"
	strength = 15

	glass_name = "RR coffee liquor"
	glass_desc = "A widely known, Mexican coffee-flavored liqueur. In production since 1936!"

/datum/reagent/ethanol/coffee/b52
	name = REAGENT_B52
	id = REAGENT_ID_B52
	description = "Kahlua, Irish cream, and cognac. You will get bombed."
	taste_description = "coffee, almonds, and whiskey"
	taste_mult = 1.3
	color = "#997650"
	strength = 12

	glass_name = REAGENT_B52
	glass_desc = "Kahlua, Irish cream, and cognac. You will get bombed."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_DAIRY|ALLERGEN_FRUIT|ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from kahlua(coffee/caffeine), cognac(fruit), and irish cream(Whiskey(grains),cream(dairy))

/datum/reagent/ethanol/coffee/brave_bull //Since it's under the /coffee subtype, it already has coffee and caffeine allergens.
	name = REAGENT_BRAVEBULL
	id = REAGENT_ID_BRAVEBULL
	description = "It's just as effective as Dutch-Courage!"
	taste_description = "coffee and paint thinner"
	taste_mult = 1.1
	color = "#4C3100"
	strength = 15

	glass_name = REAGENT_BRAVEBULL
	glass_desc = "Tequilla and coffee liquor, brought together in a mouthwatering mixture. Drink up."

/datum/reagent/ethanol/coffee/irishcoffee
	name = REAGENT_IRISHCOFFEE
	id = REAGENT_ID_IRISHCOFFEE
	description = "Coffee, and alcohol. More fun than a Mimosa to drink in the morning."
	taste_description = "giving up on the day"
	color = "#4C3100"
	strength = 15

	glass_name = "Irish coffee"
	glass_desc = "Coffee and alcohol. More fun than a Mimosa to drink in the morning."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_DAIRY|ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from Coffee(coffee/caffeine) and irish cream(whiskey(grains), cream(dairy))

/datum/reagent/ethanol/coffee/elysiumfacepunch
	name = REAGENT_ELYSIUMFACEPUNCH
	id = REAGENT_ID_ELYSIUMFACEPUNCH
	description = "A loathesome cocktail favored by Heaven's skeleton shift workers."
	taste_description = "sour coffee"
	color = "#8f7729"
	strength = 20

	glass_name = REAGENT_ELYSIUMFACEPUNCH
	glass_desc = "A loathesome cocktail favored by Heaven's skeleton shift workers."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Made from kahlua(Coffee/caffeine) and lemonjuice(fruit)
