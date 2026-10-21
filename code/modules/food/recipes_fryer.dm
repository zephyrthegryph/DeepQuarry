/transformation/kitchen/fries
CAPABILITIES(/transformation/kitchen/fries)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawsticks, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fries, 1)),
		cooks_in = FRYER))

/transformation/kitchen/cheesyfries
CAPABILITIES(/transformation/kitchen/cheesyfries)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/fries, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesyfries, 1)),
		cooks_in = FRYER))

/transformation/kitchen/jpoppers
CAPABILITIES(/transformation/kitchen/jpoppers)
	configure(transformation(takes = list(fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jalapeno_poppers, 2)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter))

// Simplify end product
/transformation/kitchen/risottoballs
CAPABILITIES(/transformation/kitchen/risottoballs)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/risotto, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/risottoballs, 2)),
		cooks_in = FRYER,
		mix = RECIPE_REAGENT_REPLACE,
		coating = /datum/reagent/nutriment/coating/batter))

/transformation/kitchen/bellefritter
CAPABILITIES(/transformation/kitchen/bellefritter)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/frostbelle, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bellefritter, 2)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter))

/transformation/kitchen/onionrings
CAPABILITIES(/transformation/kitchen/onionrings)
	configure(transformation(takes = list(fruit_term(PLANT_ONION, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/onionrings, 2)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter))

//Meaty Recipes
//====================
/transformation/kitchen/cubancarp
CAPABILITIES(/transformation/kitchen/cubancarp)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cubancarp, 1)),
		cooks_in = FRYER))

/transformation/kitchen/batteredsausage
CAPABILITIES(/transformation/kitchen/batteredsausage)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sausage, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sausage/battered, 1)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter))


/transformation/kitchen/katsu
CAPABILITIES(/transformation/kitchen/katsu)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat/chicken, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chickenkatsu, 1)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/beerbatter))


/transformation/kitchen/pizzacrunch_1
CAPABILITIES(/transformation/kitchen/pizzacrunch_1)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/crunch, 1)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter))

//Alternate pizza crunch recipe for combination pizzas made in oven
/transformation/kitchen/pizzacrunch_2
CAPABILITIES(/transformation/kitchen/pizzacrunch_2)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/variable/pizza, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/crunch, 1)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter,
		wiki = WIKI_SPOILER))

// Simplify end product
/transformation/kitchen/friedmushroom
CAPABILITIES(/transformation/kitchen/friedmushroom)
	configure(transformation(takes = list(fruit_term(PLANT_PLUMPHELMET, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/friedmushroom, 1)),
		cooks_in = FRYER,
		mix = RECIPE_REAGENT_REPLACE,
		coating = /datum/reagent/nutriment/coating/beerbatter))

/transformation/kitchen/fishfingers
CAPABILITIES(/transformation/kitchen/fishfingers)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fishfingers, 1)),
		mix = RECIPE_REAGENT_REPLACE,
		coating = /datum/reagent/nutriment/coating/batter))

/transformation/kitchen/corn_dog
CAPABILITIES(/transformation/kitchen/corn_dog)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sausage, 1),
			fruit_term(PLANT_CORN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/corn_dog, 1)),
		cooks_in = FRYER,
		coating = /datum/reagent/nutriment/coating/batter))

/transformation/kitchen/sweet_and_sour
CAPABILITIES(/transformation/kitchen/sweet_and_sour)
	configure(transformation(takes = list(reagent(REAGENT_ID_SOYSAUCE, 5),
			reagent(REAGENT_ID_BATTER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sweet_and_sour, 1)),
		cooks_in = FRYER))

//Sweet Recipes.
//==================
// All donuts were given reagents of 5 to equal old recipes and make for faster cook times.
/transformation/kitchen/jellydonut
CAPABILITIES(/transformation/kitchen/jellydonut)
	configure(transformation(takes = list(reagent(REAGENT_ID_BERRYJUICE, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donut/plain/jelly, 2)),
		cooks_in = FRYER))

