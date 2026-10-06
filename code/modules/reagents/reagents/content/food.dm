/* Food */

/datum/reagent/nutriment
	treatment_tags = list(TREAT_BLOOD_RESTORE = 0.25, TREAT_TISSUE_REPAIR = 0.1)
	factors = alist(BF_BLOOD_REGEN = 0.8)
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

// Aurora Cooking Port Insertion Begin

/*
	Coatings are used in cooking. Dipping food items in a reagent container with a coating in it
	allows it to be covered in that, which will add a masked overlay to the sprite.
	Coatings have both a raw and a cooked image. Raw coating is generally unhealthy
	Generally coatings are intended for deep frying foods
*/
/datum/reagent/nutriment/coating
	name = REAGENT_COATING
	id = REAGENT_ID_COATING
	nutriment_factor = 6 //Less dense than the food itself, but coatings still add extra calories
	var/messaged = 0
	var/icon_raw
	var/icon_cooked
	var/coated_adj = "coated"
	var/cooked_name = "coating"

/datum/reagent/nutriment/coating/affect_ingest(mob/living/carbon/M, alien, removed)

	//We'll assume that the batter isnt going to be regurgitated and eaten by someone else. Only show this once
	if(data["cooked"] != 1)
		if (!messaged)
			to_chat(M, span_warning("Ugh, this raw [name] tastes disgusting."))
			nutriment_factor *= 0.5
			messaged = 1

		//Raw coatings will sometimes cause vomiting. 75% chance of this happening.
		if(prob(75))
			M.vomit()
	..()

/datum/reagent/nutriment/coating/initialize_data(newdata) // Called when the reagent is created.
	..()
	if (!data)
		data = list()
	else
		if (isnull(data["cooked"]))
			data["cooked"] = 0
		return
	data["cooked"] = 0
	if (holder && holder.my_atom && istype(holder.my_atom,/obj/item/reagent_containers/food/snacks))
		data["cooked"] = 1
		name = cooked_name

		//Batter which is part of objects at compiletime spawns in a cooked state

/// Coating data always requires a "cooked" key.
TYPE_TABLE(/datum/reagent/nutriment/coating, get_data_schema, list("cooked"))

//Handles setting the temperature when oils are mixed
/datum/reagent/nutriment/coating/mix_data(newdata, newamount)
	if (!data)
		data = list()
	if(!newdata || isnull(newdata["cooked"]))
		return

	data["cooked"] = newdata["cooked"]

/datum/reagent/nutriment/coating/batter
	name = REAGENT_BATTER
	cooked_name = REAGENT_ID_BATTER
	id = REAGENT_ID_BATTER
	color = "#f5f4e9"
	reagent_state = LIQUID
	icon_raw = "batter_raw"
	icon_cooked = "batter_cooked"
	coated_adj = "battered"
	allergen_type = ALLERGEN_GRAINS | ALLERGEN_EGGS //Made with flour(grain), and eggs(eggs)

/datum/reagent/nutriment/coating/beerbatter
	factors = alist(BF_INTOXICATION = 0.02) //Very slightly alcoholic
	name = REAGENT_BEERBATTER
	cooked_name = "beer batter"
	id = REAGENT_ID_BEERBATTER
	color = "#f5f4e9"
	reagent_state = LIQUID
	icon_raw = "batter_raw"
	icon_cooked = "batter_cooked"
	coated_adj = "beer-battered"
	allergen_type = ALLERGEN_GRAINS | ALLERGEN_EGGS //Made with flour(grain), eggs(eggs), and beer(grain)

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

// Aurora Cooking Port Insertion End

/datum/reagent/nutriment/glucose
	name = REAGENT_GLUCOSE
	id = REAGENT_ID_GLUCOSE
	taste_description = "sweetness"
	color = "#FFFFFF"
	cup_prefix = "sweetened"

	injectable = 1
	coolant_modifier = 1.25

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

/datum/reagent/nutriment/honey
	name = REAGENT_HONEY
	id = REAGENT_ID_HONEY
	description = "A golden yellow syrup, loaded with sugary sweetness."
	taste_description = "sweetness"
	nutriment_factor = 10
	color = "#FFFF00"
	cup_prefix = REAGENT_ID_HONEY

/datum/reagent/nutriment/honey/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	var/effective_dose = dose
	if(issmall(M))
		effective_dose *= 2

	sugar_sedation(M, effective_dose)

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

/datum/reagent/nutriment/flour
	name = REAGENT_FLOUR
	id = REAGENT_ID_FLOUR
	description = "This is what you rub all over yourself to pretend to be a ghost."
	taste_description = "chalky wheat"
	reagent_state = SOLID
	nutriment_factor = 1
	color = "#FFFFFF"
	allergen_type = ALLERGEN_GRAINS //Flour is made from grain

