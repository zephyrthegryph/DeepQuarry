/* Drinks */

/datum/reagent/drink
	name = REAGENT_DEVELOPER_WARNING // Unit test ignore
	id = REAGENT_ID_DRINK
	description = "Uh, some kind of drink."
	ingest_met = REM
	reagent_state = LIQUID
	color = "#E78108"
	var/nutrition = 0 // Per unit
	var/adj_dizzy = 0 // Per tick
	var/adj_drowsy = 0
	var/adj_sleepy = 0
	var/adj_temp = 0
	var/nutriment_factor = 0
	var/water_based = TRUE
	/// Rate at which this drink pulls species in `chilled_species` toward freezing (0: never).
	var/species_chill = 0
	/// SPECIES_TAG_BIT mask of species an iced drink chills (gel bodies take on the cold).
	var/chilled_species = SPECIES_TAG_BIT(IS_SLIME)
	dermal_absorption = 0
	/// SPECIES_TAG_BIT mask of species a water-based drink poisons three times as hard.
	var/water_sensitive_species = SPECIES_TAG_BIT(IS_SLIME)
	wiki_flag = WIKI_DRINK
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
	coolant_modifier = 0.8

/datum/reagent/drink/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = (water_based && species_in(M, water_sensitive_species)) ? 3 : 1
	M.injure(INJURY_TOXIN, removed * strength_mod, source = src) // Probably not a good idea; not very deadly though
	return

/// The chill rate this tick for `species_chill` (ice overrides it with a random rate).
/datum/reagent/drink/proc/species_chill_rate()
	return species_chill

/// Pull a species in `chilled_species` toward freezing, scaled by the amount metabolised.
/datum/reagent/drink/proc/apply_species_chill(mob/living/carbon/M, removed)
	if(species_chill && species_in(M, chilled_species))
		drive_body_temperature(M, T0C, species_chill_rate(), removed)

/// A drink's pull on body temperature toward `target` (B12). A warm drink (adj > 0) only warms
/// a body below the target and a cold one (adj < 0) only cools a body above it, and neither
/// overshoots. The cold branch used to subtract a negative number, heating the drinker.
/proc/drink_temperature_step(current, target, adj)
	if(adj > 0 && current < target)
		return min(target, current + adj * TEMPERATURE_DAMAGE_COEFFICIENT)
	if(adj < 0 && current > target)
		return max(target, current + adj * TEMPERATURE_DAMAGE_COEFFICIENT)
	return current

/datum/reagent/drink/affect_ingest(mob/living/carbon/M, alien, removed)
	if(!(M.species.allergens & allergen_type) && !(M.species.medallergens & medallergen_type))
		var/bonus = M.food_preference(allergen_type)
		M.adjust_nutrition((nutrition + bonus) * removed)
	M.status_adjust(STAT_DIZZY, adj_dizzy)
	M.status_adjust(STAT_DROWSY, adj_drowsy)
	M.status_adjust(STAT_SLEEPING, adj_sleepy)
	if(adj_temp)
		drive_body_temperature(M, BODYTEMP_NORMAL, abs(adj_temp) * TEMPERATURE_DAMAGE_COEFFICIENT, removed, warm = adj_temp > 0, cool = adj_temp < 0)
	if(issmall(M)) removed *= 2
	// B18: through adjust_nutrition (its clamp), scaled by the coefficient instead of gated on it.
	if(M.species.organic_food_coeff)
		M.adjust_nutrition(nutriment_factor * removed * M.species.organic_food_coeff)

/datum/reagent/drink/overdose(mob/living/carbon/M, alien) //Add special interactions here in the future if desired.
	..()

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

/datum/reagent/drink/juice/carrot
	name = REAGENT_CARROTJUICE
	id = REAGENT_ID_CARROTJUICE
	description = "It is just like a carrot but without crunching."
	taste_description = "carrots"
	color = "#FF8C00" // rgb: 255, 140, 0

	glass_name = "carrot juice"
	glass_desc = "It is just like a carrot but without crunching."
	allergen_type = ALLERGEN_VEGETABLE //Carrots are vegetables
	cup_prefix = "carrot"

/datum/reagent/drink/juice/carrot/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.reagents.add_reagent(REAGENT_ID_IMIDAZOLINE, removed * 0.2)

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

// Orange juice's mild oxygenation is its treatment_tags profile.

/datum/reagent/toxin/poisonberryjuice // It has more in common with toxins than drinks... but it's a juice
	name = REAGENT_POISONBERRYJUICE
	id = REAGENT_ID_POISONBERRYJUICE
	description = "A tasty juice blended from various kinds of very deadly and toxic berries."
	taste_description = "berries"
	color = "#863353"
	strength = 5

	glass_name = "poison berry juice"
	glass_desc = "A glass of deadly juice."
	cup_prefix = "poison"
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

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

// Everything else

/datum/reagent/drink/milk
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)
	name = REAGENT_MILK
	id = REAGENT_ID_MILK
	description = "An opaque white liquid produced by the mammary glands of mammals."
	taste_description = "milk"
	color = "#DFDFDF"

	glass_name = REAGENT_ID_MILK
	glass_desc = "White and nutritious goodness!"

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_MILK
	cup_desc = "White and nutritious goodness!"
	allergen_type = ALLERGEN_DAIRY //Milk is dairy

/datum/reagent/drink/milk/chocolate
	name =  REAGENT_CHOCOLATEMILK
	id = REAGENT_ID_CHOCOLATEMILK
	description = "A delicious mixture of perfectly healthy mix and terrible chocolate."
	taste_description = "chocolate milk"
	color = "#74533b"

	cup_icon_state = "cup_brown"
	cup_name = "chocolate milk"
	cup_desc = "Deliciously fattening!"

	glass_name = "chocolate milk"
	glass_desc = "Deliciously fattening!"
	allergen_type = ALLERGEN_CHOCOLATE

/datum/reagent/drink/milk/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	// Milk's light tissue repair is its treatment_tags profile.
	holder.remove_reagent(REAGENT_ID_CAPSAICIN, 10 * removed)
	if(ishuman(M) && rand(1,10000) == 1)
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			if(dq_reagent_knit_fracture(O))
				H.custom_pain("You feel the agonizing power of calcium mending your bones!",60)
				H.injure(INJURY_PAIN, 60, O.organ_tag, source = src)
				H.status_adjust(STAT_STUNNED, 1) // Crawling again, weakened to stunned
				break // Only mend one bone, whichever comes first in the list

/datum/reagent/drink/milk/cream
	name = REAGENT_CREAM
	id = REAGENT_ID_CREAM
	description = "The fatty, still liquid part of milk. Why don't you mix this with sum scotch, eh?"
	taste_description = "thick milk"
	color = "#DFD7AF"

	glass_name = REAGENT_ID_CREAM
	glass_desc = "Ewwww..."

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_CREAM
	cup_desc = "Ewwww..."
	allergen_type = ALLERGEN_DAIRY //Cream is dairy

/datum/reagent/drink/milk/soymilk
	name = REAGENT_SOYMILK
	id = REAGENT_ID_SOYMILK
	description = "An opaque white liquid made from soybeans."
	taste_description = "soy milk"
	color = "#DFDFC7"

	glass_name = "soy milk"
	glass_desc = "White and nutritious soy goodness!"

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_MILK
	cup_desc = "White and nutritious goodness!"
	allergen_type = ALLERGEN_BEANS //Would be made from soy beans

/datum/reagent/drink/milk/foam
	name = REAGENT_MILKFOAM
	id = REAGENT_ID_MILKFOAM
	description = "Light and airy foamed milk."
	taste_description = "airy milk"
	color = "#eeebdf"

	glass_name = "foam"
	glass_desc = "Fluffy..."

	cup_icon_state = "cup_cream"
	cup_name = "foam"
	cup_desc = "Fluffy..."
	allergen_type = ALLERGEN_DAIRY //Cream is dairy


