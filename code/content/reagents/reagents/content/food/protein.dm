/datum/reagent/nutriment/protein // Bad for Skrell!
	name = REAGENT_PROTEIN
	id = REAGENT_ID_PROTEIN
	taste_description = "some sort of meat"
	color = "#440000"
	allergen_type = ALLERGEN_MEAT //"Animal protein" implies it comes from animals, therefore meat.

/datum/reagent/nutriment/protein/affect_ingest(mob/living/carbon/M, alien, removed)
	switch(alien)
		if(IS_TESHARI)
			..(M, alien, removed*1.2) // Teshari get a bit more nutrition from meat.
		if(IS_UNATHI)
			..(M, alien, removed*2.25) //Unathi get most of their nutrition from meat.
		if(IS_CHIMERA)
			..(M, alien, removed*4) //Xenochimera are obligate carnivores.
		else
			..()

/datum/reagent/nutriment/protein/tofu
	name = REAGENT_TOFU
	id = REAGENT_ID_TOFU
	color = "#fdffa8"
	taste_description = "tofu"
	allergen_type = ALLERGEN_BEANS //Made from soy beans

/datum/reagent/nutriment/protein/fungi
	name = REAGENT_FUNGI
	id = REAGENT_ID_FUNGI
	taste_description = "some sort of mushroom"
	color = "#979797"
	allergen_type = ALLERGEN_FUNGI

/datum/reagent/nutriment/protein/seafood
	name = REAGENT_SEAFOOD
	id = REAGENT_ID_SEAFOOD
	color = "#f5f4e9"
	taste_description = "fish"
	allergen_type = ALLERGEN_FISH //I suppose the fish allergy likely refers to seafood in general.

/datum/reagent/nutriment/protein/cheese
	name = REAGENT_CHEESE
	id = REAGENT_ID_CHEESE
	color = "#EDB91F"
	taste_description = "cheese"
	allergen_type = ALLERGEN_DAIRY //Cheese is made from dairy
	cup_prefix = "cheesy"

/datum/reagent/nutriment/protein/egg
	name = REAGENT_EGG
	id = REAGENT_ID_EGG
	taste_description = "egg"
	color = "#FFFFAA"
	allergen_type = ALLERGEN_EGGS //Eggs contain egg
	cup_prefix = "eggy"

/datum/reagent/nutriment/protein/murk
	name = REAGENT_MURK_PROTEIN
	id = REAGENT_ID_MURK_PROTEIN
	taste_description = "mud"
	color = "#664330"
	allergen_type = ALLERGEN_FISH //Murkfin is fish

/datum/reagent/nutriment/protein/bean
	name = REAGENT_BEANPROTEIN
	id = REAGENT_ID_BEANPROTEIN
	taste_description = "beans"
	color = "#562e0b"
	allergen_type = ALLERGEN_BEANS //Made from soy beans
