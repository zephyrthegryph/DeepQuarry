/transformation/kitchen/ovenfries
CAPABILITIES(/transformation/kitchen/ovenfries)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawsticks, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ovenfries, 1)),
		cooks_in = OVEN))

//Roasts
//---------------

// It dissolves the carapace. Still poisonous, though.
// No eating polyacid
/transformation/kitchen/dionaroast
CAPABILITIES(/transformation/kitchen/dionaroast)
	configure(transformation(takes = list(reagent(REAGENT_ID_PACID, 5),
			item_term(/obj/item/holder/diona, 1),
			fruit_term(PLANT_APPLE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/dionaroast, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/monkeysdelight
CAPABILITIES(/transformation/kitchen/monkeysdelight)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_FLOUR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/monkeycube, 1),
			fruit_term(PLANT_BANANA, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeysdelight, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/ribplate
CAPABILITIES(/transformation/kitchen/ribplate)
	configure(transformation(takes = list(reagent(REAGENT_ID_HONEY, 5),
			reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ribplate, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/* OLD RECIPE
/transformation/kitchen/turkey
	appliance = OVEN
	reagents = list(REAGENT_ID_SODIUMCHLORIDE = 1, REAGENT_ID_BLACKPEPPER = 1)
	items = list(
		/obj/item/reagent_containers/food/snacks/meat/chicken,
		/obj/item/reagent_containers/food/snacks/stuffing
		)
	result = /obj/item/reagent_containers/food/snacks/sliceable/turkey
*/

/transformation/kitchen/turkey
CAPABILITIES(/transformation/kitchen/turkey)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawturkey, 1),
			item_term(/obj/item/reagent_containers/food/snacks/stuffing, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/turkey, 1)),
		cooks_in = OVEN))

/transformation/kitchen/tofurkey
CAPABILITIES(/transformation/kitchen/tofurkey)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/stuffing, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tofurkey, 1)),
		cooks_in = OVEN))

/transformation/kitchen/zestfish
CAPABILITIES(/transformation/kitchen/zestfish)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 3),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_LEMON, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/zestfish, 1)),
		cooks_in = OVEN))

// secret if you know!
/transformation/kitchen/limezestfish
CAPABILITIES(/transformation/kitchen/limezestfish)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 3),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_LIME, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/zestfish, 1)),
		cooks_in = OVEN,
		wiki = WIKI_SPOILER))


//Predesigned breads
//================================
/transformation/kitchen/bread
CAPABILITIES(/transformation/kitchen/bread)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_YEAST, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/bread, 1)),
		cooks_in = OVEN))

/transformation/kitchen/baguette
CAPABILITIES(/transformation/kitchen/baguette)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_YEAST, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/baguette, 1)),
		cooks_in = OVEN))


/transformation/kitchen/tofubread
CAPABILITIES(/transformation/kitchen/tofubread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/tofubread, 1)),
		cooks_in = OVEN))


/transformation/kitchen/creamcheesebread
CAPABILITIES(/transformation/kitchen/creamcheesebread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/creamcheesebread, 1)),
		cooks_in = OVEN))

/transformation/kitchen/flatbread
CAPABILITIES(/transformation/kitchen/flatbread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/flatbread, 1)),
		cooks_in = OVEN))

/transformation/kitchen/tortilla
CAPABILITIES(/transformation/kitchen/tortilla)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 3)),
		cooks_in = OVEN))

/transformation/kitchen/meatbread
CAPABILITIES(/transformation/kitchen/meatbread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/meatbread, 1)),
		cooks_in = OVEN))

// Synthflesh secret
/transformation/kitchen/syntibread
CAPABILITIES(/transformation/kitchen/syntibread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/meatbread, 1)),
		cooks_in = OVEN,
		wiki = WIKI_SPOILER))

/transformation/kitchen/xenomeatbread
CAPABILITIES(/transformation/kitchen/xenomeatbread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/xenomeatbread, 1)),
		cooks_in = OVEN))

/transformation/kitchen/bananabread
CAPABILITIES(/transformation/kitchen/bananabread)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 15),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_BANANA, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/bananabread, 1)),
		cooks_in = OVEN))


/transformation/kitchen/bun
CAPABILITIES(/transformation/kitchen/bun)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 3)),
		cooks_in = OVEN))

