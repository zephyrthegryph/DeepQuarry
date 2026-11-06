// Juices

/datum/reagent/drink/juice/banana
	name = REAGENT_BANANA
	id = REAGENT_ID_BANANA
	description = "The raw essence of a banana."
	taste_description = "banana"
	color = "#C3AF00"

	glass_name = "banana juice"
	glass_desc = "The raw essence of a banana. HONK!"
	allergen_type = ALLERGEN_FRUIT //Bananas are fruit
	cup_prefix = REAGENT_ID_BANANA

/datum/reagent/drink/juice/berry
	name = REAGENT_BERRYJUICE
	id = REAGENT_ID_BERRYJUICE
	description = "A delicious blend of several different kinds of berries."
	taste_description = "berries"
	color = "#990066"

	glass_name = "berry juice"
	glass_desc = "Berry juice. Or maybe it's jam. Who cares?"
	allergen_type = ALLERGEN_FRUIT //Berries are fruit
	cup_prefix = "berry"

/datum/reagent/drink/juice/pineapple
	name = REAGENT_PINEAPPLEJUICE
	id = REAGENT_ID_PINEAPPLEJUICE
	description = "A sour but refreshing juice from a pineapple."
	taste_description = "pineapple"
	color = "#C3AF00"

	glass_name = "pineapple juice"
	glass_desc = "Pineapple juice. Or maybe it's spineapple. Who cares?"
	allergen_type = ALLERGEN_FRUIT //Pineapples are fruit
	cup_prefix = "pineapple"

/datum/reagent/drink/juice/lettuce
	name = REAGENT_LETTUCEJUICE
	id = REAGENT_ID_LETTUCEJUICE
	description = "It's mostly water, just a bit more lettucy."
	taste_description = "fresh greens"
	color = "#29df4b"

	glass_name = "lettuce juice"
	glass_desc = "This is just lettuce water. Fresh but boring."
	cup_prefix = "lettuce"

/datum/reagent/drink/juice
	name = REAGENT_GRAPEJUICE
	id = REAGENT_ID_GRAPEJUICE
	description = "It's grrrrrape!"
	taste_description = "grapes"
	color = "#863333"
	var/sugary = TRUE ///So non-sugary juices don't make Unathi snooze.

	glass_name = "grape juice"
	glass_desc = "It's grrrrrape!"
	allergen_type = ALLERGEN_FRUIT //Grapes are fruit
	cup_prefix = "grape"

/datum/reagent/drink/juice/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	var/effective_dose = dose/2
	if(issmall(M))
		effective_dose *= 2

	if(sugary == TRUE)
		sugar_sedation(M, effective_dose)

/datum/reagent/drink/juice/lemon
	name = REAGENT_LEMONJUICE
	id = REAGENT_ID_LEMONJUICE
	description = "This juice is VERY sour."
	taste_description = "sourness"
	taste_mult = 1.1
	color = "#AFAF00"

	glass_name = "lemon juice"
	glass_desc = "Sour..."
	allergen_type = ALLERGEN_FRUIT //Lemons are fruit
	cup_prefix = "lemon"

/datum/reagent/drink/juice/apple
	name = REAGENT_APPLEJUICE
	id = REAGENT_ID_APPLEJUICE
	description = "The most basic juice."
	taste_description = "crispness"
	taste_mult = 1.1
	color = "#E2A55F"

	glass_name = "apple juice"
	glass_desc = "An earth favorite."
	allergen_type = ALLERGEN_FRUIT //Apples are fruit
	cup_prefix = "apple"

/datum/reagent/drink/juice/lime
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)
	name = REAGENT_LIMEJUICE
	id = REAGENT_ID_LIMEJUICE
	description = "The sweet-sour juice of limes."
	taste_description = "sourness"
	taste_mult = 1.8
	color = "#365E30"

	glass_name = "lime juice"
	glass_desc = "A glass of sweet-sour lime juice"
	allergen_type = ALLERGEN_FRUIT //Limes are fruit
	cup_prefix = "lime"

// Lime juice's mild antitoxin action is its treatment_tags profile.

/datum/reagent/drink/juice/orange
	treatment_tags = list(TREAT_OXYGENATION = 0.1)
	name = REAGENT_ORANGEJUICE
	id = REAGENT_ID_ORANGEJUICE
	description = "Both delicious AND rich in Vitamin C, what more do you need?"
	taste_description = "oranges"
	color = "#E78108"

	glass_name = "orange juice"
	glass_desc = "Vitamins! Yay!"
	allergen_type = ALLERGEN_FRUIT //Oranges are fruit
	cup_prefix = "orange"

/datum/reagent/drink/juice/potato
	name = REAGENT_POTATOJUICE
	id = REAGENT_ID_POTATOJUICE
	description = "Juice of the potato. Bleh."
	taste_description = "potatoes"
	nutrition = 2
	color = "#302000"
	sugary = FALSE

	glass_name = "potato juice"
	glass_desc = "Juice from a potato. Bleh."
	allergen_type = ALLERGEN_VEGETABLE //Potatoes are vegetables
	cup_prefix = "potato"

/datum/reagent/drink/juice/turnip
	name = REAGENT_TURNIPJUICE
	id = REAGENT_ID_TURNIPJUICE
	description = "Juice of the turnip. A step below the potato."
	taste_description = "turnips"
	nutrition = 2
	color = "#251e2e"
	sugary = FALSE

	glass_name = "turnip juice"
	glass_desc = "Juice of the turnip. A step below the potato."
	allergen_type = ALLERGEN_VEGETABLE //Turnips are vegetables
	cup_prefix = "turnip"

/datum/reagent/drink/juice/tomato
	treatment_tags = list(TREAT_BURN_CARE = 0.1)
	name = REAGENT_TOMATOJUICE
	id = REAGENT_ID_TOMATOJUICE
	description = "Tomatoes made into juice. What a waste of big, juicy tomatoes, huh?"
	taste_description = "tomatoes"
	color = "#731008"
	sugary = FALSE
	cup_prefix = "tomato"

	glass_name = "tomato juice"
	glass_desc = "Are you sure this is tomato juice?"
	allergen_type = ALLERGEN_FRUIT //Yes tomatoes are a fruit

// Tomato juice's mild burn care is its treatment_tags profile.

/datum/reagent/drink/juice/watermelon
	name = REAGENT_WATERMELONJUICE
	id = REAGENT_ID_WATERMELONJUICE
	description = "Delicious juice made from watermelon."
	taste_description = "sweet watermelon"
	color = "#B83333"
	cup_prefix = "melon"

	glass_name = "watermelon juice"
	glass_desc = "Delicious juice made from watermelon."
	allergen_type = ALLERGEN_FRUIT //Watermelon is a fruit
