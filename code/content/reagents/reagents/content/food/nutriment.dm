/* Food */

/datum/reagent/nutriment
	treatment_tags = list(TREAT_BLOOD_RESTORE = 0.25, TREAT_TISSUE_REPAIR = 0.1)
	factors = alist(STAT_BLOOD_REGEN = 0.8)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_NUTRIMENT
	id = REAGENT_ID_NUTRIMENT
	description = "All the vitamins, minerals, and carbohydrates the body needs in pure form."
	taste_mult = 4
	reagent_state = SOLID
	metabolism = REM * 4
	ingest_met = REM * 4
	var/nutriment_factor = 30 // Per unit
	var/injectable = 0
	color = "#664330"
	affects_robots = 1
	wiki_flag = WIKI_FOOD
	coolant_modifier = -1
	scannable = SCANNABLE_BENEFICIAL

	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/nutriment/mix_data(list/newdata, newamount)

	if(!islist(newdata) || !newdata.len)
		return

	//add the new taste data
	if(islist(data))
		for(var/taste in newdata)
			if(taste in data)
				data[taste] += newdata[taste]
			else
				data[taste] = newdata[taste]
	else
		initialize_data(newdata)

	//cull all tastes below 10% of total
	var/totalFlavor = 0
	for(var/taste in data)
		totalFlavor += data[taste]
	if(totalFlavor) //Let's not divide by zero for things w/o taste
		for(var/taste in data)
			if(data[taste]/totalFlavor < 0.1)
				data -= taste

/datum/reagent/nutriment/affect_blood(mob/living/carbon/M, alien, removed)
	if(!injectable && !species_in(M, REAGENT_BLOOD_FED_SPECIES) && !HAS_SYNTHETIC_BIOLOGY(M))
		M.injure(INJURY_TOXIN, 0.1 * removed, source = src)
		return
	affect_ingest(M, alien, removed) // B18: this already feeds every body; no second add
	..()

/datum/reagent/nutriment/affect_ingest(mob/living/carbon/M, alien, removed)
	switch(alien)
		if(IS_DIONA) return
		if(IS_UNATHI) removed *= 0.5
		if(IS_CHIMERA) removed *= 0.25
	if(issmall(M)) removed *= 2 // Small bodymass, more effect from lower volume.
	// s Start
	if(!HAS_SYNTHETIC_BIOLOGY(M))
		if(!(M.species.allergens & allergen_type) && !(M.species.medallergens & medallergen_type))	//assuming it doesn't cause a horrible reaction, we'll be ok!
			// Nutriment's light tissue repair is its treatment_tags profile.
			M.adjust_nutrition(((nutriment_factor + M.food_preference(allergen_type)) * removed) * M.species.organic_food_coeff) //RS edit
	else
		M.adjust_nutrition(((nutriment_factor + M.food_preference(allergen_type)) * removed) * M.species.synthetic_food_coeff) //RS edit

	// s Stop

//=========================
//Fats
//=========================
/datum/reagent/nutriment/triglyceride
	name = REAGENT_TRIGLYCERIDE
	id = REAGENT_ID_TRIGLYCERIDE
	description = "More commonly known as fat, the third macronutrient, with over double the energy content of carbs and protein"

	reagent_state = SOLID
	taste_description = "greasiness"
	taste_mult = 0.1
	nutriment_factor = 27//The caloric ratio of carb/protein/fat is 4:4:9
	color = "#CCCCCC"
	coolant_modifier = 1.5

// Aurora Cooking Port Insertion End

/datum/reagent/nutriment/glucose
	name = REAGENT_GLUCOSE
	id = REAGENT_ID_GLUCOSE
	taste_description = "sweetness"
	color = "#FFFFFF"
	cup_prefix = "sweetened"

	injectable = 1
	coolant_modifier = 1.25

/datum/reagent/nutriment/mayo
	name = REAGENT_MAYO
	id = REAGENT_ID_MAYO
	description = "A thick, bitter sauce."
	taste_description = "unmistakably mayonnaise"
	nutriment_factor = 10
	color = "#FFFFFF"
	allergen_type = ALLERGEN_EGGS	//Mayo is made from eggs
	cup_prefix = REAGENT_ID_MAYO

/datum/reagent/nutriment/yeast
	name = REAGENT_YEAST
	id = REAGENT_ID_YEAST
	description = "For making bread rise!"
	taste_description = "yeast"
	nutriment_factor = 1
	color = "#D3AF70"