/datum/reagent/drink/tea
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)
	name = REAGENT_TEA
	id = REAGENT_ID_TEA
	description = "Tasty black tea, it has antioxidants, it's good for you!"
	taste_description = "black tea"
	color = "#832700"
	adj_dizzy = -2
	adj_drowsy = -1
	adj_sleepy = -3
	adj_temp = 20

	glass_name = "cup of tea"
	glass_desc = "Tasty black tea, it has antioxidants, it's good for you!"

	cup_icon_state = "cup_tea"
	cup_name = REAGENT_ID_TEA
	cup_desc = "Tasty black tea, it has antioxidants, it's good for you!"
	allergen_type = ALLERGEN_STIMULANT //Black tea strong enough to have significant caffeine content

// Tea's mild antitoxin action is its treatment_tags profile.

/datum/reagent/drink/tea/decaf
	name = REAGENT_TEADECAF
	id = REAGENT_ID_TEADECAF
	description = "Tasty black tea, it has antioxidants, it's good for you, and won't keep you up at night!"
	color = "#832700"
	adj_dizzy = 0
	adj_drowsy = 0 //Decaf won't help you here.
	adj_sleepy = 0

	glass_name = "cup of decaf tea"
	glass_desc = "Tasty black tea, it has antioxidants, it's good for you, and won't keep you up at night!"

	cup_name = "decaf tea"
	cup_desc = "Tasty black tea, it has antioxidants, it's good for you, and won't keep you up at night!"
	allergen_type = null //Certified cat-safe!


/datum/reagent/drink/tea/icetea
	name = REAGENT_ICETEA
	id = REAGENT_ID_ICETEA
	description = "No relation to a certain rap artist/ actor."
	taste_description = "sweet tea"
	color = "#AC7F24" // rgb: 16, 64, 56
	adj_temp = -5

	glass_name = "iced tea"
	glass_desc = "No relation to a certain rap artist/ actor."
	glass_special = list(DRINK_ICE)

	cup_icon_state = "cup_tea"
	cup_name = "iced tea"
	cup_desc = "No relation to a certain rap artist/ actor."

/datum/reagent/drink/tea/icetea
	species_chill = 0.5

/datum/reagent/drink/tea/icetea/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/tea/icetea/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/tea/icetea/decaf
	name = REAGENT_ICETEADECAF
	id = REAGENT_ID_ICETEADECAF
	glass_name = "decaf iced tea"
	cup_name = "decaf iced tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = null

/datum/reagent/drink/tea/minttea
	name = REAGENT_MINTTEA
	id = REAGENT_ID_MINTTEA
	description = "A tasty mixture of mint and tea. It's apparently good for you!"
	color = "#A8442C"
	taste_description = "black tea with tones of mint"

	glass_name = "mint tea"
	glass_desc = "A tasty mixture of mint and tea. It's apparently good for you!"

	cup_name = "mint tea"
	cup_desc = "A tasty mixture of mint and tea. It's apparently good for you!"

/datum/reagent/drink/tea/minttea/decaf
	name = REAGENT_MINTTEADECAF
	id = REAGENT_ID_MINTTEADECAF
	glass_name = "decaf mint tea"
	cup_name = "decaf mint tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = null

/datum/reagent/drink/tea/lemontea
	name = REAGENT_LEMONTEA
	id = REAGENT_ID_LEMONTEA
	description = "A tasty mixture of lemon and tea. It's apparently good for you!"
	color = "#FC6A00"
	taste_description = "black tea with tones of lemon"

	glass_name = "lemon tea"
	glass_desc = "A tasty mixture of lemon and tea. It's apparently good for you!"

	cup_name = "lemon tea"
	cup_desc = "A tasty mixture of lemon and tea. It's apparently good for you!"
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with lemon juice, still tea

/datum/reagent/drink/tea/lemontea/decaf
	name = REAGENT_LEMONTEADECAF
	id = REAGENT_ID_LEMONTEADECAF
	glass_name = "decaf lemon tea"
	cup_name = "decaf lemon tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = ALLERGEN_FRUIT //No caffine, still lemon.

/datum/reagent/drink/tea/limetea
	name = REAGENT_LIMETEA
	id = REAGENT_ID_LIMETEA
	description = "A tasty mixture of lime and tea. It's apparently good for you!"
	color = "#DE4300"
	taste_description = "black tea with tones of lime"

	glass_name = "lime tea"
	glass_desc = "A tasty mixture of lime and tea. It's apparently good for you!"

	cup_name = "lime tea"
	cup_desc = "A tasty mixture of lime and tea. It's apparently good for you!"
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with lime juice, still tea

/datum/reagent/drink/tea/limetea/decaf
	name = REAGENT_LIMETEADECAF
	id = REAGENT_ID_LIMETEADECAF
	glass_name = "decaf lime tea"
	cup_name = "decaf lime tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = ALLERGEN_FRUIT //No caffine, still lime.

/datum/reagent/drink/tea/orangetea
	name = REAGENT_ORANGETEA
	id = REAGENT_ID_ORANGETEA
	description = "A tasty mixture of orange and tea. It's apparently good for you!"
	color = "#FB4F06"
	taste_description = "black tea with tones of orange"

	glass_name = "orange tea"
	glass_desc = "A tasty mixture of orange and tea. It's apparently good for you!"

	cup_name = "orange tea"
	cup_desc = "A tasty mixture of orange and tea. It's apparently good for you!"
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with orange juice, still tea

/datum/reagent/drink/tea/orangetea/decaf
	name = REAGENT_ORANGETEADECAF
	id = REAGENT_ID_ORANGETEADECAF
	glass_name = "decaf orange tea"
	cup_name = "decaf orange tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = ALLERGEN_FRUIT //No caffine, still orange.

/datum/reagent/drink/tea/berrytea
	name = REAGENT_BERRYTEA
	id = REAGENT_ID_BERRYTEA
	description = "A tasty mixture of berries and tea. It's apparently good for you!"
	color = "#A60735"
	taste_description = "black tea with tones of berries"

	glass_name = "berry tea"
	glass_desc = "A tasty mixture of berries and tea. It's apparently good for you!"

	cup_name = "berry tea"
	cup_desc = "A tasty mixture of berries and tea. It's apparently good for you!"
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with berry juice, still tea

/datum/reagent/drink/tea/berrytea/decaf
	name = REAGENT_BERRYTEADECAF
	id = REAGENT_ID_BERRYTEADECAF
	glass_name = "decaf berry tea"
	cup_name = "decaf berry tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = ALLERGEN_FRUIT //No caffine, still berries.

/datum/reagent/drink/greentea
	name = REAGENT_GREENTEA
	id = REAGENT_ID_GREENTEA
	description = "A subtle blend of green tea. It's apparently good for you!"
	color = "#A8442C"
	taste_description = "green tea"

	glass_name = "green tea"
	glass_desc = "A subtle blend of green tea. It's apparently good for you!"

	cup_name = "green tea"
	cup_desc = "A subtle blend of green tea. It's apparently good for you!"

/datum/reagent/drink/tea/chaitea
	name = REAGENT_CHAITEA
	id = REAGENT_ID_CHAITEA
	description = "A milky tea spiced with cinnamon and cloves."
	color = "#A8442C"
	taste_description = "creamy cinnamon and spice"

	glass_name = "chai tea"
	glass_desc = "A milky tea spiced with cinnamon and cloves."

	cup_name = "chai tea"
	cup_desc = "A milky tea spiced with cinnamon and cloves."
	allergen_type = ALLERGEN_STIMULANT|ALLERGEN_DAIRY //Made with milk and tea.

/datum/reagent/drink/tea/chaitea/decaf
	name = REAGENT_CHAITEADECAF
	id = REAGENT_ID_CHAITEADECAF
	glass_name = "decaf chai tea"
	cup_name = "decaf chai tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = ALLERGEN_DAIRY //No caffeine, still milk.