/datum/reagent/nutriment/flour/touch_turf(turf/simulated/T)
	..()
	if(!istype(T, /turf/space))
		new /obj/effect/decal/cleanable/flour(T)

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

/datum/reagent/nutriment/durian
	name = REAGENT_DURIANPASTE
	id = REAGENT_ID_DURIANPASTE
	description = "A strangely sweet and savory paste."
	taste_description = "sweet and savory"
	color = "#757631"

	glass_name = "durian paste"
	glass_desc = "Durian paste. It smells horrific."

/datum/reagent/nutriment/durian/touch_mob(mob/M, amount)
	..()
	if(iscarbon(M) && !HAS_SYNTHETIC_BIOLOGY(M))
		var/message = pick("Oh god, it smells disgusting here.", "What is that stench?", "That's an awful odor.")
		to_chat(M, span_alien("[message]"))
		if(prob(CLAMP(amount, 5, 90)))
			var/mob/living/L = M
			L.vomit()
	return ..()

/datum/reagent/nutriment/durian/touch_turf(turf/T, amount)
	..()
	if(istype(T))
		var/obj/effect/decal/cleanable/chemcoating/C = new /obj/effect/decal/cleanable/chemcoating(T)
		C.reagents.add_reagent(id, amount)
	return ..()

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

/datum/reagent/lipozine // The anti-nutriment.
	name = REAGENT_LIPOZINE
	id = REAGENT_ID_LIPOZINE
	description = "A chemical compound that causes a powerful fat-burning reaction."
	taste_description = "mothballs"
	reagent_state = LIQUID
	color = "#BBEDA4"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DIET

/* Non-food stuff like condiments */

/datum/reagent/sodiumchloride
	name = REAGENT_SODIUMCHLORIDE
	id = REAGENT_ID_SODIUMCHLORIDE
	description = "A salt made of sodium chloride. Commonly used to season food."
	taste_description = "salt"
	reagent_state = SOLID
	color = "#FFFFFF"
	overdose = REAGENTS_OVERDOSE
	ingest_met = REM
	allergen_type = ALLERGEN_SALT
	cup_prefix = "salty"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BURN = 1))

/datum/reagent/sodiumchloride/affect_ingest(mob/living/carbon/M, alien, removed)
	var/pass_mod = rand(3,5)
	var/passthrough = (removed - (removed/pass_mod)) //Some may be nullified during consumption, between one third and one fifth.
	affect_blood(M, alien, passthrough)
	// The passthrough acts as blood, so it carries the blood route's species reaction.
	apply_species_injuries(M, species_injuries_blood, passthrough)

/datum/reagent/blackpepper
	name = REAGENT_BLACKPEPPER
	id = REAGENT_ID_BLACKPEPPER
	description = "A powder ground from peppercorns. *AAAACHOOO*"
	taste_description = "pepper"
	reagent_state = SOLID
	ingest_met = REM
	color = "#000000"
	cup_prefix = "peppery"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/mustardpods
	name = REAGENT_MUSTARDPODS
	id = REAGENT_ID_MUSTARDPODS
	description = "Densely-packed seed pods from a mustard plant. Good for making mustard. Not much use for anything else."
	taste_description = "sharp, bitter, dry mustard"
	reagent_state = SOLID
	ingest_met = REM
	color = "#B2A00D"
	cup_prefix = "mustardy"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/enzyme
	name = REAGENT_ENZYME
	id = REAGENT_ID_ENZYME
	description = "A universal enzyme used in the preperation of certain chemicals and foods."
	taste_description = "sweetness"
	taste_mult = 0.7
	reagent_state = LIQUID
	color = "#365E30"
	overdose = REAGENTS_OVERDOSE
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/spacespice
	name = REAGENT_SPACESPICE
	id = REAGENT_ID_SPACESPICE
	description = "An exotic blend of spices for cooking. Definitely not worms."
	reagent_state = SOLID
	color = "#e08702"
	cup_prefix = "spicy"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/browniemix
	name = REAGENT_BROWNIEMIX
	id = REAGENT_ID_BROWNIEMIX
	description = "A dry mix for making delicious brownies."
	reagent_state = SOLID
	color = "#441a03"
	allergen_type = ALLERGEN_CHOCOLATE
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/cakebatter
	name = REAGENT_CAKEBATTER
	id = REAGENT_ID_CAKEBATTER
	description = "A batter for making delicious cakes."
	reagent_state = LIQUID
	color = "#F0EDDA"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/frostoil
	name = REAGENT_FROSTOIL
	id = REAGENT_ID_FROSTOIL
	description = "A special oil that noticably chills the body. Extracted from Ice Peppers."
	taste_description = "mint"
	taste_mult = 1.5
	reagent_state = LIQUID
	ingest_met = REM
	color = "#B31008"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
	coolant_modifier = 2.5