/transformation/kitchen/jellydonut/poisonberry
CAPABILITIES(/transformation/kitchen/jellydonut/poisonberry)
	configure(transformation(takes = list(reagent(REAGENT_ID_POISONBERRYJUICE, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donut/plain/jelly/poisonberry, 2)),
		wiki = WIKI_SPOILER))

// Subtypes of jellydonut, appliance inheritance applies.
/transformation/kitchen/jellydonut/slime
CAPABILITIES(/transformation/kitchen/jellydonut/slime)
	configure(transformation(takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donut/plain/jelly/slimejelly, 2))))

// Subtypes of jellydonut, appliance inheritance applies.
/transformation/kitchen/jellydonut/cherry
CAPABILITIES(/transformation/kitchen/jellydonut/cherry)
	configure(transformation(takes = list(reagent(REAGENT_ID_CHERRYJELLY, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donut/plain/jelly/cherryjelly, 2))))

/transformation/kitchen/donut
CAPABILITIES(/transformation/kitchen/donut)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donut/plain, 2)),
		cooks_in = FRYER))

// This creates its own reagents
/transformation/kitchen/chaosdonut
CAPABILITIES(/transformation/kitchen/chaosdonut)
	configure(transformation(takes = list(reagent(REAGENT_ID_FROSTOIL, 10),
			reagent(REAGENT_ID_CAPSAICIN, 10),
			reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donut/chaos, 2)),
		cooks_in = FRYER,
		mix = RECIPE_REAGENT_REPLACE,
		wiki = WIKI_SPOILER))

/transformation/kitchen/funnelcake
CAPABILITIES(/transformation/kitchen/funnelcake)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_BATTER, 10)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/funnelcake, 2)),
		cooks_in = FRYER))

// Simplify end product
/transformation/kitchen/pisanggoreng
CAPABILITIES(/transformation/kitchen/pisanggoreng)
	configure(transformation(takes = list(fruit_term(PLANT_BANANA, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/pisanggoreng, 1)),
		cooks_in = FRYER,
		mix = RECIPE_REAGENT_REPLACE,
		coating = /datum/reagent/nutriment/coating/batter))

//CHOMP removal start
/*/transformation/kitchen/generalschicken
*	appliance = FRYER
	reagents = list(REAGENT_ID_CAPSAICIN = 2, REAGENT_ID_SUGAR = 2, REAGENT_ID_BATTER = 10)
*	items = list(
*		/obj/item/reagent_containers/food/snacks/meat,
*		/obj/item/reagent_containers/food/snacks/meat
*	)
*	result = /obj/item/reagent_containers/food/snacks/generalschicken
*
/transformation/kitchen/chickenwings
*	appliance = FRYER
	reagents = list(REAGENT_ID_CAPSAICIN = 5, REAGENT_ID_BATTER = 10)
*	items = list(
*		/obj/item/reagent_containers/food/snacks/meat,
*		/obj/item/reagent_containers/food/snacks/meat,
*		/obj/item/reagent_containers/food/snacks/meat,
*		/obj/item/reagent_containers/food/snacks/meat
*	)
*	result = /obj/item/storage/box/wings //This is kinda like the donut box.
Chomp remove end */

/transformation/kitchen/churro
CAPABILITIES(/transformation/kitchen/churro)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/churro, 1)),
		cooks_in = FRYER))


/transformation/kitchen/generalschicken
CAPABILITIES(/transformation/kitchen/generalschicken)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAPSAICIN, 2),
			reagent(REAGENT_ID_SUGAR, 2),
			reagent(REAGENT_ID_BATTER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/generalschicken, 1)),
		cooks_in = FRYER))

// This is kinda like the donut box.
/transformation/kitchen/chickenwings
CAPABILITIES(/transformation/kitchen/chickenwings)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAPSAICIN, 5),
			reagent(REAGENT_ID_BATTER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/storage/box/wings, 1)),
		cooks_in = FRYER))

/transformation/kitchen/locust
CAPABILITIES(/transformation/kitchen/locust)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/locust, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/locust_cooked, 1)),
		cooks_in = FRYER))