/datum/reagent/drink/coffee
	name = REAGENT_COFFEE
	id = REAGENT_ID_COFFEE
	description = "Coffee is a brewed drink prepared from roasted seeds, commonly called coffee beans, of the coffee plant."
	taste_description = "coffee"
	taste_mult = 1.3
	color = "#482000"
	adj_dizzy = -5
	adj_drowsy = -3
	adj_sleepy = -2
	adj_temp = 25
	overdose = REAGENTS_OVERDOSE *1.5

	cup_icon_state = "cup_coffee"
	cup_name = REAGENT_ID_COFFEE
	cup_desc = "Don't drop it, or you'll send scalding liquid and ceramic shards everywhere."

	glass_name = REAGENT_ID_COFFEE
	glass_desc = "Don't drop it, or you'll send scalding liquid and glass shards everywhere."
	allergen_type = ALLERGEN_COFFEE | ALLERGEN_STIMULANT //Apparently coffee contains coffee

/datum/reagent/drink/coffee/affect_ingest(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	..()

	if(adj_temp > 0)
		holder.remove_reagent(REAGENT_ID_FROSTOIL, 10 * removed)

/datum/reagent/drink/coffee/affect_blood(mob/living/carbon/M, alien, removed)
	..()


/datum/reagent/drink/coffee/overdose(mob/living/carbon/M, alien)
	if(inert_for(M))
		return
	M.status_adjust(STAT_JITTERY, 5)

/datum/reagent/drink/coffee/handle_addiction(mob/living/carbon/M, alien)
	// A copy of the base with withdrawl, but with much less effects, no vomiting and sometimes pain
	var/current_addiction = M.get_addiction_to_reagent(id)
	// slow degrade
	if(prob(8))
		current_addiction  -= 1
	// withdrawl mechanics
	if(prob(2))
		if(current_addiction < 90 && prob(10))
			to_chat(M, span_warning("[pick("You feel miserable.","You feel sluggish.","You get a small headache.")]"))
			M.injure(INJURY_PAIN, 2, source = src)
		else if(current_addiction <= 50)
			to_chat(M, span_warning("You're really craving some [name]."))
		else if(current_addiction <= 100)
			to_chat(M, span_notice("You're feeling the need for some [name]."))
		// effects
		if(current_addiction < 60 && prob(20))
			M.emote(pick("pale","shiver","twitch"))
	if(current_addiction <= 0) //safety
		current_addiction = 0
	return current_addiction

/datum/reagent/drink/coffee/icecoffee
	name = REAGENT_ICECOFFEE
	id = REAGENT_ID_ICECOFFEE
	description = "Coffee and ice, refreshing and cool."
	color = "#102838"
	adj_temp = -5

	glass_name = "iced coffee"
	glass_desc = "A drink to perk you up and refresh you!"
	glass_special = list(DRINK_ICE)

/datum/reagent/drink/coffee/icecoffee
	species_chill = 0.5

/datum/reagent/drink/coffee/icecoffee/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/coffee/icecoffee/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/coffee/soy_latte
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)
	name = REAGENT_SOYLATTE
	id = REAGENT_ID_SOYLATTE
	description = "A nice and tasty beverage while you are reading your hippie books."
	taste_description = "creamy coffee"
	color = "#C65905"
	adj_temp = 5

	glass_desc = "A nice and refreshing beverage while you are reading."
	glass_name = "soy latte"

	cup_icon_state = "cup_latte"
	cup_name = "soy latte"
	cup_desc = "A nice and refreshing beverage while you are reading."
	allergen_type = ALLERGEN_COFFEE|ALLERGEN_BEANS 	//Soy(beans) and coffee

// Soy latte's light tissue repair is its treatment_tags profile.

/datum/reagent/drink/coffee/cafe_latte
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)
	name = REAGENT_CAFELATTE
	id = REAGENT_ID_CAFELATTE
	description = "A nice, strong and tasty beverage while you are reading."
	taste_description = "bitter cream"
	color = "#C65905"
	adj_temp = 5

	glass_name = "cafe latte"
	glass_desc = "A nice, strong and refreshing beverage while you are reading."

	cup_icon_state = "cup_latte"
	cup_name = "cafe latte"
	cup_desc = "A nice and refreshing beverage while you are reading."
	allergen_type = ALLERGEN_COFFEE|ALLERGEN_DAIRY //Cream and coffee

// Cafe latte's light tissue repair is its treatment_tags profile.

/datum/reagent/drink/decaf
	name = REAGENT_DECAF
	id = REAGENT_ID_DECAF
	description = "Coffee with at least 97% of its caffeine content removed. All of the flavor, none of the kick!" // In defense of decaf coffee
	taste_description = "coffee" // In defense of decaf coffee
	taste_mult = 1.3
	color = "#482000"
	adj_temp = 25

	cup_icon_state = "cup_coffee"
	cup_name = REAGENT_ID_DECAF
	cup_desc = "Just as bitter as regular coffee, but it won't keep you up at night!" // In defense of decaf coffee

	glass_name = "decaf coffee"
	glass_desc = "Just as bitter as regular coffee, but it won't keep you up at night!" // In defense of decaf coffee
	allergen_type = ALLERGEN_COFFEE //Decaf coffee is still coffee, just less stimulating.

/datum/reagent/drink/hot_coco
	name = REAGENT_HOTCOCO
	id = REAGENT_ID_HOTCOCO
	description = "Made with love! And cocoa beans."
	taste_description = "creamy chocolate"
	reagent_state = LIQUID
	color = "#403010"
	nutrition = 2
	adj_temp = 5

	glass_name = "hot chocolate"
	glass_desc = "Made with love! And cocoa beans."

	cup_icon_state = "cup_coco"
	cup_name = "hot chocolate"
	cup_desc = "Made with love! And cocoa beans."
	allergen_type = ALLERGEN_CHOCOLATE