//Predesigned pies
//=======================

/transformation/kitchen/meatpie
CAPABILITIES(/transformation/kitchen/meatpie)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatpie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/tofupie
CAPABILITIES(/transformation/kitchen/tofupie)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tofupie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/xemeatpie
CAPABILITIES(/transformation/kitchen/xemeatpie)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/xemeatpie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/pie
CAPABILITIES(/transformation/kitchen/pie)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_BANANA, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/pie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cherrypie
CAPABILITIES(/transformation/kitchen/cherrypie)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_CHERRY, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cherrypie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/amanita_pie
CAPABILITIES(/transformation/kitchen/amanita_pie)
	configure(transformation(takes = list(reagent(REAGENT_ID_AMATOXIN, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/amanita_pie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/plump_pie
CAPABILITIES(/transformation/kitchen/plump_pie)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_PLUMPHELMET, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/plump_pie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/applepie
CAPABILITIES(/transformation/kitchen/applepie)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_APPLE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/applepie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/pumpkinpie
CAPABILITIES(/transformation/kitchen/pumpkinpie)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_PUMPKIN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pumpkinpie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/appletart
CAPABILITIES(/transformation/kitchen/appletart)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_GOLDAPPLE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/appletart, 2)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// No raw egg in finished product, protein after cooking causes magic meatballs otherwise
/transformation/kitchen/keylimepie
CAPABILITIES(/transformation/kitchen/keylimepie)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_EGG, 3),
			reagent(REAGENT_ID_FLOUR, 10),
			fruit_term(PLANT_LIME, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/keylimepie, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// No raw egg in finished product, protein after cooking causes magic meatballs otherwise
/transformation/kitchen/quiche
CAPABILITIES(/transformation/kitchen/quiche)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_EGG, 9),
			reagent(REAGENT_ID_FLOUR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/quiche, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

//Baked sweets:
//---------------

/transformation/kitchen/cookie
CAPABILITIES(/transformation/kitchen/cookie)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 10),
			reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cookie, 4)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/ovenfortunecookie
CAPABILITIES(/transformation/kitchen/ovenfortunecookie)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/paper, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fortunecookie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/poppypretzel
CAPABILITIES(/transformation/kitchen/poppypretzel)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_POPPIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/poppypretzel, 2)),
		cooks_in = OVEN))

/transformation/kitchen/cracker
CAPABILITIES(/transformation/kitchen/cracker)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cracker, 1)),
		cooks_in = OVEN))

// No egg or mix in final recipe
/transformation/kitchen/brownies
CAPABILITIES(/transformation/kitchen/brownies)
	configure(transformation(takes = list(reagent(REAGENT_ID_BROWNIEMIX, 10),
			reagent(REAGENT_ID_EGG, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/brownies, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// No egg or mix in final recipe
/transformation/kitchen/cosmicbrownies
CAPABILITIES(/transformation/kitchen/cosmicbrownies)
	configure(transformation(takes = list(reagent(REAGENT_ID_BROWNIEMIX, 10),
			reagent(REAGENT_ID_EGG, 3),
			fruit_term(PLANT_AMBROSIA, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/cosmicbrownies, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/buchedenoel
CAPABILITIES(/transformation/kitchen/buchedenoel)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 20),
			reagent(REAGENT_ID_CREAM, 10),
			reagent(REAGENT_ID_COCO, 5),
			fruit_term(PLANT_BERRIES, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/buchedenoel, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cinnamonbun
CAPABILITIES(/transformation/kitchen/cinnamonbun)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 15),
			reagent(REAGENT_ID_CREAM, 10),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cinnamonbun, 4)),
		cooks_in = OVEN))

/transformation/kitchen/jaffacake
CAPABILITIES(/transformation/kitchen/jaffacake)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 15),
			reagent(REAGENT_ID_COCO, 10),
			fruit_term(PLANT_ORANGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jaffacake, 6)),
		cooks_in = OVEN))

//Pizzas
//=========================
/transformation/kitchen/pizzamargherita
CAPABILITIES(/transformation/kitchen/pizzamargherita)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita, 1)),
		cooks_in = OVEN))

/transformation/kitchen/meatpizza
CAPABILITIES(/transformation/kitchen/meatpizza)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/meatpizza, 1)),
		cooks_in = OVEN))