/datum/reagent/nutriment/coffee
	name = REAGENT_COFFEEPOWDER
	id = REAGENT_ID_COFFEEPOWDER
	description = "A bitter powder made by grinding coffee beans."
	taste_description = "bitterness"
	taste_mult = 1.3
	nutriment_factor = 1
	color = "#482000"
	allergen_type = ALLERGEN_COFFEE | ALLERGEN_STIMULANT //Again, coffee contains coffee
	wiki_flag = WIKI_DRINK

/datum/reagent/nutriment/tea
	name = REAGENT_TEAPOWDER
	id = REAGENT_ID_TEAPOWDER
	description = "A dark, tart powder made from black tea leaves."
	taste_description = "tartness"
	taste_mult = 1.3
	nutriment_factor = 1
	color = "#101000"
	allergen_type = ALLERGEN_STIMULANT //Strong enough to contain caffeine
	wiki_flag = WIKI_DRINK

/datum/reagent/nutriment/decaf_tea
	name = REAGENT_DECAFTEAPOWDER
	id = REAGENT_ID_DECAFTEAPOWDER
	description = "A dark, tart powder made from black tea leaves, treated to remove caffeine content."
	taste_description = "tartness"
	taste_mult = 1.3
	nutriment_factor = 1
	color = "#101000"
	wiki_flag = WIKI_DRINK

/datum/reagent/nutriment/coco
	name = REAGENT_COCO
	id = REAGENT_ID_COCO
	description = "A fatty, bitter paste made from coco beans."
	taste_description = "bitterness"
	taste_mult = 1.3
	reagent_state = SOLID
	nutriment_factor = 5
	color = "#302000"
	allergen_type = ALLERGEN_CHOCOLATE
	cup_prefix = REAGENT_ID_COCO

/datum/reagent/nutriment/chocolate
	name = REAGENT_CHOCOLATE
	id = REAGENT_ID_CHOCOLATE
	description = "Great for cooking or on its own!"
	taste_description = "chocolate"
	color = "#582815"
	nutriment_factor = 5
	taste_mult = 1.3
	allergen_type = ALLERGEN_CHOCOLATE
	cup_prefix = REAGENT_ID_CHOCOLATE

/datum/reagent/nutriment/instantjuice
	name = REAGENT_INSTANTJUICE
	id = REAGENT_ID_INSTANTJUICE
	description = "Dehydrated, powdered juice of some kind."
	taste_mult = 1.3
	nutriment_factor = 1
	allergen_type = ALLERGEN_FRUIT //I suppose it's implied here that the juice is from dehydrated fruit.
	wiki_flag = WIKI_DRINK

/datum/reagent/nutriment/instantjuice/grape
	name = REAGENT_INSTANTGRAPE
	id = REAGENT_ID_INSTANTGRAPE
	description = "Dehydrated, powdered grape juice."
	taste_description = "dry grapes"
	color = "#863333"
	cup_prefix = "grape"

/datum/reagent/nutriment/instantjuice/orange
	name = REAGENT_INSTANTORANGE
	id = REAGENT_ID_INSTANTORANGE
	description = "Dehydrated, powdered orange juice."
	taste_description = "dry oranges"
	color = "#e78108"
	cup_prefix = "orange"

/datum/reagent/nutriment/instantjuice/watermelon
	name = REAGENT_INSTANTWATERMELON
	id = REAGENT_ID_INSTANTWATERMELON
	description = "Dehydrated, powdered watermelon juice."
	taste_description = "dry sweet watermelon"
	color = "#b83333"
	cup_prefix = "melon"

/datum/reagent/nutriment/instantjuice/apple
	name = REAGENT_INSTANTAPPLE
	id = REAGENT_ID_INSTANTAPPLE
	description = "Dehydrated, powdered apple juice."
	taste_description = "dry sweet apples"
	color = "#c07c40"
	cup_prefix = "apple"

/datum/reagent/nutriment/soysauce
	name = REAGENT_SOYSAUCE
	id = REAGENT_ID_SOYSAUCE
	description = "A salty sauce made from the soy plant."
	taste_description = "umami"
	taste_mult = 1.1
	reagent_state = LIQUID
	nutriment_factor = 2
	color = "#792300"
	allergen_type = ALLERGEN_BEANS | ALLERGEN_SALT //Soy (beans)
	cup_prefix = "umami"