/datum/reagent/drink/coffee/blackeye
	name = REAGENT_BLACKEYE
	id = REAGENT_ID_BLACKEYE
	description = "Coffee but with more coffee for that extra coffee kick."
	taste_description = "very concentrated coffee"
	color = "#241001"
	adj_temp = 5

	glass_desc = "Coffee but with more coffee for that extra coffee kick."
	glass_name = "black eye coffee"

	cup_icon_state = "cup_coffee"
	cup_name = "black eye coffee"
	cup_desc = "Coffee but with more coffee for that extra coffee kick."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/drip
	name = REAGENT_DRIPCOFFEE
	id = REAGENT_ID_DRIPCOFFEE
	description = "Coffee made by soaking beans in hot water and allowing it seep through."
	taste_description = "very concentrated coffee"
	color = "#3d1a00"
	adj_temp = 5

	glass_desc = "Coffee made by soaking beans in hot water and allowing it seep through."
	glass_name = "drip coffee"

	cup_icon_state = "cup_coffee"
	cup_name = "drip brewed coffee"
	cup_desc = "Coffee made by soaking beans in hot water and allowing it seep through."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/americano
	name = REAGENT_AMERICANO
	id = REAGENT_ID_AMERICANO
	description = "A traditional coffee that is more dilute and perfect for a gentle start to the day."
	taste_description = "pleasant coffee"
	color = "#6d3205"
	adj_temp = 5

	glass_desc = "A traditional coffee that is more dilute and perfect for a gentle start to the day."
	glass_name = REAGENT_ID_AMERICANO

	cup_icon_state = "cup_coffee"
	cup_name = REAGENT_ID_AMERICANO
	cup_desc = "A traditional coffee that is more dilute and perfect for a gentle start to the day."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/long_black
	name = REAGENT_LONGBLACK
	id = REAGENT_ID_LONGBLACK
	description = "A traditional coffee with a little more kick."
	taste_description = "modestly bitter coffee"
	color = "#6d3205"
	adj_temp = 5

	glass_desc = "A traditional coffee with a little more kick."
	glass_name = REAGENT_ID_LONGBLACK

	cup_icon_state = "cup_coffee"
	cup_name = "long black coffee"
	cup_desc = "A traditional coffee with a little more kick."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/macchiato
	name = REAGENT_MACCHIATO
	id = REAGENT_ID_MACCHIATO
	description = "A coffee mixed with steamed milk, it has swirling patterns on top."
	taste_description = "milky coffee"
	color = "#ad5817"
	adj_temp = 5

	glass_desc = "A coffee mixed with steamed milk, it has swirling patterns on top."
	glass_name = REAGENT_ID_MACCHIATO

	cup_icon_state = "cup_latte"
	cup_name = REAGENT_ID_MACCHIATO
	cup_desc = "A coffee mixed with steamed milk, it has swirling patterns on top."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/cortado
	name = REAGENT_CORTADO
	id = REAGENT_ID_CORTADO
	description = "Espresso mixed with equal parts milk and a layer of foam on top."
	taste_description = "milky coffee"
	color = "#ad5817"
	adj_temp = 5

	glass_desc = "Espresso mixed with equal parts milk and a layer of foam on top."
	glass_name = REAGENT_ID_CORTADO

	cup_icon_state = "cup_latte"
	cup_name = REAGENT_ID_CORTADO
	cup_desc = "Espresso mixed with equal parts milk and a layer of foam on top."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/breve
	name = REAGENT_BREVE
	id = REAGENT_ID_BREVE
	description = "Espresso topped with half-and-half, with a layer of foam on top."
	taste_description = "creamy coffee"
	color = "#d1905e"
	adj_temp = 5

	glass_desc = "Espresso topped with half-and-half, with a layer of foam on top."
	glass_name = REAGENT_ID_BREVE

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_BREVE
	cup_desc = "Espresso topped with half-and-half, with a layer of foam on top."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/cappuccino
	name = REAGENT_CAPPUCCINO
	id = REAGENT_ID_CAPPUCCINO
	description = "Espresso with a large portion of milk and a hefty layer of foam."
	taste_description = "classic coffee"
	color = "#d1905e"
	adj_temp = 5

	glass_desc = "Espresso with a large portion of milk and a hefty layer of foam."
	glass_name = REAGENT_ID_CAPPUCCINO

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_CAPPUCCINO
	cup_desc = "Espresso with a large portion of milk and a hefty layer of foam."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/flat_white
	name = REAGENT_FLATWHITE
	id = REAGENT_ID_FLATWHITE
	description = "A very milky coffee that is particularly light and airy."
	taste_description = "very milky coffee"
	color = "#ed9f64"
	adj_temp = 5

	glass_desc = "A very milky coffee that is particularly light and airy."
	glass_name = REAGENT_ID_FLATWHITE

	cup_icon_state = "cup_latte"
	cup_name = "flat white coffee"
	cup_desc = "A very milky coffee that is particularly light and airy."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/mocha
	name = REAGENT_MOCHA
	id = REAGENT_ID_MOCHA
	description = "A chocolate and coffee mix topped with a lot of milk and foam."
	taste_description = "chocolatey coffee"
	color = "#984201"
	adj_temp = 5

	glass_desc = "A chocolate and coffee mix topped with a lot of milk and foam."
	glass_name = REAGENT_ID_MOCHA

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_MOCHA
	cup_desc = "A chocolate and coffee mix topped with a lot of milk and foam."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/coffee/vienna
	name = REAGENT_VIENNA
	id = REAGENT_ID_VIENNA
	description = "A very sweet espresso topped with a lot of whipped cream."
	taste_description = "super sweet and creamy coffee"
	color = "#8e7059"
	adj_temp = 5

	glass_desc = "A very sweet espresso topped with a lot of whipped cream."
	glass_name = REAGENT_ID_VIENNA

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_VIENNA
	cup_desc = "A very sweet espresso topped with a lot of whipped cream."
	allergen_type = ALLERGEN_COFFEE

/datum/reagent/drink/soda/sodawater
	name = REAGENT_SODAWATER
	id = REAGENT_ID_SODAWATER
	description = "A can of club soda. Why not make a scotch and soda?"
	taste_description = "carbonated water"
	color = "#619494"
	adj_dizzy = -5
	adj_drowsy = -3
	adj_temp = -5
	cup_prefix = "fizzy"

	glass_name = "soda water"
	glass_desc = "Soda water. Why not make a scotch and soda?"
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/grapesoda
	nutriment_factor = 1.5
	cup_prefix = "grape soda"

/datum/reagent/drink/soda/tonic
	name = REAGENT_TONIC
	id = REAGENT_ID_TONIC
	description = "It tastes strange but at least the quinine keeps the Space Malaria at bay."
	taste_description = "tart and fresh"
	color = "#619494"
	cup_prefix = REAGENT_ID_TONIC

	adj_dizzy = -5
	adj_drowsy = -3
	adj_sleepy = -2
	adj_temp = -5

	glass_name = "tonic water"
	glass_desc = "Quinine tastes funny, but at least it'll keep that Space Malaria away."

/datum/reagent/drink/soda/lemonade
	name = REAGENT_LEMONADE
	id = REAGENT_ID_LEMONADE
	description = "Oh the nostalgia..."
	taste_description = REAGENT_ID_LEMONADE
	nutriment_factor = 1.5
	color = "#FFFF00"
	adj_temp = -5
	cup_prefix = REAGENT_ID_LEMONADE

	glass_name = REAGENT_ID_LEMONADE
	glass_desc = "Oh the nostalgia..."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with lemon juice

/datum/reagent/drink/soda/melonade
	name = REAGENT_MELONADE
	id = REAGENT_ID_MELONADE
	description = "Oh the.. nostalgia?"
	taste_description = "watermelon"
	nutriment_factor = 1.5
	color = "#FFB3BB"
	adj_temp = -5
	cup_prefix = REAGENT_ID_MELONADE

	glass_name = REAGENT_ID_MELONADE
	glass_desc = "Oh the.. nostalgia?"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with watermelon juice

/datum/reagent/drink/soda/appleade
	name = REAGENT_APPLEADE
	id = REAGENT_ID_APPLEADE
	description = "Applejuice, improved."
	taste_description = "apples"
	nutriment_factor = 1.5
	color = "#FFD1B3"
	adj_temp = -5
	cup_prefix = REAGENT_ID_APPLEADE

	glass_name = REAGENT_ID_APPLEADE
	glass_desc = "Applejuice, improved."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with apple juice

/datum/reagent/drink/soda/pineappleade
	name = REAGENT_PINEAPPLEADE
	id = REAGENT_ID_PINEAPPLEADE
	description = "Pineapple, juiced up."
	taste_description = "sweet`n`sour pineapples"
	nutriment_factor = 5
	color = "#FFFF00"
	adj_temp = -5
	cup_prefix = REAGENT_ID_PINEAPPLEADE

	glass_name = REAGENT_ID_PINEAPPLEADE
	glass_desc = "Pineapple, juiced up."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with pineapple juice

/datum/reagent/drink/soda/kiraspecial
	name = REAGENT_KIRASPECIAL
	id = REAGENT_ID_KIRASPECIAL
	description = "Long live the guy who everyone had mistaken for a girl. Baka!"
	taste_description = "fruity sweetness"
	nutriment_factor = 1.5
	color = "#CCCC99"
	adj_temp = -5

	glass_name = REAGENT_KIRASPECIAL
	glass_desc = "Long live the guy who everyone had mistaken for a girl. Baka!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made from orange and lime juice

/datum/reagent/drink/soda/brownstar
	name = REAGENT_BROWNSTAR
	id = REAGENT_ID_BROWNSTAR
	description = "It's not what it sounds like..."
	taste_description = "orange and cola soda"
	nutriment_factor = 1.5
	color = "#9F3400"
	adj_temp = -2

	glass_name = REAGENT_BROWNSTAR
	glass_desc = "It's not what it sounds like..."
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with orangejuice and cola

/datum/reagent/drink/soda/brownstar_decaf //For decaf starkist
	name = REAGENT_BROWNSTARDECAF
	id = REAGENT_ID_BROWNSTARDECAF
	description = "It's not what it sounds like..."
	taste_description = "orange and cola soda"
	color = "#9F3400"
	adj_temp = -2

	glass_name = REAGENT_BROWNSTAR
	glass_desc = "It's not what it sounds like..."

/datum/reagent/drink/milkshake
	name = REAGENT_MILKSHAKE
	id = REAGENT_ID_MILKSHAKE
	description = "Glorious brainfreezing mixture."
	taste_description = "vanilla milkshake"
	color = "#AEE5E4"
	adj_temp = -9

	glass_name = REAGENT_ID_MILKSHAKE
	glass_desc = "Glorious brainfreezing mixture."
	allergen_type = ALLERGEN_DAIRY //Made with dairy products