/datum/reagent/frostoil
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/frostoil/affect_blood(mob/living/carbon/M, alien, removed)
	warm_body(M, -10 * TEMPERATURE_DAMAGE_COEFFICIENT, removed, min_temp = min(M.body_temperature(), 215))
	if(prob(1))
		M.emote("shiver")
	holder.remove_reagent(REAGENT_ID_CAPSAICIN, 5)

/datum/reagent/frostoil
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/frostoil/affect_ingest(mob/living/carbon/M, alien, removed) // Eating frostoil now acts like capsaicin. Wee!
	// Kept: plant people get a different, mild effect (not a strength).
	if(alien == IS_ALRAUNE) // It wouldn't affect plants that much.
		if(prob(5))
			to_chat(M, span_rose("You feel a chilly, tingling sensation in your mouth."))
		warm_body(M, -rand(10, 25), removed)
		return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return
	var/effective_dose = (dose * M.species.spice_mod)
	if((effective_dose < 5) && (dose == metabolism || prob(5)))
		to_chat(M, span_danger("Your insides suddenly feel a spreading chill!"))
	if(effective_dose >= 5)
		M.apply_effect(2 * M.species.spice_mod, AGONY, 0)
		warm_body(M, -rand(1, 5) * M.species.spice_mod, removed) // Really fucks you up, cause it makes you cold.
		if(prob(5))
			act_message(M, null, MSG_SELF(pick(span_danger("You feel like your insides are freezing!"), span_danger("Your insides feel like they're turning to ice!"))), \
				MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))
	// holder.remove_reagent(REAGENT_ID_CAPSAICIN, 5) // Nop, we don't instadelete spices for free.

/datum/reagent/frostoil/cryotoxin //A longer lasting version of frost oil.
	name = REAGENT_CRYOTOXIN
	id = REAGENT_ID_CRYOTOXIN
	description = "Lowers the body's internal temperature."
	reagent_state = LIQUID
	color = "#B31008"
	metabolism = REM * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI
	coolant_modifier = 3

/datum/reagent/capsaicin
	name = REAGENT_CAPSAICIN
	id = REAGENT_ID_CAPSAICIN
	description = "This is what makes chilis hot."
	taste_description = "hot peppers"
	taste_mult = 1.5
	reagent_state = LIQUID
	ingest_met = REM
	color = "#B31008"
	cup_prefix = "hot"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/capsaicin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/capsaicin/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 0.5 * removed, source = src)

/datum/reagent/capsaicin/affect_ingest(mob/living/carbon/M, alien, removed)
	// Do not call parent, we don't want this absorbed into our bloodstream!
	handle_spicy(M, alien, removed)

/datum/reagent/proc/handle_spicy(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	// Kept: plant people get a different, mild effect (not a strength).
	if(alien == IS_ALRAUNE) // It wouldn't affect plants that much.
		if(prob(5))
			to_chat(M, span_rose("You feel a pleasant sensation in your mouth."))
		warm_body(M, rand(10, 25), removed)
		return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return

	var/effective_dose = (dose * M.species.spice_mod)
	if((effective_dose < 5) && (dose == metabolism || prob(5)))
		to_chat(M, span_danger("Your insides feel uncomfortably hot!"))
	if(effective_dose >= 5)
		M.apply_effect(2 * M.species.spice_mod, AGONY, 0)
		warm_body(M, rand(1, 5) * M.species.spice_mod, removed) // Really fucks you up, cause it makes you overheat, too.
		if(prob(5))
			act_message(M, null, MSG_SELF(pick(span_danger("You feel like your insides are burning!"), span_danger("You feel like your insides are on fire!"), span_danger("You feel like your belly is full of lava!"))), \
				MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))
	// holder.remove_reagent(REAGENT_ID_FROSTOIL, 5) // Nop, we don't instadelete spices for free.

/datum/reagent/condensedcapsaicin
	name = REAGENT_CONDENSEDCAPSAICIN
	id = REAGENT_ID_CONDENSEDCAPSAICIN
	scannable = SCANNABLE_ADVANCED
	description = "A chemical agent used for self-defense and in police work."
	taste_description = "fire"
	dermal_absorption = 0
	taste_mult = 10
	reagent_state = LIQUID
	touch_met = 50 // Get rid of it quickly
	ingest_met = REM
	color = "#B31008"
	cup_prefix = "dangerously hot"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
	/// SPECIES_TAG_BIT mask of species whose exposed flesh the spray burns (gel bodies).
	var/skin_burned_species = SPECIES_TAG_BIT(IS_SLIME)

/datum/reagent/condensedcapsaicin/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 0.5 * removed, source = src)