/datum/reagent/nutriment/vinegar
	name = REAGENT_VINEGAR
	id = REAGENT_ID_VINEGAR
	description = "vinegar, great for fish and pickles."
	taste_description = "vinegar"
	reagent_state = LIQUID
	nutriment_factor = 5
	color = "#54410C"
	cup_prefix = "acidic"

/datum/reagent/nutriment/ketchup
	name = REAGENT_KETCHUP
	id = REAGENT_ID_KETCHUP
	description = "Ketchup, catsup, whatever. It's tomato paste."
	taste_description = "ketchup"
	reagent_state = LIQUID
	nutriment_factor = 5
	color = "#731008"
	allergen_type = ALLERGEN_FRUIT 	//Tomatoes are a fruit.
	cup_prefix = "tomato"

/datum/reagent/nutriment/mustard
	name = REAGENT_MUSTARD
	id = REAGENT_ID_MUSTARD
	description = "Delicious mustard. Good on Hot Dogs."
	taste_description = "mustard"
	reagent_state = LIQUID
	nutriment_factor = 5
	color = "#E3BD00"
	cup_prefix = REAGENT_ID_MUSTARD

/datum/reagent/nutriment/barbecue
	name = REAGENT_BARBECUE
	id = REAGENT_ID_BARBECUE
	description = "Barbecue sauce for barbecues and long shifts."
	taste_description = "barbeque"
	reagent_state = LIQUID
	nutriment_factor = 5
	color = "#4F330F"
	cup_prefix = REAGENT_ID_BARBECUE

/datum/reagent/nutriment/rice
	name = REAGENT_RICE
	id = REAGENT_ID_RICE
	description = "Enjoy the great taste of nothing."
	taste_description = "rice"
	taste_mult = 0.4
	reagent_state = SOLID
	nutriment_factor = 1
	color = "#FFFFFF"

/datum/reagent/nutriment/cherryjelly
	name = REAGENT_CHERRYJELLY
	id = REAGENT_ID_CHERRYJELLY
	description = "Totally the best. Only to be spread on foods with excellent lateral symmetry."
	taste_description = "cherry"
	taste_mult = 1.3
	reagent_state = LIQUID
	nutriment_factor = 1
	color = "#801E28"
	allergen_type = ALLERGEN_FRUIT //Cherries are fruits

/datum/reagent/nutriment/peanutbutter
	name = REAGENT_PEANUTBUTTER
	id = REAGENT_ID_PEANUTBUTTER
	description = "A butter derived from various types of nuts."
	taste_description = "peanuts"
	taste_mult = 0.5
	reagent_state = LIQUID
	nutriment_factor = 30
	color = "#4F3500"
	allergen_type = ALLERGEN_SEEDS //Peanuts(seeds)
	cup_prefix = "peanut butter"

/datum/reagent/nutriment/vanilla
	name = REAGENT_VANILLA
	id = REAGENT_ID_VANILLA
	description = "Vanilla extract. Tastes suspiciously like boring ice-cream."
	taste_description = "vanilla"
	taste_mult = 5
	reagent_state = LIQUID
	nutriment_factor = 2
	color = "#0F0A00"
	cup_prefix = REAGENT_ID_VANILLA

/datum/reagent/nutriment/virus_food
	name = REAGENT_VIRUSFOOD
	id = REAGENT_ID_VIRUSFOOD
	description = "A mixture of water, milk, and oxygen. Virus cells can use this mixture to reproduce."
	taste_description = "vomit"
	taste_mult = 2
	reagent_state = LIQUID
	nutriment_factor = 2
	color = "#899613"
	allergen_type = ALLERGEN_DAIRY	//incase anyone is dumb enough to drink it - it does contain milk!

/datum/reagent/nutriment/sprinkles
	name = REAGENT_SPRINKLES
	id = REAGENT_ID_SPRINKLES
	description = "Multi-colored little bits of sugar, commonly found on donuts. Loved by cops."
	taste_description = "sugar"
	nutriment_factor = 1
	color = "#FF00FF"
	cup_prefix = "sprinkled"

/datum/reagent/nutriment/mint
	name = REAGENT_MINT
	id = REAGENT_ID_MINT
	description = "Also known as Mentha."
	taste_description = "mint"
	reagent_state = LIQUID
	color = "#CF3600"
	cup_prefix = "minty"