/datum/reagent/drink/milkshake/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	var/effective_dose = dose/2
	if(issmall(M))
		effective_dose *= 2

	sugar_sedation(M, effective_dose)

/datum/reagent/drink/milkshake/chocoshake
	name = REAGENT_CHOCOSHAKE
	id = REAGENT_ID_CHOCOSHAKE
	description = "A refreshing chocolate milkshake."
	taste_description = "cold refreshing chocolate and cream"
	color = "#8e6f44" // rgb(142, 111, 68)
	adj_temp = -9

	glass_name = REAGENT_CHOCOSHAKE
	glass_desc = "A refreshing chocolate milkshake, just like mom used to make."
	allergen_type = ALLERGEN_DAIRY|ALLERGEN_CHOCOLATE //Made with dairy products

/datum/reagent/drink/milkshake/berryshake
	name = REAGENT_BERRYSHAKE
	id = REAGENT_ID_BERRYSHAKE
	description = "A refreshing berry milkshake."
	taste_description = "cold refreshing berries and cream"
	color = "#ffb2b2" // rgb(255, 178, 178)
	adj_temp = -9

	glass_name = REAGENT_BERRYSHAKE
	glass_desc = "A refreshing berry milkshake, just like mom used to make."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY //Made with berry juice and dairy products

/datum/reagent/drink/milkshake/coffeeshake
	name = REAGENT_COFFEESHAKE
	id = REAGENT_ID_COFFEESHAKE
	description = "A refreshing coffee milkshake."
	taste_description = "cold energizing coffee and cream"
	color = "#8e6f44" // rgb(142, 111, 68)
	adj_temp = -9
	adj_dizzy = -5
	adj_drowsy = -3
	adj_sleepy = -2

	glass_name = REAGENT_COFFEESHAKE
	glass_desc = "An energizing coffee milkshake, perfect for hot days at work.."
	allergen_type = ALLERGEN_DAIRY|ALLERGEN_COFFEE //Made with coffee and dairy products

/datum/reagent/drink/milkshake/coffeeshake/overdose(mob/living/carbon/M, alien)
	M.status_adjust(STAT_JITTERY, 5)

/datum/reagent/drink/milkshake/peanutshake
	name = REAGENT_PEANUTMILKSHAKE
	id = REAGENT_ID_PEANUTMILKSHAKE
	description = "Savory cream in an ice-cold stature."
	taste_description = "cold peanuts and cream"
	color = "#8e6f44"

	glass_name = REAGENT_PEANUTMILKSHAKE
	glass_desc = "Savory cream in an ice-cold stature."
	allergen_type = ALLERGEN_SEEDS|ALLERGEN_DAIRY //Made with peanutbutter(seeds) and dairy products

/datum/reagent/drink/rewriter
	name = REAGENT_REWRITER
	id = REAGENT_ID_REWRITER
	description = "The secret of the sanctuary of the Libarian..."
	taste_description = "citrus and coffee"
	nutriment_factor = 1.5
	color = "#485000"
	adj_temp = -5

	glass_name = REAGENT_REWRITER
	glass_desc = "The secret of the sanctuary of the Libarian..."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Made with space mountain wind (Fruit, caffeine)

/datum/reagent/drink/rewriter/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.status_adjust(STAT_JITTERY, 5)

/datum/reagent/drink/soda/nuka_cola
	factors = alist(BF_SLOWDOWN = -1, BF_PENALTY_SCALE = 0.5)
	name = REAGENT_NUKACOLA
	id = REAGENT_ID_NUKACOLA
	description = "Cola, cola never changes."
	taste_description = "cola"
	nutriment_factor = 1.5
	color = "#100800"
	adj_temp = -5
	adj_sleepy = -2

	glass_name = "Nuka-Cola"
	glass_desc = "Don't cry, Don't raise your eye, It's only nuclear wasteland"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_STIMULANT

/datum/reagent/drink/soda/nuka_cola/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.status_adjust(STAT_JITTERY, 20)
	M.status_at_least(STAT_DRUGGED, 30)
	M.status_adjust(STAT_DIZZY, 5)
	M.status_set(STAT_DROWSY, 0)

/datum/reagent/drink/grenadine 	//Description implies that the grenadine we would be working with does not contain fruit, so no allergens.
	name = REAGENT_GRENADINE
	id = REAGENT_ID_GRENADINE
	description = "Made in the modern day with proper pomegranate substitute. Who uses real fruit, anyways?"
	taste_description = "100% pure pomegranate"
	color = "#FF004F"
	water_based = FALSE

	glass_name = "grenadine syrup"
	glass_desc = "Sweet and tangy, a bar syrup used to add color or flavor to drinks."

/datum/reagent/drink/soda/space_cola
	name = REAGENT_COLA
	id = REAGENT_ID_COLA
	description = "A refreshing beverage."
	taste_description = "cola"
	nutriment_factor = 1.5
	reagent_state = LIQUID
	color = "#100800"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_COLA
	glass_desc = "A glass of refreshing Space Cola"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_STIMULANT //Cola is typically caffeinated.

/datum/reagent/drink/soda/decaf_cola
	name = REAGENT_DECAFCOLA
	id = REAGENT_ID_DECAFCOLA
	description = "A refreshing beverage with none of the jitters."
	taste_description = "cola"
	reagent_state = LIQUID
	color = "#100800"
	adj_temp = -5

	glass_name = REAGENT_DECAFCOLA
	glass_desc = "A glass of refreshing Space Cola Free"
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/lemon_soda
	name = REAGENT_LEMONSODA
	id = REAGENT_ID_LEMONSODA
	description = "Soda made using lemon concentrate. Sour."
	taste_description = "strong sourness"
	reagent_state = LIQUID
	color = "#ffe658"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = "lemon Soda"
	glass_desc = "A glass of refreshing Lemon Soda. So sour!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT

/datum/reagent/drink/soda/apple_soda
	name = REAGENT_APPLESODA
	id = REAGENT_ID_APPLESODA
	description = "Soda made using fresh apples."
	taste_description = "crisp juiciness"
	reagent_state = LIQUID
	color = "#c73737"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_APPLESODA
	glass_desc = "A glass of refreshing Apple Soda. Crisp!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT


/datum/reagent/drink/soda/straw_soda
	name = REAGENT_STRAWSODA
	id = REAGENT_ID_STRAWSODA
	description = "Soda made using sweet berries."
	taste_description = "oddly bland"
	reagent_state = LIQUID
	color = "#ffa3a3"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_STRAWSODA
	glass_desc = "A glass of refreshing Strawberry Soda"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT

/datum/reagent/drink/soda/orangesoda
	name = REAGENT_ORANGESODA
	id = REAGENT_ID_ORANGESODA
	description = "Soda made using fresh picked oranges."
	taste_description = "sweet and citrusy"
	reagent_state = LIQUID
	color = "#ff992c"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_ORANGESODA
	glass_desc = "A glass of refreshing Orange Soda. Delicious!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT

/datum/reagent/drink/soda/grapesoda
	name = REAGENT_GRAPESODA
	id = REAGENT_ID_GRAPESODA
	description = "Soda made of carbonated grapejuice."
	taste_description = "tangy goodness"
	reagent_state = LIQUID
	color = "#9862d2"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_GRAPESODA
	glass_desc = "A glass of refreshing Grape Soda. Tangy!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT

/datum/reagent/drink/soda/sarsaparilla
	name = REAGENT_SARSAPARILLA
	id = REAGENT_ID_SARSAPARILLA
	description = "Soda made from genetically modified Mexican sarsaparilla plants."
	taste_description = "licorice and caramel"
	reagent_state = LIQUID
	color = "#e1bb59"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_SARSAPARILLA
	glass_desc = "A glass of refreshing Sarsaparilla. Delicious!"
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/pork_soda
	name = REAGENT_PORKSODA
	id = REAGENT_ID_PORKSODA
	description = "Soda made using pork like flavoring."
	taste_description = "sugar coated bacon"
	reagent_state = LIQUID
	color = "ff8080"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_PORKSODA
	glass_desc = "A glass of Bacon Soda, very odd..."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/spacemountainwind
	name = REAGENT_SPACEMOUNTAINWIND
	id = REAGENT_ID_SPACEMOUNTAINWIND
	description = "Blows right through you like a space wind."
	taste_description = "sweet citrus soda"
	nutriment_factor = 1.5
	color = "#102000"
	adj_drowsy = -7
	adj_sleepy = -1
	adj_temp = -5

	glass_name = "Space Mountain Wind"
	glass_desc = "Space Mountain Wind. As you know, there are no mountains in space, only wind."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Citrus, and caffeination