// Synthflesh spoiler
/transformation/kitchen/syntipizza
CAPABILITIES(/transformation/kitchen/syntipizza)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/meatpizza, 1)),
		cooks_in = OVEN,
		wiki = WIKI_SPOILER))

// No vomit taste in finished product from chanterelles
/transformation/kitchen/mushroompizza
CAPABILITIES(/transformation/kitchen/mushroompizza)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_MUSHROOMS, 5),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/mushroompizza, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/vegetablepizza
CAPABILITIES(/transformation/kitchen/vegetablepizza)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_EGGPLANT, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_CORN, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/vegetablepizza, 1)),
		cooks_in = OVEN))

/transformation/kitchen/pineapplepizza
CAPABILITIES(/transformation/kitchen/pineapplepizza)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/pineapple_ring, 1),
			item_term(/obj/item/reagent_containers/food/snacks/pineapple_ring, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/pizza/pineapple, 1)),
		cooks_in = OVEN))

//Spicy
//================

/transformation/kitchen/enchiladas
CAPABILITIES(/transformation/kitchen/enchiladas)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			fruit_term(PLANT_CHILI, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/enchiladas, 1)),
		cooks_in = OVEN))


// Cakes.
//============
/transformation/kitchen/cake
CAPABILITIES(/transformation/kitchen/cake)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			reagent(REAGENT_ID_VANILLA, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/plaincake, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/cake/carrot
CAPABILITIES(/transformation/kitchen/cake/carrot)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			fruit_term(PLANT_CARROT, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/carrotcake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/cheese
CAPABILITIES(/transformation/kitchen/cake/cheese)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/cheesecake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/peanut
CAPABILITIES(/transformation/kitchen/cake/peanut)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			reagent(REAGENT_ID_PEANUTBUTTER, 5),
			fruit_term(PLANT_PEANUT, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/peanutcake, 1))))

/transformation/kitchen/cake/orange
CAPABILITIES(/transformation/kitchen/cake/orange)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			fruit_term(PLANT_ORANGE, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/orangecake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/lime
CAPABILITIES(/transformation/kitchen/cake/lime)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			fruit_term(PLANT_LIME, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/limecake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/lemon
CAPABILITIES(/transformation/kitchen/cake/lemon)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			fruit_term(PLANT_LEMON, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/lemoncake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/chocolate
CAPABILITIES(/transformation/kitchen/cake/chocolate)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			reagent(REAGENT_ID_COCO, 5)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/chocolatecake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/birthday
CAPABILITIES(/transformation/kitchen/cake/birthday)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			item_term(/obj/item/clothing/head/cakehat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/birthdaycake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/apple
CAPABILITIES(/transformation/kitchen/cake/apple)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			fruit_term(PLANT_APPLE, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/applecake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cake/brain
CAPABILITIES(/transformation/kitchen/cake/brain)
	configure(transformation(takes = list(reagent(REAGENT_ID_CAKEBATTER, 30),
			item_term(/obj/item/organ/internal/brain, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/braincake, 1)),
		cooks_in = OVEN))

/transformation/kitchen/pancakes
CAPABILITIES(/transformation/kitchen/pancakes)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 15),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/pancakes, 2)),
		cooks_in = OVEN))

/transformation/kitchen/pancakes/berry
CAPABILITIES(/transformation/kitchen/pancakes/berry)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 15),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_BERRIES, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/pancakes/berry, 2)),
		cooks_in = OVEN))

/transformation/kitchen/lasagna
CAPABILITIES(/transformation/kitchen/lasagna)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			fruit_term(PLANT_TOMATO, 2),
			fruit_term(PLANT_EGGPLANT, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/lasagna, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/honeybun
CAPABILITIES(/transformation/kitchen/honeybun)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_EGG, 3),
			reagent(REAGENT_ID_HONEY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/honeybun, 4)),
		cooks_in = OVEN))

//Bacon
/transformation/kitchen/bacon_oven
CAPABILITIES(/transformation/kitchen/bacon_oven)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/spreads, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon/oven, 6)),
		cooks_in = OVEN))

/transformation/kitchen/meat_pocket
CAPABILITIES(/transformation/kitchen/meat_pocket)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meat_pocket, 2)),
		cooks_in = OVEN))