/datum/reagent/condensedcapsaicin/affect_touch(mob/living/carbon/M, alien, removed)
	var/eyes_covered = 0
	var/mouth_covered = 0

	var/head_covered = 0
	var/arms_covered = 0 //These are used for the effects on slime-based species.
	var/legs_covered = 0
	var/hands_covered = 0
	var/feet_covered = 0
	var/chest_covered = 0
	var/groin_covered = 0

	var/obj/item/safe_thing = null

	var/effective_strength = 5
	// Species whose whole exposed surface burns (checked per body part below).
	var/skin_burns = species_in(M, skin_burned_species)


	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return
		if(H.get_equipped_item(SLOT_ID_HEAD))
			if(H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & EYES)
				eyes_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_HEAD)
			if((H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE) && !(H.get_equipped_item(SLOT_ID_HEAD).item_flags & FLEXIBLEMATERIAL))
				mouth_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_HEAD)
		if(H.get_equipped_item(SLOT_ID_MASK))
			if(!eyes_covered && H.get_equipped_item(SLOT_ID_MASK).body_parts_covered & EYES)
				eyes_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_MASK)
			if(!mouth_covered && (H.get_equipped_item(SLOT_ID_MASK).body_parts_covered & FACE) && !(H.get_equipped_item(SLOT_ID_MASK).item_flags & FLEXIBLEMATERIAL))
				mouth_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_MASK)
		if(H.get_equipped_item(SLOT_ID_EYES) && H.get_equipped_item(SLOT_ID_EYES).body_parts_covered & EYES)
			if(!eyes_covered)
				eyes_covered = 1
				if(!safe_thing)
					safe_thing = H.get_equipped_item(SLOT_ID_EYES)
		if(skin_burns)
			for(var/obj/item/clothing/C in H.get_worn_clothing())
				if(C.body_parts_covered & HEAD)
					head_covered = 1
				if(C.body_parts_covered & UPPER_TORSO)
					chest_covered = 1
				if(C.body_parts_covered & LOWER_TORSO)
					groin_covered = 1
				if(C.body_parts_covered & LEGS)
					legs_covered = 1
				if(C.body_parts_covered & ARMS)
					arms_covered = 1
				if(C.body_parts_covered & HANDS)
					hands_covered = 1
				if(C.body_parts_covered & FEET)
					feet_covered = 1
				if(head_covered && chest_covered && groin_covered && legs_covered && arms_covered && hands_covered && feet_covered)
					break
	if(eyes_covered && mouth_covered)
		to_chat(M, span_warning("Your [safe_thing] protects you from the pepperspray!"))
		if(!skin_burns)
			return
	else if(eyes_covered)
		to_chat(M, span_warning("Your [safe_thing] protects you from most of the pepperspray!"))
		M.status_at_least(STAT_BLURRY, effective_strength * 3)
		M.status_at_least(STAT_BLINDED, effective_strength)
		M.status_at_least(STAT_STUNNED, 5)
		M.status_at_least(STAT_WEAKENED, 5)
		if(!skin_burns)
			return
	else if(mouth_covered) // Mouth cover is better than eye cover
		to_chat(M, span_warning("Your [safe_thing] protects your face from the pepperspray!"))
		M.status_at_least(STAT_BLURRY, effective_strength)
		if(!skin_burns)
			return
	else// Oh dear :D
		to_chat(M, span_warning("You're sprayed directly in the eyes with pepperspray!"))
		M.status_at_least(STAT_BLURRY, effective_strength * 5)
		M.status_at_least(STAT_BLINDED, effective_strength * 2)
		M.status_at_least(STAT_STUNNED, 5)
		M.status_at_least(STAT_WEAKENED, 5)
		if(!skin_burns)
			return
	if(skin_burns)
		if(!head_covered)
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your head burns!"))
			M.apply_effect(5 * effective_strength, AGONY, 0)
		if(!chest_covered)
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your chest burns!"))
			M.apply_effect(5 * effective_strength, AGONY, 0)
		if(!groin_covered && prob(75))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your groin burns!"))
			M.apply_effect(3 * effective_strength, AGONY, 0)
		if(!arms_covered && prob(45))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your arms burns!"))
			M.apply_effect(3 * effective_strength, AGONY, 0)
		if(!legs_covered && prob(45))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your legs burns!"))
			M.apply_effect(3 * effective_strength, AGONY, 0)
		if(!hands_covered && prob(20))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your hands burns!"))
			M.apply_effect(effective_strength / 2, AGONY, 0)
		if(!feet_covered && prob(20))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your feet burns!"))
			M.apply_effect(effective_strength / 2, AGONY, 0)

/datum/reagent/condensedcapsaicin/affect_ingest(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return
	if(dose == metabolism)
		to_chat(M, span_danger("You feel like your insides are burning!"))
	else
		M.apply_effect(4, AGONY, 0)
		if(prob(5))
			act_message(M, null, MSG_SELF(span_danger("You feel like your insides are burning!")), \
				MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))