/datum/reagent/drink/soda/dr_gibb
	name = REAGENT_DRGIBB
	id = REAGENT_ID_DRGIBB
	description = "A delicious blend of 42 different flavors."
	taste_description = "cherry soda"
	nutriment_factor = 3
	color = "#102000"
	adj_drowsy = -6
	adj_temp = -5

	glass_name = REAGENT_DRGIBB
	glass_desc = "Dr. Gibb. Not as dangerous as the name might imply."
	allergen_type = ALLERGEN_STIMULANT

/datum/reagent/drink/soda/space_up
	name = REAGENT_SPACEUP
	id = REAGENT_ID_SPACEUP
	description = "Tastes like a hull breach in your mouth."
	taste_description = "citrus soda"
	nutriment_factor = 1.5
	color = "#202800"
	adj_temp = -8

	glass_name = "Space-up"
	glass_desc = "Space-up. It helps keep your cool."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT

/datum/reagent/drink/soda/lemon_lime
	name = REAGENT_LEMONLIME
	id = REAGENT_ID_LEMONLIME
	description = "A tangy substance made of 0.5% natural citrus!"
	taste_description = "tangy lime and lemon soda"
	nutriment_factor = 1.5
	color = "#878F00"
	adj_temp = -8

	glass_name = "lemon lime soda"
	glass_desc = "A tangy substance made of 0.5% natural citrus!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with lemon and lime juice

/datum/reagent/drink/soda/gingerale
	name = REAGENT_GINGERALE
	id = REAGENT_ID_GINGERALE
	description = "The original."
	taste_description = "somewhat tangy ginger ale"
	nutriment_factor = 1.5
	color = "#edcf8f"
	adj_temp = -8

	glass_name = "ginger ale"
	glass_desc = "The original, refreshing not-actually-ale."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/root_beer
	name = REAGENT_ROOTBEER
	id = REAGENT_ID_ROOTBEER
	color = "#211100"
	adj_drowsy = -6
	taste_description = "sassafras and anise soda"

	glass_name = "glass of R&D Root Beer"
	glass_desc = "A glass of bubbly R&D Root Beer."

/datum/reagent/drink/dr_gibb_diet
	name = REAGENT_DIETDRGIBB
	id = REAGENT_ID_DIETDRGIBB
	color = "#102000"
	taste_description = "chemically sweetened cherry soda"

	glass_name = "glass of Diet Dr. Gibb"
	glass_desc = "Regular Dr.Gibb is probably healthier than this cocktail of artificial flavors."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/shirley_temple
	name = REAGENT_SHIRLEYTEMPLE
	id =  REAGENT_ID_SHIRLEYTEMPLE
	description = "A sweet concotion hated even by its namesake."
	taste_description = "sweet ginger ale"
	color = "#EF304F"
	adj_temp = -8

	glass_name = "shirley temple"
	glass_desc = "A sweet concotion hated even by its namesake."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/roy_rogers
	name = REAGENT_ROYROGERS
	id = REAGENT_ID_ROYROGERS
	description = "I'm a cowboy, on a steel horse I ride."
	taste_description = "cola and fruit"
	nutriment_factor = 1.5
	color = "#4F1811"
	adj_temp = -8

	glass_name = "roy rogers"
	glass_desc = "I'm a cowboy, on a steel horse I ride"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with lemon lime and cola

/datum/reagent/drink/collins_mix
	name = REAGENT_COLLINSMIX
	id = REAGENT_ID_COLLINSMIX
	description = "Best hope it isn't a hoax."
	taste_description = "gin and lemonade"
	nutriment_factor = 1.5
	color = "#D7D0B3"
	adj_temp = -8

	glass_name = "collins mix"
	glass_desc = "Best hope it isn't a hoax."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with lemon lime

/datum/reagent/drink/arnold_palmer
	name = REAGENT_ARNOLDPALMER
	id = REAGENT_ID_ARNOLDPALMER
	description = "Tastes just like the old man."
	taste_description = "lemon and sweet tea"
	nutriment_factor = 1.5
	color = "#AF5517"
	adj_temp = -8

	glass_name = "arnold palmer"
	glass_desc = "Tastes just like the old man."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT | ALLERGEN_STIMULANT //Made with lemonade and tea

/datum/reagent/drink/doctor_delight
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.4,
		TREAT_BURN_CARE = 0.4,
		TREAT_OXYGENATION = 0.2,
		TREAT_ANTITOXIN = 0.3,
	)
	name = REAGENT_DOCTORSDELIGHT
	id = REAGENT_ID_DOCTORSDELIGHT
	description = "A gulp a day keeps the MediBot away. That's probably for the best."
	taste_description = "homely fruit smoothie"
	reagent_state = LIQUID
	color = "#FF8CFF"
	nutrition = 1

	glass_name = REAGENT_DOCTORSDELIGHT
	glass_desc = "A healthy mixture of juices, guaranteed to keep you healthy until the next toolboxing takes place."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY //Made from several fruit juices, and cream.
	medallergen_type = MEDALLERGEN_TRICORD // this too!

/datum/reagent/drink/doctor_delight/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	// Its healing is the treatment_tags profile.
	M.status_adjust(STAT_DIZZY, -15)
	if(M.has_status(STAT_CONFUSED))
		M.status_at_least(STAT_CONFUSED, -5)

/datum/reagent/drink/dry_ramen
	name = REAGENT_DRYRAMEN
	id = REAGENT_ID_DRYRAMEN
	description = "Space age food, since August 25, 1958. Contains dried noodles, vegetables, boil in water before serving."
	taste_description = "dry cheap noodles"
	reagent_state = SOLID
	nutrition = 1
	color = "#302000"

/datum/reagent/drink/hot_ramen
	name = REAGENT_HOTRAMEN
	id = REAGENT_ID_HOTRAMEN
	description = "The noodles are boiled, the flavors are artificial, just like being back in school."
	taste_description = "noodles and salt"
	reagent_state = LIQUID
	color = "#302000"
	nutrition = 5
	adj_temp = 5

/datum/reagent/drink/hell_ramen
	name = REAGENT_HELLRAMEN
	id = REAGENT_ID_HELLRAMEN
	description = "The noodles are boiled, the flavors are artificial, just like being back in school."
	taste_description = "noodles and spice"
	taste_mult = 1.7
	reagent_state = LIQUID
	color = "#302000"
	nutrition = 5

/datum/reagent/drink/hell_ramen/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	handle_spicy(M, alien, removed)

/datum/reagent/drink/sweetsundaeramen
	name = REAGENT_DESSERTRAMEN
	id = REAGENT_ID_DESSERTRAMEN
	description = "How many things can you add to a cup of ramen before it begins to question its existance?"
	taste_description = "unbearable sweetness"
	color = "#4444FF"
	nutrition = 5

	glass_name = "Sweet Sundae Ramen"
	glass_desc = "How many things can you add to a cup of ramen before it begins to question its existance?"

/datum/reagent/drink/ice
	name = REAGENT_ICE
	id = REAGENT_ID_ICE
	description = "Frozen water, your dentist wouldn't like you chewing this."
	taste_description = "ice"
	reagent_state = SOLID
	color = "#619494"
	adj_temp = -5

	glass_name = REAGENT_ID_ICE
	glass_desc = "Generally, you're supposed to put something else in there too..."
	glass_icon = DRINK_ICON_NOISY

/datum/reagent/drink/ice
	species_chill = 1 // nonzero enables the chill; the rate itself is random (species_chill_rate())

