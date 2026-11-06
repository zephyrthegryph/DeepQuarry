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

/datum/reagent/drink/sweetsundaeramen
	name = REAGENT_DESSERTRAMEN
	id = REAGENT_ID_DESSERTRAMEN
	description = "How many things can you add to a cup of ramen before it begins to question its existance?"
	taste_description = "unbearable sweetness"
	color = "#4444FF"
	nutrition = 5

	glass_name = "Sweet Sundae Ramen"
	glass_desc = "How many things can you add to a cup of ramen before it begins to question its existance?"

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
