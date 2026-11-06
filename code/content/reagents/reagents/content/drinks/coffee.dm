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