/datum/reagent/drink/ice/species_chill_rate()
	return rand(1, 3)

/datum/reagent/drink/ice/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/ice/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/nothing
	name = REAGENT_NOTHING
	id = REAGENT_ID_NOTHING
	description = "Absolutely nothing."
	taste_description = REAGENT_ID_NOTHING

	glass_name = REAGENT_ID_NOTHING
	glass_desc = "Absolutely nothing."

/datum/reagent/drink/dreamcream
	name = REAGENT_DREAMCREAM
	id = REAGENT_ID_DREAMCREAM
	description = "A smoothy, silky mix of honey and dairy."
	taste_description = "sweet, soothing dairy"
	nutriment_factor = 5
	color = "#fcfcc9" // rgb(252, 252, 201)

	glass_name = REAGENT_DREAMCREAM
	glass_desc = "A smoothy, silky mix of honey and dairy."
	allergen_type = ALLERGEN_DAIRY //Made using dairy

/datum/reagent/drink/soda/vilelemon
	name = REAGENT_VILELEMON
	id = REAGENT_ID_VILELEMON
	description = "A fizzy, sour lemonade mix."
	taste_description = "fizzy, sour lemon"
	nutriment_factor = 1.5
	color = "#c6c603" // rgb(198, 198, 3)

	glass_name = REAGENT_VILELEMON
	glass_desc = "A sour, fizzy drink with lemonade and lemonlime."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Made from lemonade and mtn wind(caffeine)

/datum/reagent/drink/entdraught
	name = REAGENT_ENTDRAUGHT
	id = REAGENT_ID_ENTDRAUGHT
	description = "A natural, earthy combination of all things peaceful."
	taste_description = "fresh rain and sweet memories"
	nutriment_factor = 5
	color = "#3a6617" // rgb(58, 102, 23)

	glass_name = REAGENT_ENTDRAUGHT
	glass_desc = "You can almost smell the tranquility emanating from this."

/datum/reagent/drink/love_potion
	name = REAGENT_LOVEPOTION
	id = REAGENT_ID_LOVEPOTION
	description = "Creamy strawberries and sugar, simple and sweet."
	taste_description = "strawberries and cream"
	color = "#fc8a8a" // rgb(252, 138, 138)

	glass_name = REAGENT_LOVEPOTION
	glass_desc = "Love me tender, love me sweet."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY //Made from cream(dairy) and berryjuice(fruit)

/datum/reagent/drink/oilslick
	name = REAGENT_OILSLICK
	id = REAGENT_ID_OILSLICK
	description = "A viscous, but sweet, ooze."
	taste_description = "honey"
	nutriment_factor = 15
	color = "#FDF5E6" // rgb(253,245,230)
	water_based = FALSE

	glass_name = REAGENT_OILSLICK
	glass_desc = "A concoction that should probably be in an engine, rather than your stomach."
	glass_icon = DRINK_ICON_NOISY
	allergen_type = ALLERGEN_VEGETABLE //Made from corn oil

/datum/reagent/drink/slimeslammer
	name = REAGENT_SLIMESLAMMER
	id = REAGENT_ID_SLIMESLAMMER
	description = "A viscous, but savory, ooze."
	taste_description = "peanuts`n`slime"
	nutriment_factor = 20
	color = "#93604D"
	water_based = FALSE

	glass_name = "Slick Slime Slammer"
	glass_desc = "A concoction that should probably be in an engine, rather than your stomach. Still."
	glass_icon = DRINK_ICON_NOISY
	allergen_type = ALLERGEN_VEGETABLE|ALLERGEN_SEEDS //Made from corn oil and peanutbutter

/datum/reagent/drink/eggnog
	name = REAGENT_EGGNOG
	id = REAGENT_ID_EGGNOG
	description = "A creamy, rich beverage made out of whisked eggs, milk and sugar, for when you feel like celebrating the winter holidays."
	taste_description = "thick cream and vanilla"
	color = "#fff3c1" // rgb(255, 243, 193)

	glass_name = REAGENT_EGGNOG
	glass_desc = "You can't egg-nore the holiday cheer all around you"
	allergen_type = ALLERGEN_DAIRY|ALLERGEN_EGGS //Eggnog is made with dairy and eggs.

/datum/reagent/drink/nuclearwaste
	name = REAGENT_NUCLEARWASTE
	id = REAGENT_ID_NUCLEARWASTE
	description = "A viscous, glowing slurry."
	taste_description = "sour honey drops"
	nutriment_factor = 15
	color = "#7FFF00" // rgb(127,255,0)
	water_based = FALSE

	glass_name = REAGENT_NUCLEARWASTE
	glass_desc = "Sadly, no super powers."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_VEGETABLE //Made from oilslick, so has the same allergens.

/datum/reagent/drink/nuclearwaste/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	M.bloodstr.add_reagent(REAGENT_ID_RADIUM, 0.3)

/datum/reagent/drink/nuclearwaste/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	M.ingested.add_reagent(REAGENT_ID_RADIUM, 0.25)

/datum/reagent/drink/sodaoil //Mixed with normal drinks to make a 'potable' version for Prometheans if mixed 1-1. Dilution is key.
	name = REAGENT_SODAOIL
	id = REAGENT_ID_SODAOIL
	description = "A thick, bubbling soda."
	taste_description = "chewy water"
	nutriment_factor = 10
	color = "#F0FFF0" // rgb(245,255,250)
	water_based = FALSE

	glass_name = REAGENT_SODAOIL
	glass_desc = "A pitiful sludge that looks vaguely like a soda.. if you look at it a certain way."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_VEGETABLE //Made from corn oil

/datum/reagent/drink/sodaoil/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(M.bloodstr) // If, for some reason, they are injected, dilute them as well.
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/drink))
				var/datum/reagent/drink/D = R
				if(D.water_based)
					// Conditional on other drinks being present: mends directly.
					M.mend(TREAT_ANTITOXIN, removed * 3)

/datum/reagent/drink/sodaoil/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(M.ingested) // Find how many drinks are causing tox, and negate them.
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/drink))
				var/datum/reagent/drink/D = R
				if(D.water_based)
					// Conditional on other drinks being present: mends directly.
					M.mend(TREAT_ANTITOXIN, removed * 2)

/datum/reagent/drink/virgin_mojito
	name = REAGENT_VIRGINMOJITO
	id = REAGENT_ID_VIRGINMOJITO
	description = "Mint, bubbly water, and citrus, made for sailing."
	taste_description = "mint and lime"
	color = "#FFF7B3"

	glass_name = REAGENT_ID_MOJITO
	glass_desc = "Mint, bubbly water, and citrus, made for sailing."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with lime juice

/datum/reagent/drink/sexonthebeach
	name = REAGENT_VIRGINSEXONTHEBEACH
	id = REAGENT_ID_VIRGINSEXONTHEBEACH
	description = "A secret combination of orange juice and pomegranate."
	taste_description = "60% orange juice, 40% pomegranate"
	color = "#7051E3"

	glass_name = "sex on the beach"
	glass_desc = "A secret combination of orange juice and pomegranate."
	allergen_type = ALLERGEN_FRUIT //Made with orange juice

/datum/reagent/drink/driverspunch
	name = REAGENT_DRIVERSPUNCH
	id = REAGENT_ID_DRIVERSPUNCH
	description = "A fruity punch!"
	taste_description = "sharp, sour apples"
	color = "#D2BA6E"

	glass_name = "driver`s punch"
	glass_desc = "A fruity punch!"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with appleade and orange juice

/datum/reagent/drink/mintapplesparkle
	name = REAGENT_MINTAPPLESPARKLE
	id = REAGENT_ID_MINTAPPLESPARKLE
	description = "Delicious appleade with a touch of mint."
	taste_description = "minty apples"
	color = "#FDDA98"

	glass_name = "mint apple sparkle"
	glass_desc = "Delicious appleade with a touch of mint."
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with appleade