/transformation/kitchen/bacon_flatbread
CAPABILITIES(/transformation/kitchen/bacon_flatbread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			fruit_term(PLANT_TOMATO, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon_flatbread, 1)),
		cooks_in = OVEN))

/transformation/kitchen/truffle
CAPABILITIES(/transformation/kitchen/truffle)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_CREAM, 5),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/truffle, 4)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/croissant
CAPABILITIES(/transformation/kitchen/croissant)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_YEAST, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/croissant, 2)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/macncheese
CAPABILITIES(/transformation/kitchen/macncheese)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/macncheese, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/suppermatter
CAPABILITIES(/transformation/kitchen/suppermatter)
	configure(transformation(takes = list(reagent(REAGENT_ID_RADIUM, 5),
			reagent(REAGENT_ID_MILK, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/cheesecake, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/suppermatter, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/excitingsuppermatter
CAPABILITIES(/transformation/kitchen/excitingsuppermatter)
	configure(transformation(takes = list(reagent(REAGENT_ID_RADIUM, 5),
			reagent(REAGENT_ID_SPACESPICE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/cheesecake, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/excitingsuppermatter, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/waffles
CAPABILITIES(/transformation/kitchen/waffles)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/waffles, 2)),
		cooks_in = OVEN))

/transformation/kitchen/loadedbakedpotatooven
CAPABILITIES(/transformation/kitchen/loadedbakedpotatooven)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/loadedbakedpotato, 1)),
		cooks_in = OVEN))

// Water used up in cooking
/transformation/kitchen/meatbun
CAPABILITIES(/transformation/kitchen/meatbun)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatbun, 2)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// Water used up in cooking
/transformation/kitchen/spicedmeatbun
CAPABILITIES(/transformation/kitchen/spicedmeatbun)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawcutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/spicedmeatbun, 2)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// Water, egg used up in cooking
/transformation/kitchen/custardbun
CAPABILITIES(/transformation/kitchen/custardbun)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_EGG, 3),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/custardbun, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/chickenmomo
CAPABILITIES(/transformation/kitchen/chickenmomo)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/chicken, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chickenmomo, 2)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))

// Get that water outta here
/transformation/kitchen/veggiemomo
CAPABILITIES(/transformation/kitchen/veggiemomo)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/veggiemomo, 2)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))


/transformation/kitchen/buttspie
CAPABILITIES(/transformation/kitchen/buttspie)
	configure(transformation(takes = list(reagent(REAGENT_ID_CINNAMONPOWDER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/butterscotch, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/slicable/buttspie, 1)),
		cooks_in = OVEN))

/transformation/kitchen/cinnamon_roll
CAPABILITIES(/transformation/kitchen/cinnamon_roll)
	configure(transformation(takes = list(reagent(REAGENT_ID_CINNAMONPOWDER, 5),
			reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/spreads/butter, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cinnamonroll, 1)),
		cooks_in = OVEN))

// TODO: Possibly see if recipe can be in the candymaker?
/transformation/kitchen/spicy_boys
CAPABILITIES(/transformation/kitchen/spicy_boys)
	configure(transformation(takes = list(reagent(REAGENT_ID_CINNAMONPOWDER, 5),
			reagent(REAGENT_ID_SUGAR, 10),
			reagent(REAGENT_ID_CORNOIL, 10)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/spicy_boys, 6)),
		cooks_in = OVEN))

// TODO: Possibly see if recipe can be in the candymaker?
/transformation/kitchen/welders_original
CAPABILITIES(/transformation/kitchen/welders_original)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/butterscotch, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/welders_original, 6)),
		cooks_in = OVEN))

// No egg or mix in final recipe
/transformation/kitchen/blondies
CAPABILITIES(/transformation/kitchen/blondies)
	configure(transformation(takes = list(reagent(REAGENT_ID_BLONDIEMIX, 10),
			reagent(REAGENT_ID_EGG, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/blondies, 1)),
		cooks_in = OVEN,
		mix = RECIPE_REAGENT_REPLACE))


/transformation/kitchen/scorpion
CAPABILITIES(/transformation/kitchen/scorpion)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/scorpion, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/scorpion_cooked, 1)),
		cooks_in = OVEN))