/datum/reagent/drink/berrycordial
	name = REAGENT_BERRYCORDIAL
	id = REAGENT_ID_BERRYCORDIAL
	description = "How <font face='comic sans ms'>berry cordial</font> of you."
	taste_description = "sweet chivalry"
	color = "#D26EB8"

	glass_name = "berry cordial"
	glass_desc = "How <font face='comic sans ms'>berry cordial</font> of you."
	glass_icon = DRINK_ICON_NOISY
	allergen_type = ALLERGEN_FRUIT //Made with berry and lemonjuice

/datum/reagent/drink/tropicalfizz
	name = REAGENT_TROPICALFIZZ
	id = REAGENT_ID_TROPICALFIZZ
	description = "One sip and you're in the bahamas."
	taste_description = "tropical"
	color = "#69375C"

	glass_name = "tropical fizz"
	glass_desc = "One sip and you're in the bahamas."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //Made with several fruit juices

/datum/reagent/drink/fauxfizz
	name = REAGENT_FAUXFIZZ
	id = REAGENT_ID_FAUXFIZZ
	description = "One sip and you're in the bahamas... maybe."
	taste_description = "slightly tropical"
	nutriment_factor = 4
	color = "#69375C"

	glass_name = "tropical fizz"
	glass_desc = "One sip and you're in the bahamas... maybe."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_FRUIT //made with several fruit juices

/datum/reagent/drink/syrup
	name = REAGENT_SYRUP
	id = REAGENT_ID_SYRUP
	description = "A generic, sugary syrup."
	taste_description = "sweetness"
	color = "#fffbe8"
	cup_prefix = "extra sweet"

	glass_name = REAGENT_ID_SYRUP
	glass_desc = "That is just way too much syrup to drink on its own."
	allergen_type = ALLERGEN_SUGARS

	overdose = REAGENTS_OVERDOSE *1.5

/datum/reagent/drink/syrup/overdose(mob/living/carbon/M, alien)
	if(inert_for(M))
		return
	M.status_adjust(STAT_DIZZY, 1)

/datum/reagent/drink/syrup/pumpkin
	name = REAGENT_SYRUPPUMPKIN
	id = REAGENT_ID_SYRUPPUMPKIN
	description = "A sugary syrup that tastes of pumpkin spice."
	taste_description = "pumpkin spice"
	color = "#e0b439"
	cup_prefix = "pumpkin spice"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/caramel
	name = REAGENT_SYRUPCARAMEL
	id = REAGENT_ID_SYRUPCARAMEL
	description = "A sugary syrup that tastes of caramel."
	taste_description = "caramel"
	color = "#b47921"
	cup_prefix = "caramel"

/datum/reagent/drink/syrup/scaramel
	name = REAGENT_SYRUPSALTEDCARAMEL
	id = REAGENT_ID_SYRUPSALTEDCARAMEL
	description = "A sugary syrup that tastes of salted caramel."
	taste_description = "salty caramel"
	color = "#9f6714"
	cup_prefix = "salted caramel"

/datum/reagent/drink/syrup/irish
	name = REAGENT_SYRUPIRISH
	id = REAGENT_ID_SYRUPIRISH
	description = "A sugary syrup that tastes of a light, sweet cream."
	taste_description = "creaminess"
	color = "#ead3b0"
	cup_prefix = "irish"

/datum/reagent/drink/syrup/almond
	name = REAGENT_SYRUPALMOND
	id = REAGENT_ID_SYRUPALMOND
	description = "A sugary syrup that tastes of almonds."
	taste_description = "almonds"
	color = "#ffb64a"
	cup_prefix = "almond"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_SEEDS

/datum/reagent/drink/syrup/cinnamon
	name = REAGENT_SYRUPCINNAMON
	id = REAGENT_ID_SYRUPCINNAMON
	description = "A sugary syrup that tastes of cinnamon."
	taste_description = "cinnamon"
	color = "#ec612a"
	cup_prefix = "cinnamon"

/datum/reagent/drink/syrup/pistachio
	name = REAGENT_SYRUPPISTACHIO
	id = REAGENT_ID_SYRUPPISTACHIO
	description = "A sugary syrup that tastes of pistachio."
	taste_description = "pistachio"
	color = "#c9eb59"
	cup_prefix = "pistachio"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_SEEDS

/datum/reagent/drink/syrup/vanilla
	name = REAGENT_SYRUPVANILLA
	id = REAGENT_ID_SYRUPVANILLA
	description = "A sugary syrup that tastes of vanilla."
	taste_description = "vanilla"
	color = "#eaebd1"
	cup_prefix = REAGENT_ID_VANILLA

/datum/reagent/drink/syrup/toffee
	name = REAGENT_SYRUPTOFFEE
	id = REAGENT_ID_SYRUPTOFFEE
	description = "A sugary syrup that tastes of toffee."
	taste_description = "toffee"
	color = "#aa7143"
	cup_prefix = "toffee"

/datum/reagent/drink/syrup/cherry
	name = REAGENT_SYRUPCHERRY
	id = REAGENT_ID_SYRUPCHERRY
	description = "A sugary syrup that tastes of cherries."
	taste_description = "cherries"
	color = "#ff0000"
	cup_prefix = "cherry"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/butterscotch
	name = REAGENT_SYRUPBUTTERSCOTCH
	id = REAGENT_ID_SYRUPBUTTERSCOTCH
	description = "A sugary syrup that tastes of butterscotch."
	taste_description = "butterscotch"
	color = "#e6924e"
	cup_prefix = "butterscotch"

/datum/reagent/drink/syrup/chocolate
	name = REAGENT_SYRUPCHOCOLATE
	id = REAGENT_ID_SYRUPCHOCOLATE
	description = "A sugary syrup that tastes of chocolate."
	taste_description = REAGENT_ID_CHOCOLATE
	color = "#873600"
	cup_prefix = REAGENT_ID_CHOCOLATE

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_CHOCOLATE

/datum/reagent/drink/syrup/wchocolate
	name = REAGENT_SYRUPWHITECHOCOLATE
	id = REAGENT_ID_SYRUPWHITECHOCOLATE
	description = "A sugary syrup that tastes of white chocolate."
	taste_description = "white chocolate"
	color = "#c4c6a5"
	cup_prefix = "white chocolate"

	allergen_type = ALLERGEN_SUGARS //|ALLERGEN_CHOCOLATE //commenting this out and leaving this comment to inform that WHITE CHOCOLATE IS NOT CHOCOLATE!!!!

/datum/reagent/drink/syrup/strawberry
	name = REAGENT_SYRUPSTRAWBERRY
	id = REAGENT_ID_SYRUPSTRAWBERRY
	description = "A sugary syrup that tastes of strawberries."
	taste_description = "strawberries"
	color = "#ff2244"
	cup_prefix = "strawberry"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/coconut
	name = REAGENT_SYRUPCOCONUT
	id = REAGENT_ID_SYRUPCOCONUT
	description = "A sugary syrup that tastes of coconut."
	taste_description = "coconut"
	color = "#ffffff"
	cup_prefix = "coconut"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/ginger
	name = REAGENT_SYRUPGINGER
	id = REAGENT_ID_SYRUPGINGER
	description = "A sugary syrup that tastes of ginger."
	taste_description = "ginger"
	color = "#d09740"
	cup_prefix = "ginger"

/datum/reagent/drink/syrup/gingerbread
	name = REAGENT_SYRUPGINGERBREAD
	id = REAGENT_ID_SYRUPGINGERBREAD
	description = "A sugary syrup that tastes of gingerbread."
	taste_description = "gingerbread"
	color = "#b6790f"
	cup_prefix = "gingerbread"

/datum/reagent/drink/syrup/peppermint
	name = REAGENT_SYRUPPEPPERMINT
	id = REAGENT_ID_SYRUPPEPPERMINT
	description = "A sugary syrup that tastes of peppermint."
	taste_description = "peppermint"
	color = "#9ce06e"
	cup_prefix = "peppermint"

/datum/reagent/drink/syrup/birthday_cake
	name = REAGENT_SYRUPBIRTHDAY
	id = REAGENT_ID_SYRUPBIRTHDAY
	description = "A sugary syrup that tastes of an overload of sweetness."
	taste_description = "far too much sugar"
	color = "#ff00e6"
	cup_prefix = "birthday cake"

